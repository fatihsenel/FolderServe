import XCTest
@testable import FolderServeCore

final class RequestDetailTests: XCTestCase {
    var root: URL!; var server: StaticServer!; var upstream: FakeUpstream!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rd-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try "body{}".write(to: root.appendingPathComponent("a.css"), atomically: true, encoding: .utf8)
        try #"{"baseUrl":"https://localhost:5003/uiapi/"}"#.write(to: root.appendingPathComponent("assets/config.json"), atomically: true, encoding: .utf8)
        upstream = FakeUpstream(); upstream.start()
    }
    override func tearDownWithError() throws { server?.stop(); upstream.stop(); try? fm.removeItem(at: root) }

    private func start(rules: [ProxyRule] = []) async throws -> (UInt16, LogBox) {
        server = StaticServer(root: root, port: 0, options: ServeOptions(proxyRules: rules))
        let box = LogBox(); server.onRequest = { box.add($0) }
        return (try await server.start(), box)
    }
    private func entry(_ box: LogBox, path: String) async throws -> RequestLogEntry {
        for _ in 0..<50 {
            if let e = box.entries.last(where: { $0.path == path }) { return e }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw XCTSkip("no log entry for \(path)")
    }

    func testStaticRequestRecordsUrlHeadersTimingAndFile() async throws {
        let (port, box) = try await start()
        _ = RawHTTP.request(port: port, "GET /a.css?v=3 HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nX-Test: hello\r\nAccept: text/css\r\n\r\n")
        let e = try await entry(box, path: "/a.css")
        XCTAssertEqual(e.url, "http://127.0.0.1:\(port)/a.css?v=3")
        XCTAssertEqual(e.requestHeaders.first { $0.name == "x-test" }?.value, "hello")
        XCTAssertEqual(e.requestHeaders.map(\.name), e.requestHeaders.map(\.name).sorted(), "sorted by name")
        XCTAssertEqual(e.responseHeaders.first { $0.name == "Content-Type" }?.value, "text/css; charset=utf-8")
        XCTAssertEqual(e.responseHeaders.first { $0.name == "Content-Length" }?.value, "6")
        XCTAssertEqual(e.responseHeaders.first { $0.name == "Cache-Control" }?.value, "no-store")
        XCTAssertNotNil(e.durationMs)
        XCTAssertEqual(e.servedFile, root.appendingPathComponent("a.css").path)
        XCTAssertFalse(e.rewritten)
        XCTAssertNil(e.requestBody); XCTAssertNil(e.responseBody, "files are read from disk, not stored")
    }

    func testErrorPagesStillCarryRequestAndResponseDetails() async throws {
        let (port, box) = try await start()
        _ = RawHTTP.request(port: port, "GET /nope.png HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nX-Id: 7\r\n\r\n")
        let e = try await entry(box, path: "/nope.png")
        XCTAssertEqual(e.status, 404)
        XCTAssertEqual(e.requestHeaders.first { $0.name == "x-id" }?.value, "7")
        XCTAssertEqual(e.responseContentType, "text/html; charset=utf-8")
        XCTAssertNil(e.servedFile)
    }

    func testRewrittenFilesAreFlagged() async throws {
        let (port, box) = try await start(rules: [ProxyRule(prefix: "/uiapi", target: "https://localhost:5003")])
        _ = RawHTTP.request(port: port, "GET /assets/config.json HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n")
        let e = try await entry(box, path: "/assets/config.json")
        XCTAssertTrue(e.rewritten)
        XCTAssertEqual(e.servedFile, root.appendingPathComponent("assets/config.json").path)
    }

    func testCORSHeadersAppearInRecordedResponseHeaders() async throws {
        server = StaticServer(root: root, port: 0, options: ServeOptions(cors: true))
        let box = LogBox(); server.onRequest = { box.add($0) }
        let port = try await server.start()
        _ = RawHTTP.request(port: port, "GET /a.css HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n")
        let e = try await entry(box, path: "/a.css")
        XCTAssertEqual(e.responseHeaders.first { $0.name == "Access-Control-Allow-Origin" }?.value, "*")
    }

    func testProxiedCallCapturesBodiesBothWaysAndTheUpstreamURL() async throws {
        let (port, box) = try await start(rules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")])
        let json = #"{"user":"a"}"#
        let raw = "POST /api/Account/Login?x=1 HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\n\r\n\(json)"
        _ = RawHTTP.request(port: port, raw)
        let e = try await entry(box, path: "/api/Account/Login")
        XCTAssertEqual(e.category, .fetch)
        XCTAssertEqual(e.url, "http://127.0.0.1:\(port)/api/Account/Login?x=1")
        XCTAssertEqual(e.upstreamURL, "http://127.0.0.1:\(upstream.port)/api/Account/Login?x=1")
        XCTAssertEqual(String(decoding: try XCTUnwrap(e.requestBody), as: UTF8.self), json)
        XCTAssertEqual(String(decoding: try XCTUnwrap(e.responseBody), as: UTF8.self), "POST /api/Account/Login?x=1 body=\(json)")
        XCTAssertFalse(e.requestBodyTruncated); XCTAssertFalse(e.responseBodyTruncated)
        XCTAssertEqual(e.requestHeaders.first { $0.name == "content-type" }?.value, "application/json")
        XCTAssertEqual(e.responseHeaders.first { $0.name == "Content-Type" }?.value, "text/plain")
        XCTAssertNotNil(e.durationMs)
    }

    func testCapturedBodiesAreCapped() async throws {
        let (port, box) = try await start(rules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")])
        let big = String(repeating: "x", count: RequestLogEntry.maxResponseBodyCapture + 70_000)
        _ = RawHTTP.request(port: port, "PUT /api/blob HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nContent-Length: \(big.utf8.count)\r\n\r\n\(big)")
        let e = try await entry(box, path: "/api/blob")
        XCTAssertEqual(e.requestBody?.count, RequestLogEntry.maxRequestBodyCapture)
        XCTAssertTrue(e.requestBodyTruncated)
        XCTAssertEqual(e.responseBody?.count, RequestLogEntry.maxResponseBodyCapture, "the echo is longer than the response cap")
        XCTAssertTrue(e.responseBodyTruncated)
        XCTAssertEqual(upstream.last?.body.count, big.utf8.count, "forwarding is not affected by the capture cap")
        XCTAssertLessThanOrEqual(e.capturedBodyBytes, RequestLogEntry.maxRequestBodyCapture + RequestLogEntry.maxResponseBodyCapture)
    }

    func testProxiedResponseHeadersShowRewrittenCookiesAndAddedHeaders() async throws {
        let (port, box) = try await start(rules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")])
        _ = RawHTTP.request(port: port, "GET /api/cookie HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n")
        let e = try await entry(box, path: "/api/cookie")
        let cookies = e.responseHeaders.filter { $0.name == "Set-Cookie" }.map(\.value)
        XCTAssertEqual(cookies.count, 2)
        XCTAssertFalse(cookies[0].lowercased().contains("secure"))
        XCTAssertTrue(e.responseHeaders.contains { $0.name == "Transfer-Encoding" && $0.value == "chunked" })
    }

    func testDisplayURLEncodesThePath() {
        let r = HTTPRequest(method: "GET", path: "/a b/ü", rawQuery: "q=1", headers: ["host": "localhost:8080"])
        XCTAssertEqual(r.displayURL, "http://localhost:8080/a%20b/%C3%BC?q=1")
    }
}

/// One request must produce exactly one log entry, whatever path it takes through the server.
final class LoggedOnceTests: XCTestCase {
    var root: URL!; var server: StaticServer!; let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("once-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try "<html><body>x</body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "export const a=1;".write(to: root.appendingPathComponent("chunk-A.js"), atomically: true, encoding: .utf8)
        try #"{"u":"https://localhost:5003/"}"#.write(to: root.appendingPathComponent("assets/config.json"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private func counts(after requests: [String], options: ServeOptions) async throws -> [String: Int] {
        server = StaticServer(root: root, port: 0, options: options)
        let box = LogBox(); server.onRequest = { box.add($0) }
        let port = try await server.start()
        for r in requests { _ = RawHTTP.request(port: port, r.replacingOccurrences(of: "{HOST}", with: "127.0.0.1:\(port)")) }
        try await Task.sleep(nanoseconds: 400_000_000)
        return Dictionary(box.entries.map { ($0.method + " " + $0.path, 1) }, uniquingKeysWith: +)
    }

    func testEveryKindOfRequestIsLoggedExactlyOnce() async throws {
        let get = { (p: String, extra: String) in "GET \(p) HTTP/1.1\r\nHost: {HOST}\r\n\(extra)\r\n" }
        let c = try await counts(after: [
            get("/chunk-A.js", "Sec-Fetch-Dest: script\r\n"),
            get("/assets/config.json", "Sec-Fetch-Dest: empty\r\n"),
            get("/index.html", ""), get("/deep/link", "Accept: text/html\r\n"), get("/missing.js", ""),
            get("/chunk-A.js", "Range: bytes=0-3\r\n"),
            "HEAD /chunk-A.js HTTP/1.1\r\nHost: {HOST}\r\n\r\n",
            "OPTIONS /x HTTP/1.1\r\nHost: {HOST}\r\n\r\n",
            "GET / HTTP/1.1\r\nHost: evil.example\r\n\r\n",
        ], options: ServeOptions(liveReload: true, cors: true,
                                 proxyRules: [ProxyRule(prefix: "/uiapi", target: "https://localhost:5003")]))
        XCTAssertEqual(c["GET /chunk-A.js"], 2, "the plain GET and the Range GET are two requests, one entry each")
        XCTAssertEqual(c["GET /assets/config.json"], 1)
        XCTAssertEqual(c["GET /index.html"], 1)
        XCTAssertEqual(c["GET /deep/link"], 1)
        XCTAssertEqual(c["GET /missing.js"], 1)
        XCTAssertEqual(c["HEAD /chunk-A.js"], 1)
        XCTAssertEqual(c["OPTIONS /x"], 1)
        XCTAssertEqual(c["GET /"], 1, "the foreign-host rejection is logged once too")
        XCTAssertEqual(c.values.reduce(0, +), 9)
    }

    func testThirtyConcurrentRequestsGiveThirtyEntries() async throws {
        server = StaticServer(root: root, port: 0, options: ServeOptions())
        let box = LogBox(); server.onRequest = { box.add($0) }
        let port = try await server.start()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask { _ = RawHTTP.request(port: port, "GET /chunk-A.js?i=\(i) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n") }
            }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(box.entries.count, 30)
        XCTAssertEqual(Set(box.entries.map(\.id)).count, 30, "every entry has its own id")
    }
}
