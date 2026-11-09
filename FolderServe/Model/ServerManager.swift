import Foundation
import Observation
import os
import Security
import FolderServeCore

@MainActor @Observable
final class ServerManager {
    private(set) var entries: [ServerEntry] = []
    private(set) var statuses: [UUID: ServerStatus] = [:]
    /// Detected framework per folder; filled in when a server starts (needs folder access).
    private(set) var projectKinds: [UUID: ProjectKind] = [:]
    /// Folders just added or dropped again; the UI glows their cards for a moment.
    private(set) var highlightedIDs: Set<UUID> = []
    /// The most recent of them (the list scrolls to it).
    private(set) var lastHighlightedID: UUID?
    /// The folder the user asked to remove; the window shows a confirmation for it.
    private(set) var pendingRemoval: UUID?
    private(set) var log: [LogLine] = []
    /// Folders that were served before and then removed from the list, newest first (the menu bar offers them for one-click reuse).
    private(set) var recents: [ServerEntry] = []
    static let maxRecents = 6
    /// Failed requests per server that the user has not looked at yet (the menu bar icon shows their total).
    private(set) var unseenErrors: [UUID: Int] = [:]
    /// Goes up with every logged request; the menu bar icon pulses when it changes.
    private(set) var requestTick = 0
    /// Set by the menu bar: the main window opens Activity on this server and status, then clears it.
    var activityRequest: ActivityRequest?
    /// Global setting: serve dotfiles (e.g. .env) from every folder. Off by default.
    private(set) var serveDotfiles: Bool
    /// Global setting: start the servers that were running when the app last quit.
    var startServersAtLaunch: Bool {
        didSet { defaults.set(startServersAtLaunch, forKey: Self.startAtLaunchKey) }
    }

    @ObservationIgnored private let store: ServerStoring
    @ObservationIgnored private let recentsStore: ServerStoring?
    @ObservationIgnored private let defaultStartPort: UInt16
    @ObservationIgnored private let minSearchDuration: TimeInterval
    @ObservationIgnored private let bodyBudget: Int
    @ObservationIgnored private let highlightDuration: TimeInterval
    @ObservationIgnored private var highlightTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let certificateDirectory: URL
    @ObservationIgnored private var cachedIdentity: SecIdentity?
    private static let dotfilesKey = "serveDotfiles"
    private static let startAtLaunchKey = "startServersAtLaunch"
    @ObservationIgnored private var servers: [UUID: StaticServer] = [:]
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var starting: Set<UUID> = []
    private static let maxLogLines = 500
    private static let logger = Logger(subsystem: "com.fatihsenel.FolderServe", category: "servers")

    init(store: ServerStoring, defaultStartPort: UInt16 = 8080, minSearchDuration: TimeInterval = 1.5,
         bodyBudget: Int = 20 * 1024 * 1024, highlightDuration: TimeInterval = 2.2,
         defaults: UserDefaults = .standard, certificateDirectory: URL? = nil, recentsStore: ServerStoring? = nil) {
        self.certificateDirectory = certificateDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FolderServe/Certificates")
        self.store = store
        self.recentsStore = recentsStore
        self.highlightDuration = highlightDuration
        self.bodyBudget = bodyBudget
        self.minSearchDuration = minSearchDuration
        self.defaultStartPort = defaultStartPort
        self.defaults = defaults
        self.serveDotfiles = defaults.bool(forKey: Self.dotfilesKey)
        self.startServersAtLaunch = defaults.object(forKey: Self.startAtLaunchKey) as? Bool ?? true
        entries = store.load()
        for e in entries { statuses[e.id] = .stopped }
        let active = Set(entries.map(\.folderPath))
        recents = Array((recentsStore?.load() ?? []).filter { !active.contains($0.folderPath) }.prefix(Self.maxRecents))
    }

    func url(for id: UUID) -> URL? {
        if case .running(let port) = statuses[id] {
            let secure = entries.first { $0.id == id }?.options.https == true
            return URL(string: "\(secure ? "https" : "http")://\(hostName(for: id)):\(port)/")
        }
        return nil
    }

