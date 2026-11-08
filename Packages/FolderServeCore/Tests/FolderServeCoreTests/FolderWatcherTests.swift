import XCTest
@testable import FolderServeCore

final class FolderWatcherTests: XCTestCase {
    var dir: URL!
    var watcher: FolderWatcher?
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("fw-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("nested/deeper"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        watcher?.stop()
        try? fm.removeItem(at: dir)
    }

    private func startWatcher(_ counter: LockedBox<Int>) async throws {
        watcher = FolderWatcher(root: dir, debounce: 0.1) { counter.value += 1 }
        watcher?.start()
        // FSEvents can still report the fixture setup that happened just before the stream started;
        // let that settle, then count only what the test itself does.
        try await Task.sleep(nanoseconds: 1_000_000_000)
        counter.value = 0
    }

    func testBurstOfWritesFiresOnce() async throws {
        let count = LockedBox(0)
        try await startWatcher(count)
        for i in 0..<5 { try "v\(i)".write(to: dir.appendingPathComponent("a.txt"), atomically: false, encoding: .utf8) }
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(count.value, 1)
    }

    func testNestedChangeFires() async throws {
        let count = LockedBox(0)
        try await startWatcher(count)
        try "x".write(to: dir.appendingPathComponent("nested/deeper/b.txt"), atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertGreaterThanOrEqual(count.value, 1)
    }

    func testGitDirectoryChangesAreIgnored() async throws {
        let count = LockedBox(0)
        try await startWatcher(count)
        try "x".write(to: dir.appendingPathComponent(".git/index"), atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(count.value, 0)
    }

    func testStopPreventsFurtherCallbacks() async throws {
        let count = LockedBox(0)
        try await startWatcher(count)
        watcher?.stop()
        try "x".write(to: dir.appendingPathComponent("c.txt"), atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(count.value, 0)
    }

    func testCallbackReceivesTheChangedPathsOfTheBurst() async throws {
        let seen = LockedBox([String]())
        watcher = FolderWatcher(root: dir, debounce: 0.1) { (paths: [String]) in seen.value += paths }
        watcher?.start()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        seen.value = []
        try "x".write(to: dir.appendingPathComponent("nested/style.css"), atomically: false, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent(".git/index"), atomically: false, encoding: .utf8)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertTrue(seen.value.contains { $0.hasSuffix("/nested/style.css") }, "\(seen.value)")
        XCTAssertFalse(seen.value.contains { $0.contains("/.git") })
    }
}
