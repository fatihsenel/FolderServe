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
        manager = ServerManager(store: store, defaultStartPort: startPort, minSearchDuration: 0)
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

    private func fetchStatus(_ port: UInt16, _ path: String) async throws -> (Int, String) {
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
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

    func testDetectsFrameworkWhenServerStarts() async throws {
        let f = try folder()
        try "{\"dependencies\": {\"vue\": \"3\"}}".write(to: f.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        XCTAssertEqual(manager.projectKinds[id], .vue)
        manager.remove(id)
        XCTAssertNil(manager.projectKinds[id])
    }

    func testAddingSameFolderTwiceReturnsSameID() throws {
        let f = try folder()
        let a = manager.add(folder: f)
        let b = manager.add(folder: f)
        XCTAssertEqual(a, b)
        XCTAssertEqual(manager.entries.count, 1)
    }

    func testPortConflictPicksNextFreePort() async throws {
        let blocker = StaticServer(root: base, port: startPort, options: ServeOptions())
        _ = try await blocker.start()
        blockers.append(blocker)
        let id = manager.add(folder: try folder())
        await expectEventually { runningPort(id) != nil }
        XCTAssertGreaterThan(try XCTUnwrap(runningPort(id)), startPort)
    }

    func testPortSearchIsShownThenSettlesOnRunning() async throws {
        let m = ServerManager(store: InMemoryStore(), defaultStartPort: startPort, minSearchDuration: 0.5)
        defer { m.stopAll() }
        let began = Date()
        let id = m.add(folder: try folder())
        var sawFinding = false
        let ok = await waitFor(5) {
            if case .finding = m.statuses[id] { sawFinding = true }
            if case .running = m.statuses[id] { return true }
            return false
        }
        XCTAssertTrue(ok)
        XCTAssertTrue(sawFinding, "the card should show the port search first")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 0.45, "search is held for the minimum duration")
    }

    func testPortSearchReportsBusyPortsAndLandedPort() async throws {
        let blocker = StaticServer(root: base, port: startPort, options: ServeOptions())
        _ = try await blocker.start()
        blockers.append(blocker)
        let m = ServerManager(store: InMemoryStore(), defaultStartPort: startPort, minSearchDuration: 0.6)
        defer { m.stopAll() }
        let id = m.add(folder: try folder())
        var search: PortSearch?
        _ = await waitFor(5) {
            if case .finding(let s) = m.statuses[id], s.landed != nil { search = s; return true }
            return false
        }
        let found = try XCTUnwrap(search)
        XCTAssertEqual(found.busy.first, startPort)
        XCTAssertGreaterThan(try XCTUnwrap(found.landed), startPort)
    }

    func testStopDuringSearchAnimationStaysStopped() async throws {
        let m = ServerManager(store: InMemoryStore(), defaultStartPort: startPort, minSearchDuration: 0.6)
        defer { m.stopAll() }
        let id = m.add(folder: try folder())
        _ = await waitFor(5) { if case .finding(let s) = m.statuses[id], s.landed != nil { return true } else { return false } }
        m.stop(id)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(m.statuses[id], .stopped)
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
        let reloaded = ServerManager(store: store, defaultStartPort: startPort, minSearchDuration: 0)
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

    func testGlobalDotfilesToggleAppliesToAllEntriesAndRunningServers() async throws {
        let suiteName = "fs-test-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let suite = UserDefaults(suiteName: suiteName)!
        manager = ServerManager(store: store, defaultStartPort: startPort, minSearchDuration: 0, defaults: suite)
        let f = try folder("a")
        try "secret".write(to: f.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        let id = manager.add(folder: f)
        await expectEventually { runningPort(id) != nil }
        let port = try XCTUnwrap(runningPort(id))
        let before = try await fetchStatus(port, "/.env")
        XCTAssertEqual(before.0, 403)

        manager.setServeDotfiles(true)
        XCTAssertTrue(manager.entries.allSatisfy { $0.options.serveDotfiles })
        let after = try await fetchStatus(port, "/.env")
        XCTAssertEqual(after.0, 200)
        XCTAssertEqual(after.1, "secret")

        let id2 = manager.add(folder: try folder("b"))
        XCTAssertEqual(manager.entries.first(where: { $0.id == id2 })?.options.serveDotfiles, true)
    }

    func testGlobalSettingsPersistInDefaults() throws {
        let suiteName = "fs-test-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let suite = UserDefaults(suiteName: suiteName)!
        let m = ServerManager(store: store, defaultStartPort: startPort, minSearchDuration: 0, defaults: suite)
        XCTAssertTrue(m.startServersAtLaunch)
        XCTAssertFalse(m.serveDotfiles)
        m.setServeDotfiles(true)
        m.startServersAtLaunch = false
        let again = ServerManager(store: store, defaultStartPort: startPort, minSearchDuration: 0, defaults: suite)
        XCTAssertTrue(again.serveDotfiles)
        XCTAssertFalse(again.startServersAtLaunch)
    }

    func testLogLinesFilterByServerNewestFirst() async throws {
        let fa = try folder("a"), fb = try folder("b")
        try "x".write(to: fa.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: fb.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)
        let a = manager.add(folder: fa), b = manager.add(folder: fb)
        await expectEventually { runningPort(a) != nil && runningPort(b) != nil }
        _ = try await fetch(try XCTUnwrap(runningPort(a)), "/one.txt")
        _ = try await fetch(try XCTUnwrap(runningPort(b)), "/two.txt")
        await expectEventually { manager.log.count >= 2 }
        XCTAssertEqual(manager.logLines(for: a).map(\.entry.path), ["/one.txt"])
        XCTAssertEqual(manager.logLines(for: b).map(\.entry.path), ["/two.txt"])
        XCTAssertEqual(manager.logLines(for: nil).map(\.entry.path), ["/two.txt", "/one.txt"])
    }
}