    /// The address the Open button uses: the server's URL plus the folder's "Open at" page.
    func openURL(for id: UUID) -> URL? {
        guard let base = url(for: id) else { return nil }
        return BrowserOpener.target(base: base, path: entries.first { $0.id == id }?.options.openPath ?? "")
    }

    /// `127.0.0.1`, or `name.localhost` when the folder's friendly address is on.
    func hostName(for id: UUID) -> String {
        guard let entry = entries.first(where: { $0.id == id }), entry.options.friendlyHost else { return "127.0.0.1" }
        return HostSlug.make(entry.displayName) + ".localhost"
    }

    /// Addresses other devices can use while the folder is shared on the network (empty otherwise).
    func lanURLs(for id: UUID) -> [URL] {
        guard case .running(let port) = statuses[id], let options = entries.first(where: { $0.id == id })?.options,
              options.shareOnNetwork else { return [] }
        let scheme = options.https ? "https" : "http"
        return LANAddress.ipv4Addresses().compactMap { URL(string: "\(scheme)://\($0):\(port)/") }
    }

    // MARK: - Adding / removing

    @discardableResult
    /// Makes the folder's card glow for a moment (new folder, or one that was dropped again).
    func highlight(_ id: UUID) {
        highlightedIDs.insert(id)
        lastHighlightedID = id
        highlightTasks[id]?.cancel()
        highlightTasks[id] = Task { [weak self, highlightDuration] in
            try? await Task.sleep(for: .seconds(highlightDuration))
            guard !Task.isCancelled else { return }
            self?.highlightedIDs.remove(id)
            self?.highlightTasks[id] = nil
        }
    }

    func add(folder: URL) -> UUID {
        let path = folder.standardizedFileURL.path
        if let existing = entries.first(where: { $0.folderPath == path }) {
            highlight(existing.id)
            Task { await startNow(existing.id) }
            return existing.id
        }
        var entry = ServerEntry(id: UUID(), bookmark: Self.makeBookmark(folder), folderPath: path,
                                preferredPort: nil, options: ServeOptions(serveDotfiles: serveDotfiles), autoStart: true)
        if let old = recents.first(where: { $0.folderPath == path }) {   // served before: keep its name, port and options
            entry.customName = old.customName; entry.preferredPort = old.preferredPort
            entry.options = old.options; entry.pinnedStart = old.pinnedStart
            recents.removeAll { $0.folderPath == path }
            persistRecents()
        }
        entries.append(entry)
        statuses[entry.id] = .stopped
        persist()
        highlight(entry.id)
        Task { await startNow(entry.id) }
        return entry.id
    }

