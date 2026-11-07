import XCTest
@testable import FolderServeCore

final class CORSTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("cors-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "<html><body>x</body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private func start(cors: Bool) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: ServeOptions(cors: cors))
        return try await server.start()
    }
    private func req(_ port: UInt16, _ raw: String) throws -> RawResponse {
        try XCTUnwrap(RawHTTP.request(port: port, raw))
    }

    func testOffByDefaultSendsNoCORSHeaders() async throws {
        let port = try await start(cors: false)
        let r = try req(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\nOrigin: http://localhost:4200\r\n\r\n")
        XCTAssertEqual(r.status, 200)
        XCTAssertNil(r.headers["access-control-allow-origin"])
    }

    func testOffRejectsPreflightWith405() async throws {
        let port = try await start(cors: false)
        let r = try req(port, "OPTIONS /a.txt HTTP/1.1\r\nHost: localhost\r\nOrigin: http://x\r\nAccess-Control-Request-Method: GET\r\n\r\n")
        XCTAssertEqual(r.status, 405)
        XCTAssertNil(r.headers["access-control-allow-origin"])
    }

    func testOnAddsAllowOriginToFilesAndErrors() async throws {
        let port = try await start(cors: true)
        let ok = try req(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\nOrigin: http://localhost:4200\r\n\r\n")
        XCTAssertEqual(ok.status, 200)
        XCTAssertEqual(ok.headers["access-control-allow-origin"], "*")
        XCTAssertEqual(ok.text, "hello")
        let missing = try req(port, "GET /nope.png HTTP/1.1\r\nHost: localhost\r\nOrigin: http://localhost:4200\r\n\r\n")
        XCTAssertEqual(missing.status, 404)
        XCTAssertEqual(missing.headers["access-control-allow-origin"], "*", "JS must be able to read the 404")
    }

    func testOnAddsHeadersToHEADAndRanges() async throws {
        let port = try await start(cors: true)
        XCTAssertEqual(try req(port, "HEAD /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").headers["access-control-allow-origin"], "*")
        let partial = try req(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\nRange: bytes=0-1\r\n\r\n")
        XCTAssertEqual(partial.status, 206)
        XCTAssertEqual(partial.headers["access-control-allow-origin"], "*")
        XCTAssertNotNil(partial.headers["access-control-expose-headers"]?.contains("Content-Range"))
    }

    func testPreflightIsAnsweredWith204() async throws {
        let port = try await start(cors: true)
        let r = try req(port, "OPTIONS /api/data.json HTTP/1.1\r\nHost: localhost\r\nOrigin: http://localhost:4200\r\nAccess-Control-Request-Method: GET\r\nAccess-Control-Request-Headers: x-custom, content-type\r\n\r\n")
        XCTAssertEqual(r.status, 204)
        XCTAssertEqual(r.headers["access-control-allow-origin"], "*")
        XCTAssertEqual(r.headers["access-control-allow-methods"], "GET, HEAD, OPTIONS")
        XCTAssertEqual(r.headers["access-control-allow-headers"], "x-custom, content-type")
        XCTAssertEqual(r.headers["access-control-max-age"], "600")
        XCTAssertEqual(r.headers["content-length"], "0")
        XCTAssertTrue(r.body.isEmpty)
    }

    func testPrivateNetworkPreflight() async throws {
        let port = try await start(cors: true)
        let r = try req(port, "OPTIONS /a.txt HTTP/1.1\r\nHost: localhost\r\nOrigin: https://example.com\r\nAccess-Control-Request-Method: GET\r\nAccess-Control-Request-Private-Network: true\r\n\r\n")
        XCTAssertEqual(r.headers["access-control-allow-private-network"], "true")
    }

    func testStillRejectsForeignHostEvenWithCORS() async throws {
        let port = try await start(cors: true)
        let r = try req(port, "GET /a.txt HTTP/1.1\r\nHost: evil.example.com\r\nOrigin: http://evil.example.com\r\n\r\n")
        XCTAssertEqual(r.status, 403)
        XCTAssertFalse(r.text.contains("hello"))
    }

    func testOtherMethodsStillRejectedWithCORS() async throws {
        let port = try await start(cors: true)
        let r = try req(port, "POST /a.txt HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
        XCTAssertEqual(r.status, 405)
        XCTAssertEqual(r.headers["allow"], "GET, HEAD, OPTIONS")
    }

    func testCanToggleLiveWithUpdateOptions() async throws {
        let port = try await start(cors: false)
        XCTAssertNil(try req(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").headers["access-control-allow-origin"])
        server.updateOptions(ServeOptions(cors: true))
        XCTAssertEqual(try req(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").headers["access-control-allow-origin"], "*")
    }

    func testDecodingOldOptionsWithoutCORSKeyDefaultsOff() throws {
        let old = Data(#"{"spaMode":false,"liveReload":true,"serveDotfiles":true}"#.utf8)
        let o = try JSONDecoder().decode(ServeOptions.self, from: old)
        XCTAssertFalse(o.cors)
        XCTAssertFalse(o.spaMode)
        XCTAssertTrue(o.serveDotfiles)
    }
}
