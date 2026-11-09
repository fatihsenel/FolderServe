import XCTest
import SwiftUI
import FolderServeCore
@testable import FolderServe

@MainActor
final class MockTests: XCTestCase {
    var manager: ServerManager!
    var store: InMemoryStore!
    var base: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        store = InMemoryStore()
        manager = ServerManager(store: store, defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        base = fm.temporaryDirectory.appendingPathComponent("mk-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try #"{"real":true}"#.write(to: base.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        manager.stopAll()
        try? fm.removeItem(at: base)
    }

    private func get(_ url: URL) async throws -> (String, Int) {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession(configuration: config).data(from: url)
        return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    func testAddingAMockIsSavedAndAppliesToTheRunningServer() async throws {
        let id = manager.add(folder: base)
        await manager.startNow(id)
        let url = try XCTUnwrap(manager.url(for: id)).appendingPathComponent("data.json")
        let before = try await get(url)
        XCTAssertEqual(before.0, #"{"real":true}"#)

        XCTAssertTrue(manager.addMock(MockRule(method: "GET", path: "/data.json", status: 202, body: #"{"mock":true}"#), to: id))
        XCTAssertEqual(store.saved.first?.options.mocks.count, 1)
        let after = try await get(url)
        XCTAssertEqual(after.0, #"{"mock":true}"#)
        XCTAssertEqual(after.1, 202)

        // Saving the same method and path again replaces it; removing all brings the file back.
        manager.addMock(MockRule(method: "GET", path: "/data.json", body: "2"), to: id)
        XCTAssertEqual(manager.entries.first?.options.mocks.map(\.body), ["2"])
        manager.setMocks(id, [])
        let restored = try await get(url)
        XCTAssertEqual(restored.0, #"{"real":true}"#)
        XCTAssertFalse(manager.addMock(MockRule(path: "/x"), to: UUID()))
    }

    func testMockForALoggedRequest() {
        var proxied = RequestLogEntry(method: "GET", path: "/api/me", status: 200, bytes: 9)
        proxied.responseHeaders = [HTTPHeaderField(name: "Content-Type", value: "application/json")]
        proxied.responseBody = Data(#"{"id":7}"#.utf8)
        XCTAssertEqual(RequestDetailView.mock(for: proxied, content: nil)?.body, #"{"id":7}"#)

        // A static file's body is not in the log entry: it comes from what the detail panel loaded.
        var file = RequestLogEntry(method: "GET", path: "/data.json", status: 200, bytes: 4)
        file.responseHeaders = [HTTPHeaderField(name: "Content-Type", value: "application/json")]
        XCTAssertNil(RequestDetailView.mock(for: file, content: nil))
        XCTAssertEqual(RequestDetailView.mock(for: file, content: LoadedContent(data: Data("[1]".utf8), totalSize: 3, truncated: false))?.body, "[1]")
        XCTAssertNil(RequestDetailView.mock(for: file, content: LoadedContent(data: Data("[1".utf8), totalSize: 900_000, truncated: true)))
    }

    func testEditorHelpers() {
        XCTAssertEqual(MockEditorView.methodLabel(""), "Any")
        XCTAssertEqual(MockEditorView.methodLabel("POST"), "POST")
        var status = 200
        let text = MockEditorView.statusText(Binding(get: { status }, set: { status = $0 }))
        XCTAssertEqual(text.wrappedValue, "200")
        text.wrappedValue = " 404 "
        XCTAssertEqual(status, 404)
        text.wrappedValue = "abc"
        XCTAssertEqual(status, 0)
        XCTAssertEqual(text.wrappedValue, "")
        XCTAssertNotNil(MockRule(path: "/a", status: status).problem)
    }
}
