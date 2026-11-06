import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class RestoreTests: XCTestCase {
    var store: InMemoryStore!
    var base: URL!
    var created: [ServerManager] = []
    let fm = FileManager.default

    override func setUpWithError() throws {
        store = InMemoryStore()
        base = fm.temporaryDirectory.appendingPathComponent("rs-\(UUID().uuidString)")
        try fm.createDirectory(at: base.appendingPathComponent("site"), withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        created.forEach { $0.stopAll() }
        try? fm.removeItem(at: base)
    }

    private func makeManager(defaults: UserDefaults) -> ServerManager {
        let m = ServerManager(store: store, defaultStartPort: UInt16.random(in: 20_000...50_000), defaults: defaults)
        created.append(m)
        return m
    }

    private func freshDefaults() -> UserDefaults {
        let name = "fs-restore-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    private func isRunning(_ m: ServerManager, _ id: UUID) -> Bool {
        if case .running = m.statuses[id] { return true } else { return false }
    }

    private func waitUntil(_ cond: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline { if cond() { return true }; try? await Task.sleep(nanoseconds: 20_000_000) }
        return cond()
    }

    func testRestoreStartsServersThatWereRunning() async throws {
        let defaults = freshDefaults()
        let first = makeManager(defaults: defaults)
        let id = first.add(folder: base.appendingPathComponent("site"))
        let up = await waitUntil { isRunning(first, id) }
        XCTAssertTrue(up)
        first.stopAll()   // app quit: intent to run again is kept

        let relaunched = makeManager(defaults: defaults)
        XCTAssertEqual(relaunched.statuses[id], .stopped)
        FolderServeAppDelegate.restoreServers(manager: relaunched)
        let restored = await waitUntil { isRunning(relaunched, id) }
        XCTAssertTrue(restored)
    }

    func testRestoreDoesNothingWhenStartAtLaunchIsOff() async throws {
        let defaults = freshDefaults()
        let first = makeManager(defaults: defaults)
        let id = first.add(folder: base.appendingPathComponent("site"))
        let up = await waitUntil { isRunning(first, id) }
        XCTAssertTrue(up)
        first.startServersAtLaunch = false
        first.stopAll()

        let relaunched = makeManager(defaults: defaults)
        FolderServeAppDelegate.restoreServers(manager: relaunched)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(relaunched.statuses[id], .stopped)
    }
}