    /// A dropped folder is served directly; a dropped file serves its parent folder and returns
    /// the file's URL path (percent-encoded, no leading slash) so the caller can open it.
    func addDropped(url: URL) -> (id: UUID, openPath: String?) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue { return (add(folder: url), nil) }
        let id = add(folder: url.deletingLastPathComponent())
        return (id, url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed))
    }

    /// Asks for confirmation (shown by the main window); nothing is removed until `confirmRemoval()`.
    func requestRemoval(_ id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        pendingRemoval = id
    }

    func cancelRemoval() { pendingRemoval = nil }

    func confirmRemoval() {
        guard let id = pendingRemoval else { return }
        pendingRemoval = nil
        remove(id)
    }

    func remove(_ id: UUID) {
        if pendingRemoval == id { pendingRemoval = nil }
        teardown(id)
        if let entry = entries.first(where: { $0.id == id }) { remember(entry) }
        entries.removeAll { $0.id == id }
        statuses[id] = nil
        projectKinds[id] = nil
        unseenErrors[id] = nil
        persist()
    }

    // MARK: - Recent folders

    private func remember(_ entry: ServerEntry) {
        var old = entry
        old.autoStart = false
        recents.removeAll { $0.folderPath == entry.folderPath }
        recents.insert(old, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persistRecents()
    }

    /// Serves a recent folder again with the name, port and options it had, using the access saved with it.
    /// Returns the new server's id (nil when the recent is unknown or the folder is already served).
    @discardableResult
    func reopenRecent(_ id: UUID) async -> UUID? {
        guard let old = recents.first(where: { $0.id == id }) else { return nil }
        recents.removeAll { $0.id == id }
        persistRecents()
        if let existing = entries.first(where: { $0.folderPath == old.folderPath }) {
            highlight(existing.id)
            await startNow(existing.id)
            return existing.id
        }
        var entry = old
        entry.autoStart = true
        entries.append(entry)
        statuses[entry.id] = .stopped
        persist()
        highlight(entry.id)
        await startNow(entry.id)
        return entry.id
    }

    func forgetRecent(_ id: UUID) {
        recents.removeAll { $0.id == id }
        persistRecents()
    }

    func clearRecents() {
        recents = []
        persistRecents()
    }

    func relocate(_ id: UUID, to folder: URL) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        teardown(id)
        entries[i].bookmark = Self.makeBookmark(folder)
        entries[i].folderPath = folder.standardizedFileURL.path
        entries[i].autoStart = true
        persist()
        Task { await startNow(id) }
    }

    // MARK: - Start / stop

    /// User-initiated start (remembered across launches).
    func start(_ id: UUID) {
        setAutoStart(id, true)
        Task { await startNow(id) }
    }

    /// User-initiated stop (the server stays stopped after the next launch).
    func stop(_ id: UUID) {
        teardown(id)
        statuses[id] = .stopped
        unseenErrors[id] = nil
        setAutoStart(id, false)
    }

    /// App teardown: stops everything but keeps the "was running" intent for the next launch.
    func stopAll() {
        for id in Array(servers.keys) {
            teardown(id)
            statuses[id] = .stopped
        }
    }

    /// `pinnedOnly`: just the folders marked "always start" (used when restoring the previous session is switched off).
    func startAutoStartEntries(pinnedOnly: Bool = false) {
        for e in entries where e.startsAlways || (!pinnedOnly && e.autoStart) { Task { await startNow(e.id) } }
    }

    func setAlwaysStart(_ id: UUID, _ value: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].startsAlways != value else { return }
        entries[i].pinnedStart = value ? true : nil
        persist()
    }

    func setOptions(_ id: UUID, _ options: ServeOptions) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        let listenerChanged = entries[i].options.https != options.https
            || entries[i].options.shareOnNetwork != options.shareOnNetwork
        entries[i].options = options
        servers[id]?.updateOptions(options)
        persist()
        if listenerChanged, servers[id] != nil {   // http ⇄ https, loopback ⇄ all interfaces: needs a new listener
            teardown(id)
            Task { await startNow(id) }
        }
    }

    func setServeDotfiles(_ value: Bool) {
        serveDotfiles = value
        defaults.set(value, forKey: Self.dotfilesKey)
        for entry in entries {
            var options = entry.options
            options.serveDotfiles = value
            setOptions(entry.id, options)
        }
    }

    /// Request log, newest first; pass a server id to filter to that server.
    func logLines(for serverID: UUID?) -> [LogLine] {
        let lines = serverID.map { id in log.filter { $0.serverID == id } } ?? log
        return lines.reversed()
    }

    /// Removes logged requests: one server's, or everything when `serverID` is nil.
    func clearLog(for serverID: UUID?) {
        if let serverID { log.removeAll { $0.serverID == serverID }; unseenErrors[serverID] = nil } else { log.removeAll(); unseenErrors = [:] }
    }

    // MARK: - Menu bar helpers

    /// Failed requests nobody has looked at yet, over all servers.
    var unseenErrorTotal: Int { unseenErrors.values.reduce(0, +) }

    /// Servers that could not start or stopped with an error (their row shows the message).
    var failedServerCount: Int { statuses.values.filter { if case .error = $0 { return true } else { return false } }.count }

    /// What the menu bar icon counts: unseen failed requests plus servers that failed to start.
    var attentionCount: Int { unseenErrorTotal + failedServerCount }

    /// The user has seen (or dealt with) this server's failures.
    func markErrorsSeen(_ id: UUID) { unseenErrors[id] = nil }

    /// Asks the main window to show Activity for one server, filtered by status.
    func showActivity(for id: UUID, status: StatusFilter = .any) {
        activityRequest = ActivityRequest(serverID: id, status: status)
    }

    /// Turns Share on or off for a server (restarts it when it runs, like the card's toggle).
    func toggleShare(_ id: UUID) {
        guard var options = entries.first(where: { $0.id == id })?.options else { return }
        options.shareOnNetwork.toggle()
        setOptions(id, options)
    }

    /// Replaces the folder's API proxy rules (applied to a running server immediately).
    func setProxyRules(_ id: UUID, _ rules: [ProxyRule]) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        var options = entries[i].options
        options.proxyRules = rules
        setOptions(id, options)
    }

    static let maxNameLength = 60

    /// Trimmed, length-limited label; nil (= use the folder name) when empty or equal to the folder name.
    static func normalizedName(_ raw: String, folderName: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(trimmed.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return limited.isEmpty || limited == folderName ? nil : limited
    }

    /// Renames the card's label only; the folder on disk and the URL stay the same.
    func rename(_ id: UUID, to name: String) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].customName = Self.normalizedName(name, folderName: entries[i].folderName)
        persist()
    }

    func setPreferredPort(_ id: UUID, _ port: UInt16?) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].preferredPort = port
        persist()
    }

    /// A server for the folder; with HTTPS on it carries the (created-on-demand) local certificate.
    private func makeServer(root: URL, port: UInt16, entry: ServerEntry) throws -> StaticServer {
        guard entry.options.https else { return StaticServer(root: root, port: port, options: entry.options) }
        if cachedIdentity == nil { cachedIdentity = try LocalCertificate.identity(in: certificateDirectory) }
        return StaticServer(root: root, port: port, options: entry.options, identity: cachedIdentity)
    }

    func startNow(_ id: UUID) async {
        guard servers[id] == nil, !starting.contains(id), let entry = entries.first(where: { $0.id == id }) else { return }
        starting.insert(id)
        defer { starting.remove(id) }

        guard let folder = accessFolder(for: entry) else {
            Self.logger.error("Cannot access folder \(entry.folderPath, privacy: .public)")
            statuses[id] = .folderMissing
            return
        }
        projectKinds[id] = ProjectDetector.detect(root: folder)
        if let wanted = entry.preferredPort {
            do {
                let server = try makeServer(root: folder, port: wanted, entry: entry)
                let port = try await server.start()
                attach(server, id: id, port: port)
            } catch StaticServerError.portInUse {
                releaseScope(id)
                statuses[id] = .error("Port \(wanted) is already in use")
            } catch {
                releaseScope(id)
                statuses[id] = .error("Could not start: \(error)")
            }
            return
        }

        var candidate = defaultStartPort
        var busy: [UInt16] = []
        let began = Date()
        let animate = minSearchDuration > 0
        if animate { statuses[id] = .finding(PortSearch(busy: [], landed: nil, began: began, duration: minSearchDuration)) }
        func publish(landed: UInt16? = nil) {
            guard animate else { return }
            statuses[id] = .finding(PortSearch(busy: Array(busy.suffix(12)), landed: landed, began: began, duration: minSearchDuration))
        }
        for _ in 0..<10 {
            guard let free = PortFinder.firstFree(startingAt: candidate) else { break }
            if free > candidate { busy.append(contentsOf: candidate..<free) }   // ports PortFinder skipped because they are in use
            do {
                let server = try makeServer(root: folder, port: free, entry: entry)
                let port = try await server.start()
                attach(server, id: id, port: port, searching: animate)
                if animate {
                    publish(landed: port)
                    let remaining = minSearchDuration - Date().timeIntervalSince(began)
                    if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                    // Only finish if the user did not stop or remove it while the animation played.
                    if servers[id] === server, case .finding = statuses[id] { statuses[id] = .running(port: port) }
                }
                return
            } catch StaticServerError.portInUse {
                busy.append(free)
                publish()
                guard free < UInt16.max else { break }
                candidate = free + 1
            } catch is LocalCertificateError {
                releaseScope(id)
                statuses[id] = .error("Could not create the HTTPS certificate")
                return
            } catch {
                break
            }
        }
        releaseScope(id)
        statuses[id] = .error("No free port available")
    }

    // MARK: - Internals

    private func attach(_ server: StaticServer, id: UUID, port: UInt16, searching: Bool = false) {
        server.onRequest = { [weak self] entry in
            Task { @MainActor in self?.append(LogLine(serverID: id, entry: entry)) }
        }
        servers[id] = server
        if !searching { statuses[id] = .running(port: port) }
    }

    func append(_ line: LogLine) {
        log.append(line)
        requestTick &+= 1
        if line.entry.countsAsUnseenError { unseenErrors[line.serverID, default: 0] += 1 }
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
        if line.entry.capturedBodyBytes > 0 { enforceBodyBudget() }
    }

    /// Captured request/response bodies live in memory only. When they add up to more than the budget,
    /// the oldest requests lose their bodies (their headers stay).
    private func enforceBodyBudget() {
        var total = log.reduce(0) { $0 + $1.entry.capturedBodyBytes }
        guard total > bodyBudget else { return }
        for i in log.indices {
            if total <= bodyBudget { break }
            let n = log[i].entry.capturedBodyBytes
            guard n > 0 else { continue }
            log[i].entry.requestBody = nil
            log[i].entry.responseBody = nil
            log[i].entry.bodiesDropped = true
            total -= n
        }
    }

    /// Reads (up to `limit` bytes of) the file that answered a static request, for the details panel.
    /// Only files inside a folder this app serves are read, and only while that folder is accessible.
    nonisolated static func readServedFile(path: String, folderPath: String, limit: Int) -> (data: Data, totalSize: Int64)? {
        let root = URL(fileURLWithPath: folderPath).resolvingSymlinksInPath().path
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard file.path.hasPrefix(root + "/"),
              let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return (data, Int64(size))
    }

    func folderPath(for serverID: UUID) -> String? { entries.first { $0.id == serverID }?.folderPath }

    private func teardown(_ id: UUID) {
        servers[id]?.stop()
        servers[id] = nil
        releaseScope(id)
    }

    private func releaseScope(_ id: UUID) {
        scopedURLs[id]?.stopAccessingSecurityScopedResource()
        scopedURLs[id] = nil
    }

    private func setAutoStart(_ id: UUID, _ value: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].autoStart != value else { return }
        entries[i].autoStart = value
        persist()
    }

    private func persist() { store.save(entries) }
    private func persistRecents() { recentsStore?.save(recents) }

    private static func makeBookmark(_ folder: URL) -> Data {
        (try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
    }

    /// Resolves the entry's folder (bookmark first) and begins security-scoped access.
    /// Returns nil when the folder is gone or its bookmark cannot be resolved.
    private func accessFolder(for entry: ServerEntry) -> URL? {
        var url = URL(fileURLWithPath: entry.folderPath)
        var scoped = false
        if !entry.bookmark.isEmpty {
            var stale = false
            do {
                _ = try URL(resolvingBookmarkData: entry.bookmark, options: .withSecurityScope,
                            relativeTo: nil, bookmarkDataIsStale: &stale)
            } catch {
                Self.logger.error("Bookmark resolve failed: \(String(describing: error), privacy: .public)")
                return nil
            }
            guard let resolved = try? URL(resolvingBookmarkData: entry.bookmark, options: .withSecurityScope,
                                          relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
            url = resolved
            scoped = resolved.startAccessingSecurityScopedResource()
            if let i = entries.firstIndex(where: { $0.id == entry.id }) {
                var changed = false
                if stale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    entries[i].bookmark = fresh; changed = true
                }
                if entries[i].folderPath != resolved.standardizedFileURL.path {
                    entries[i].folderPath = resolved.standardizedFileURL.path; changed = true
                }
                if changed { persist() }
            }
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            Self.logger.error("Folder not readable: \(url.path, privacy: .public) scoped=\(scoped)")
            if scoped { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if scoped { scopedURLs[entry.id] = url }
        return url
    }
}

#if DEBUG
extension ServerManager {
    /// Seeds state for SwiftUI previews and snapshot tests without starting real servers.
    func loadPreview(entries: [ServerEntry], statuses: [UUID: ServerStatus], log: [LogLine] = [], kinds: [UUID: ProjectKind] = [:],
                     recents: [ServerEntry] = []) {
        self.recents = recents
        self.projectKinds = kinds
        self.entries = entries
        self.statuses = statuses
        self.log = log
        self.unseenErrors = log.filter { $0.entry.countsAsUnseenError }.reduce(into: [:]) { $0[$1.serverID, default: 0] += 1 }
    }
}
#endif
