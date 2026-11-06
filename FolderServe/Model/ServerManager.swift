import Foundation
import Observation
import FolderServeCore

@MainActor @Observable
final class ServerManager {
    private(set) var entries: [ServerEntry] = []
    private(set) var statuses: [UUID: ServerStatus] = [:]
    var notice: String?
    private(set) var log: [LogLine] = []

    @ObservationIgnored private let store: ServerStoring
    @ObservationIgnored private let defaultStartPort: UInt16
    @ObservationIgnored private var servers: [UUID: StaticServer] = [:]
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var starting: Set<UUID> = []
    private static let maxLogLines = 500

    init(store: ServerStoring, defaultStartPort: UInt16 = 8080) {
        self.store = store
        self.defaultStartPort = defaultStartPort
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
                                preferredPort: nil, options: ServeOptions(), autoStart: true)
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
            statuses[id] = .folderMissing
            return
        }
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
        for _ in 0..<10 {
            guard let free = PortFinder.firstFree(startingAt: candidate) else { break }
            let server = StaticServer(root: folder, port: free, options: entry.options)
            do {
                let port = try await server.start()
                if port != defaultStartPort { notice = "Port \(defaultStartPort) was busy — \(entry.displayName) is using \(port)." }
                attach(server, id: id, port: port)
                return
            } catch StaticServerError.portInUse {
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

    private func attach(_ server: StaticServer, id: UUID, port: UInt16) {
        server.onRequest = { [weak self] entry in
            Task { @MainActor in self?.append(LogLine(serverID: id, entry: entry)) }
        }
        servers[id] = server
        statuses[id] = .running(port: port)
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
            if scoped { url.stopAccessingSecurityScopedResource() }
            return nil
        }
        if scoped { scopedURLs[entry.id] = url }
        return url
    }
}
