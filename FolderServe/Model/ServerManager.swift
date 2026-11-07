import Foundation
import Observation
import os
import FolderServeCore

@MainActor @Observable
final class ServerManager {
    private(set) var entries: [ServerEntry] = []
    private(set) var statuses: [UUID: ServerStatus] = [:]
    /// Detected framework per folder; filled in when a server starts (needs folder access).
    private(set) var projectKinds: [UUID: ProjectKind] = [:]
    private(set) var log: [LogLine] = []
    /// Global setting: serve dotfiles (e.g. .env) from every folder. Off by default.
    private(set) var serveDotfiles: Bool
    /// Global setting: start the servers that were running when the app last quit.
    var startServersAtLaunch: Bool {
        didSet { defaults.set(startServersAtLaunch, forKey: Self.startAtLaunchKey) }
    }

    @ObservationIgnored private let store: ServerStoring
    @ObservationIgnored private let defaultStartPort: UInt16
    @ObservationIgnored private let minSearchDuration: TimeInterval
    @ObservationIgnored private let defaults: UserDefaults
    private static let dotfilesKey = "serveDotfiles"
    private static let startAtLaunchKey = "startServersAtLaunch"
    @ObservationIgnored private var servers: [UUID: StaticServer] = [:]
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var starting: Set<UUID> = []
    private static let maxLogLines = 500
    private static let logger = Logger(subsystem: "com.fatihsenel.FolderServe", category: "servers")

    init(store: ServerStoring, defaultStartPort: UInt16 = 8080, minSearchDuration: TimeInterval = 1.5,
         defaults: UserDefaults = .standard) {
        self.store = store
        self.minSearchDuration = minSearchDuration
        self.defaultStartPort = defaultStartPort
        self.defaults = defaults
        self.serveDotfiles = defaults.bool(forKey: Self.dotfilesKey)
        self.startServersAtLaunch = defaults.object(forKey: Self.startAtLaunchKey) as? Bool ?? true
        entries = store.load()
        for e in entries { statuses[e.id] = .stopped }
    }

    func url(for id: UUID) -> URL? {
        if case .running(let port) = statuses[id] { return URL(string: "http://127.0.0.1:\(port)/") }
        return nil
    }

    // MARK: - Adding / removing

    @discardableResult
    func add(folder: URL) -> UUID {
        let path = folder.standardizedFileURL.path
        if let existing = entries.first(where: { $0.folderPath == path }) {
            Task { await startNow(existing.id) }
            return existing.id
        }
        let entry = ServerEntry(id: UUID(), bookmark: Self.makeBookmark(folder), folderPath: path,
                                preferredPort: nil, options: ServeOptions(serveDotfiles: serveDotfiles), autoStart: true)
        entries.append(entry)
        statuses[entry.id] = .stopped
        persist()
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

    func remove(_ id: UUID) {
        teardown(id)
        entries.removeAll { $0.id == id }
        statuses[id] = nil
        projectKinds[id] = nil
        persist()
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
        setAutoStart(id, false)
    }

    /// App teardown: stops everything but keeps the "was running" intent for the next launch.
    func stopAll() {
        for id in Array(servers.keys) {
            teardown(id)
            statuses[id] = .stopped
        }
    }

    func startAutoStartEntries() {
        for e in entries where e.autoStart { Task { await startNow(e.id) } }
    }

    func setOptions(_ id: UUID, _ options: ServeOptions) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].options = options
        servers[id]?.updateOptions(options)
        persist()
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
            let server = StaticServer(root: folder, port: wanted, options: entry.options)
            do {
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
            let server = StaticServer(root: folder, port: free, options: entry.options)
            do {
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

    private func append(_ line: LogLine) {
        log.append(line)
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
    }

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

    private static func makeBookmark(_ folder: URL) -> Data {
        (try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? Data()
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
                if stale, let fresh = try? resolved.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
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
    func loadPreview(entries: [ServerEntry], statuses: [UUID: ServerStatus], log: [LogLine] = [], kinds: [UUID: ProjectKind] = [:]) {
        self.projectKinds = kinds
        self.entries = entries
        self.statuses = statuses
        self.log = log
    }
}
#endif
