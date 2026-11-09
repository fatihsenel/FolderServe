import XCTest
@testable import FolderServeCore

final class MockRuleTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("mock-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "real file".write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private func start(_ options: ServeOptions, onRequest: (@Sendable (RequestLogEntry) -> Void)? = nil) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: options)
        server.onRequest = onRequest
        return try await server.start()
    }
    private func req(_ port: UInt16, _ raw: String) throws -> RawResponse { try XCTUnwrap(RawHTTP.request(port: port, raw)) }

    // MARK: Rule

    func testMatchingIsExactOnPathAndMethod() {
        let get = MockRule(method: "get", path: "api/users?x=1")
        XCTAssertEqual(get.normalizedPath, "/api/users")
        XCTAssertTrue(get.matches(method: "GET", path: "/api/users"))
        XCTAssertTrue(get.matches(method: "HEAD", path: "/api/users"))
        XCTAssertFalse(get.matches(method: "POST", path: "/api/users"))
        XCTAssertFalse(get.matches(method: "GET", path: "/api/users/7"))
        XCTAssertTrue(MockRule(path: "/x").matches(method: "DELETE", path: "/x"))
        XCTAssertFalse(MockRule(path: "/x", enabled: false).matches(method: "GET", path: "/x"))
    }

    func testProblems() {
        XCTAssertNil(MockRule(path: "/api").problem)
        XCTAssertNotNil(MockRule(path: "  ").problem)
        XCTAssertNotNil(MockRule(path: "/a b").problem)
        XCTAssertNotNil(MockRule(path: "/__reload").problem)
        XCTAssertNotNil(MockRule(path: "/a", status: 99).problem)
        XCTAssertNotNil(MockRule(path: "/a", status: 600).problem)
        XCTAssertNotNil(MockRule(path: "/a", contentType: "text/plain\r\nX-Evil: 1").problem)
        XCTAssertNotNil(MockRule(path: "/a", body: String(repeating: "x", count: MockRule.maxBodyBytes + 1)).problem)
        XCTAssertFalse(MockRule(path: "/a", contentType: "a\r\nb").matches(method: "GET", path: "/a"))
    }

    func testOlderSavedOptionsHaveNoMocksAndRulesRoundTrip() throws {
        XCTAssertEqual(try JSONDecoder().decode(ServeOptions.self, from: Data("{}".utf8)).mocks, [])
        let options = ServeOptions(mocks: [MockRule(method: "POST", path: "/login", status: 401, body: "{}")])
        XCTAssertEqual(try JSONDecoder().decode(ServeOptions.self, from: JSONEncoder().encode(options)), options)
    }

    func testCapturingALoggedRequest() {
        var e = RequestLogEntry(method: "POST", path: "/api/login", status: 201, bytes: 2)
        e.responseHeaders = [HTTPHeaderField(name: "Content-Type", value: "application/json; charset=utf-8")]
        e.responseBody = Data(#"{"ok":true}"#.utf8)
        let rule = MockRule(capturing: e)
        XCTAssertEqual(rule?.method, "POST")
        XCTAssertEqual(rule?.path, "/api/login")
        XCTAssertEqual(rule?.status, 201)
        XCTAssertEqual(rule?.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(rule?.body, #"{"ok":true}"#)

        e.responseBodyTruncated = true
        XCTAssertNil(MockRule(capturing: e))
        e.responseBodyTruncated = false
        e.responseBody = Data([0xFF, 0xFE])
        XCTAssertNil(MockRule(capturing: e))
        e.responseBody = nil
        XCTAssertNil(MockRule(capturing: e))
        XCTAssertEqual(MockRule(capturing: e, body: Data("file".utf8))?.body, "file")
    }

    func testAddingReplacesTheSameMethodAndPath() {
        let a = MockRule(method: "GET", path: "/a", body: "1"), b = MockRule(method: "get", path: "/a", body: "2")
        let other = MockRule(method: "POST", path: "/a")
        let out = MockRule.adding(b, to: [a, other])
        XCTAssertEqual(out.map(\.body), ["", "2"])
    }

    // MARK: Server

    func testMockAnswersInsteadOfTheFileAndIsLogged() async throws {
        let logged = Locked<[RequestLogEntry]>([])
        let mock = MockRule(method: "GET", path: "/data.json", status: 418, contentType: "application/json", body: #"{"mock":1}"#)
        let port = try await start(ServeOptions(mocks: [mock])) { e in logged.mutate { $0.append(e) } }
        let r = try req(port, "GET /data.json?x=1 HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(r.status, 418)
        XCTAssertEqual(r.text, #"{"mock":1}"#)
        XCTAssertEqual(r.headers["content-type"], "application/json")
        XCTAssertEqual(r.headers["x-folderserve-mock"], "1")
        let entry = try XCTUnwrap(waitFor { logged.value.first })
        XCTAssertEqual(entry.note, "mock")
        XCTAssertEqual(entry.responseBody, Data(#"{"mock":1}"#.utf8))
    }

    func testMockAnswersAPostWithABodyAndHeadGetsNoBody() async throws {
        let port = try await start(ServeOptions(mocks: [MockRule(path: "/api/save", status: 201, body: "saved")]))
        let body = String(repeating: "a", count: 40_000)
        let r = try req(port, "POST /api/save HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.count)\r\n\r\n\(body)")
        XCTAssertEqual(r.status, 201)
        XCTAssertEqual(r.text, "saved")
        let head = try req(port, "HEAD /api/save HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(head.status, 201)
        XCTAssertEqual(head.headers["content-length"], "5")
        XCTAssertTrue(head.body.isEmpty)
    }

    func testMockWinsOverAProxyRuleAndOtherPathsAreUntouched() async throws {
        let options = ServeOptions(proxyRules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:1")],
                                   mocks: [MockRule(path: "/api/me", body: "me"), MockRule(path: "/off", body: "x", enabled: false)])
        let port = try await start(options)
        XCTAssertEqual(try req(port, "GET /api/me HTTP/1.1\r\nHost: localhost\r\n\r\n").text, "me")
        XCTAssertEqual(try req(port, "GET /data.json HTTP/1.1\r\nHost: localhost\r\n\r\n").text, "real file")
        XCTAssertEqual(try req(port, "GET /off HTTP/1.1\r\nHost: localhost\r\nAccept: text/plain\r\n\r\n").status, 404)
    }

    func testMockCarriesCORSHeadersAndRespectsTheHostCheck() async throws {
        let port = try await start(ServeOptions(cors: true, mocks: [MockRule(path: "/api/me", body: "me")]))
        let r = try req(port, "GET /api/me HTTP/1.1\r\nHost: localhost\r\nOrigin: http://localhost:4200\r\n\r\n")
        XCTAssertNotNil(r.headers["access-control-allow-origin"])
        XCTAssertEqual(try req(port, "GET /api/me HTTP/1.1\r\nHost: evil.example\r\n\r\n").status, 403)
    }

    private func waitFor<T>(_ value: () -> T?) -> T? {
        for _ in 0..<200 { if let v = value() { return v }; usleep(10_000) }
        return nil
    }
}

private final class Locked<T>: @unchecked Sendable {
    private var stored: T
    private let lock = NSLock()
    init(_ v: T) { stored = v }
    var value: T { lock.lock(); defer { lock.unlock() }; return stored }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&stored); lock.unlock() }
}
