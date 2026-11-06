import XCTest
import FolderServeCore
@testable import FolderServe

final class InMemoryStore: ServerStoring {
    var saved: [ServerEntry] = []
    func load() -> [ServerEntry] { saved }
    func save(_ entries: [ServerEntry]) { saved = entries }
}

@MainActor
final class ServerManagerTests: XCTestCase {
    var store: InMemoryStore!
    var manager: ServerManager!
    var base: URL!
    var blockers: [StaticServer] = []
    var startPort: UInt16 = 0
    let fm = FileManager.default

    override func setUpWithError() throws {
        store = InMemoryStore()
        // A fresh port range per test: listeners from the previous test may still be shutting down.
        startPort = UInt16.random(in: 20_000...50_000)
        manager = ServerManager(store: store, defaultStartPort: startPort)
        base = fm.temporaryDirectory.appendingPathComponent("sm-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        manager.stopAll()
        blockers.forEach { $0.stop() }
        try? fm.removeItem(at: base)
    }

    private func folder(_ name: String = "site") throws -> URL {
        let url = base.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitFor(_ timeout: TimeInterval = 5, _ cond: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return cond()
    }

    private func expectEventually(file: StaticString = #filePath, line: UInt = #line, _ cond: () -> Bool) async {
        let ok = await waitFor(5, cond)
        XCTAssertTrue(ok, "condition not met in time", file: file, line: line)
    }

    private func fetch(_ port: UInt16, _ path: String = "/") async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return String(decoding: data, as: UTF8.self)
    }

    private func runningPort(_ id: UUID) -> UInt16? {
        if case .running(let p) = manager.statuses[id] { return p }
        return nil
    }

    func testAddStartsServerAndReportsRunning() async throws {
        let f = try folder()
        try "hello".write(to: f.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        let body = try await fetch(try XCTUnwrap(runningPort(id)), "/a.txt")
        XCTAssertEqual(body, "hello")
    }

    func testAddingSameFolderTwiceReturnsSameID() throws {
        let f = try folder()
        let a = manager.add(folder: f)
        let b = manager.add(folder: f)
        XCTAssertEqual(a, b)
        XCTAssertEqual(manager.entries.count, 1)
    }

    func testPortConflictPicksNextFreeAndSetsNotice() async throws {
        let blocker = StaticServer(root: base, port: startPort, options: ServeOptions())
        _ = try await blocker.start()
        blockers.append(blocker)
        let id = manager.add(folder: try folder())
        await expectEventually { runningPort(id) != nil }
        XCTAssertGreaterThan(try XCTUnwrap(runningPort(id)), startPort)
        XCTAssertNotNil(manager.notice)
    }

    func testPreferredPortTakenShowsError() async throws {
        let blocker = StaticServer(root: base, port: 0, options: ServeOptions())
        let taken = try await blocker.start()
        blockers.append(blocker)
        let id = manager.add(folder: try folder())
        await expectEventually { runningPort(id) != nil }
        manager.stop(id)
        manager.setPreferredPort(id, taken)
        await manager.startNow(id)
        guard case .error = manager.statuses[id] else { return XCTFail("expected error, got \(String(describing: manager.statuses[id]))") }
    }

    func testDeletedFolderShowsFolderMissing() async throws {
        let f = try folder()
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        manager.stop(id)
        try fm.removeItem(at: f)
        await manager.startNow(id)
        XCTAssertEqual(manager.statuses[id], .folderMissing)
    }

    func testPersistenceRoundTrip() throws {
        let f = try folder()
        let id = manager.add(folder: f)
        let reloaded = ServerManager(store: store, defaultStartPort: startPort)
        XCTAssertEqual(reloaded.entries.map(\.id), [id])
        XCTAssertEqual(reloaded.entries.first?.folderPath, f.standardizedFileURL.path)
        XCTAssertEqual(reloaded.statuses[id], .stopped)
    }

    func testDroppedFileServesParentAndReturnsOpenPath() async throws {
        let f = try folder()
        let file = f.appendingPathComponent("my page.html")
        try "<p>x</p>".write(to: file, atomically: true, encoding: .utf8)
        let (id, openPath) = manager.addDropped(url: file)
        XCTAssertEqual(manager.entries.first(where: { $0.id == id })?.folderPath, f.standardizedFileURL.path)
        XCTAssertEqual(openPath, "my%20page.html")
        await expectEventually { runningPort(id) != nil }
    }

    func testSetOptionsLiveUpdatesRunningServer() async throws {
        let f = try folder()
        try "<body>hi</body>".write(to: f.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        let port = try XCTUnwrap(runningPort(id))
        let on = try await fetch(port, "/index.html")
        XCTAssertTrue(on.contains("__reload"))
        var o = ServeOptions(); o.liveReload = false
        manager.setOptions(id, o)
        let off = try await fetch(port, "/index.html")
        XCTAssertFalse(off.contains("__reload"))
        XCTAssertEqual(store.saved.first?.options.liveReload, false)
    }

    func testStopAllStopsEverything() async throws {
        let a = manager.add(folder: try folder("a"))
        let b = manager.add(folder: try folder("b"))
        await expectEventually { runningPort(a) != nil && runningPort(b) != nil }
        manager.stopAll()
        XCTAssertEqual(manager.statuses[a], .stopped)
        XCTAssertEqual(manager.statuses[b], .stopped)
    }

    func testUserStopClearsAutoStartAndStopAllKeepsIt() async throws {
        let a = manager.add(folder: try folder("a"))
        let b = manager.add(folder: try folder("b"))
        await expectEventually { runningPort(a) != nil && runningPort(b) != nil }
        manager.stop(a)
        manager.stopAll()
        XCTAssertEqual(manager.entries.first(where: { $0.id == a })?.autoStart, false)
        XCTAssertEqual(manager.entries.first(where: { $0.id == b })?.autoStart, true)
        manager.startAutoStartEntries()
        await expectEventually { runningPort(b) != nil }
        XCTAssertEqual(manager.statuses[a], .stopped)
    }

    func testRequestsAreLogged() async throws {
        let f = try folder()
        try "x".write(to: f.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        _ = try await fetch(try XCTUnwrap(runningPort(id)), "/a.txt")
        await expectEventually { manager.log.contains { $0.serverID == id && $0.entry.path == "/a.txt" } }
    }
}
