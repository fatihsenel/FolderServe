import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class RecentFoldersTests: XCTestCase {
    var store: InMemoryStore!
    var recentsStore: InMemoryStore!
    var manager: ServerManager!
    var base: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        store = InMemoryStore()
        recentsStore = InMemoryStore()
        manager = makeManager()
        base = fm.temporaryDirectory.appendingPathComponent("rf-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        manager.stopAll()
        try? fm.removeItem(at: base)
    }

    private func makeManager() -> ServerManager {
        ServerManager(store: store, defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0, recentsStore: recentsStore)
    }

    private func folder(_ name: String) throws -> URL {
        let url = base.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testRemovedServerBecomesRecentAndIsSaved() throws {
        let id = manager.add(folder: try folder("site"))
        manager.remove(id)
        XCTAssertEqual(manager.recents.map(\.folderName), ["site"])
        XCTAssertEqual(recentsStore.saved.map(\.folderName), ["site"])
        XCTAssertEqual(recentsStore.saved.first?.autoStart, false)
    }

    func testNewestFirstAndCappedAndNoDuplicates() throws {
        for i in 0..<(ServerManager.maxRecents + 3) {
            let id = manager.add(folder: try folder("f\(i)"))
            manager.remove(id)
        }
        XCTAssertEqual(manager.recents.count, ServerManager.maxRecents)
        XCTAssertEqual(manager.recents.first?.folderName, "f\(ServerManager.maxRecents + 2)")
        // Removing the same folder twice keeps one copy, moved to the front.
        let again = manager.add(folder: try folder("f5"))
        manager.remove(again)
        XCTAssertEqual(manager.recents.filter { $0.folderName == "f5" }.count, 1)
        XCTAssertEqual(manager.recents.first?.folderName, "f5")
    }

    func testReopenServesAgainWithOldSettings() async throws {
        let id = manager.add(folder: try folder("site"))
        manager.rename(id, to: "My Site")
        var options = try XCTUnwrap(manager.entries.first?.options)
        options.cors = true
        manager.setOptions(id, options)
        manager.remove(id)
        let recent = try XCTUnwrap(manager.recents.first)

        let newID = await manager.reopenRecent(recent.id)
        XCTAssertNotNil(newID)
        XCTAssertTrue(manager.recents.isEmpty)
        XCTAssertTrue(recentsStore.saved.isEmpty)
        let entry = try XCTUnwrap(manager.entries.first)
        XCTAssertEqual(entry.displayName, "My Site")
        XCTAssertTrue(entry.options.cors)
        XCTAssertTrue(entry.autoStart)
        guard case .running = manager.statuses[entry.id] else { return XCTFail("not running: \(String(describing: manager.statuses[entry.id]))") }
        XCTAssertNotNil(manager.url(for: entry.id))
    }

    func testReopenUnknownIDDoesNothing() async {
        let result = await manager.reopenRecent(UUID())
        XCTAssertNil(result)
        XCTAssertTrue(manager.entries.isEmpty)
    }

    func testAddingFolderAgainRestoresItsSettingsAndDropsTheRecent() throws {
        let url = try folder("site")
        let id = manager.add(folder: url)
        manager.rename(id, to: "Renamed")
        manager.remove(id)
        XCTAssertEqual(manager.recents.count, 1)
        _ = manager.add(folder: url)
        XCTAssertTrue(manager.recents.isEmpty)
        XCTAssertEqual(manager.entries.first?.displayName, "Renamed")
    }

    func testForgetAndClear() throws {
        for name in ["a", "b", "c"] { manager.remove(manager.add(folder: try folder(name))) }
        let first = try XCTUnwrap(manager.recents.first)
        manager.forgetRecent(first.id)
        XCTAssertEqual(manager.recents.count, 2)
        manager.clearRecents()
        XCTAssertTrue(manager.recents.isEmpty)
        XCTAssertTrue(recentsStore.saved.isEmpty)
    }

    func testRecentsSurviveRelaunchButNotWhenFolderIsServedAgain() throws {
        manager.remove(manager.add(folder: try folder("gone")))
        let kept = manager.add(folder: try folder("kept"))
        manager.remove(kept)
        // "kept" was put back in the saved server list behind the recents file's back (e.g. an older build).
        store.saved = [try XCTUnwrap(manager.recents.first)]
        let reloaded = makeManager()
        XCTAssertEqual(reloaded.recents.map(\.folderName), ["gone"])
    }

    func testLocationShowsParentFolderName() {
        XCTAssertEqual(MenuBarRecents.location(of: "/Users/me/Projects/site"), "Projects")
    }
}
