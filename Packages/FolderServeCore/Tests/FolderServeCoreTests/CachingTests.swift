import XCTest
@testable import FolderServeCore

final class CachingTests: XCTestCase {
    private var root: URL!
    private var server: StaticServer?
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "body{}".write(to: root.appendingPathComponent("a.css"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? FileManager.default.removeItem(at: root) }

    private func start(caching: Bool) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: true, caching: caching))
        return try await server!.start()
    }

    func testOffByDefaultEverythingIsNoStore() async throws {
        let port = try await start(caching: false)
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/a.css"))
        XCTAssertEqual(r.headers["cache-control"], "no-store")
        XCTAssertNil(r.headers["etag"])
    }

    func testOnSendsETagAndAnswers304() async throws {
        let port = try await start(caching: true)
        let first = try XCTUnwrap(RawHTTP.get(port: port, "/a.css"))
        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(first.headers["cache-control"], "no-cache")
        let tag = try XCTUnwrap(first.headers["etag"])
        let second = try XCTUnwrap(RawHTTP.get(port: port, "/a.css", headers: "If-None-Match: \(tag)\r\n"))
        XCTAssertEqual(second.status, 304)
        XCTAssertTrue(second.body.isEmpty)
        XCTAssertEqual(second.headers["etag"], tag)
    }

    func testEditedFileGetsANewTagAndFullAnswer() async throws {
        let port = try await start(caching: true)
        let tag = try XCTUnwrap(RawHTTP.get(port: port, "/a.css")?.headers["etag"])
        try "body{color:red}".write(to: root.appendingPathComponent("a.css"), atomically: true, encoding: .utf8)
        let again = try XCTUnwrap(RawHTTP.get(port: port, "/a.css", headers: "If-None-Match: \(tag)\r\n"))
        XCTAssertEqual(again.status, 200)
        XCTAssertEqual(again.text, "body{color:red}")
    }

    func testInjectedHTMLIsNeverCached() async throws {
        let port = try await start(caching: true)
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/index.html"))
        XCTAssertEqual(r.headers["cache-control"], "no-store")
        XCTAssertNil(r.headers["etag"])
    }

    func testEtagMatching() {
        XCTAssertTrue(StaticServer.etagMatches("W/\"a-b\"", "W/\"a-b\""))
        XCTAssertTrue(StaticServer.etagMatches("\"x\", W/\"a-b\"", "W/\"a-b\""))
        XCTAssertTrue(StaticServer.etagMatches("*", "W/\"a-b\""))
        XCTAssertFalse(StaticServer.etagMatches("W/\"other\"", "W/\"a-b\""))
        XCTAssertFalse(StaticServer.etagMatches(nil, "W/\"a-b\""))
    }

    func testOldSettingsDecodeWithCachingOff() throws {
        let o = try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"spaMode":true}"#.utf8))
        XCTAssertFalse(o.caching)
    }
}
