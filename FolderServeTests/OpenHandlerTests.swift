import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class OpenHandlerTests: XCTestCase {
    var manager: ServerManager!
    var base: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        base = fm.temporaryDirectory.appendingPathComponent("oh-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        manager.stopAll()
        try? fm.removeItem(at: base)
    }

    func testOpeningFolderAddsServerWithoutOpeningBrowser() async throws {
        var opened: [URL] = []
        await FolderServeAppDelegate.handleOpen(urls: [base], manager: manager) { opened.append($0) }
        XCTAssertEqual(manager.entries.map(\.folderPath), [base.standardizedFileURL.path])
        XCTAssertTrue(opened.isEmpty)
    }

    func testOpeningFileServesParentAndOpensItsURL() async throws {
        let file = base.appendingPathComponent("my page.html")
        try "<p>x</p>".write(to: file, atomically: true, encoding: .utf8)
        var opened: [URL] = []
        await FolderServeAppDelegate.handleOpen(urls: [file], manager: manager) { opened.append($0) }
        let id = try XCTUnwrap(manager.entries.first?.id)
        guard case .running(let port) = manager.statuses[id] else { return XCTFail("server not running") }
        XCTAssertEqual(opened, [URL(string: "http://127.0.0.1:\(port)/my%20page.html")!])
    }

    func testOpeningMultipleFoldersAddsAll() async throws {
        let a = base.appendingPathComponent("a"), b = base.appendingPathComponent("b")
        try fm.createDirectory(at: a, withIntermediateDirectories: true)
        try fm.createDirectory(at: b, withIntermediateDirectories: true)
        await FolderServeAppDelegate.handleOpen(urls: [a, b], manager: manager) { _ in }
        XCTAssertEqual(Set(manager.entries.map(\.folderPath)), [a.standardizedFileURL.path, b.standardizedFileURL.path])
    }

    func testNonFileURLsAreIgnored() async throws {
        await FolderServeAppDelegate.handleOpen(urls: [URL(string: "https://example.com")!], manager: manager) { _ in }
        XCTAssertTrue(manager.entries.isEmpty)
    }
}
