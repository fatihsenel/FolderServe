import XCTest
@testable import FolderServeCore

final class MockRuleUnitTests: XCTestCase {
    func testPathPatterns() {
        XCTAssertTrue(PathPattern.matches("/api/me", path: "/api/me"))
        XCTAssertTrue(PathPattern.matches("/api/me", path: "/api/me/"), "a trailing slash is the same path")
        XCTAssertFalse(PathPattern.matches("/api/me", path: "/api/me/x"))
        XCTAssertTrue(PathPattern.matches("/api/*", path: "/api/users/7"))
        XCTAssertFalse(PathPattern.matches("/api/*", path: "/apix"))
        XCTAssertTrue(PathPattern.matches("*", path: "/anything"))
        XCTAssertTrue(PathPattern.matches("/*", path: "/"))
    }

    func testPathProblems() {
        XCTAssertNil(PathPattern.problem("/api/*"))
        XCTAssertNil(PathPattern.problem("*"))
        XCTAssertNotNil(PathPattern.problem("api/me"))
        XCTAssertNotNil(PathPattern.problem("/a*/b"))
    }

    func testMockMatchingByMethodAndEnabled() {
        var r = MockRule(method: "post", path: "/api/login")
        XCTAssertTrue(r.matches(method: "POST", path: "/api/login"))
        XCTAssertFalse(r.matches(method: "GET", path: "/api/login"))
        r.method = ""
        XCTAssertTrue(r.matches(method: "GET", path: "/api/login"), "empty method means any")
        r.enabled = false
        XCTAssertFalse(r.matches(method: "GET", path: "/api/login"))
    }

    func testMockValidation() {
        XCTAssertNil(MockRule().problem)
        XCTAssertNotNil(MockRule(status: 99).problem)
        XCTAssertNotNil(MockRule(status: 600).problem)
        XCTAssertNotNil(MockRule(delayMs: 60_000).problem)
        XCTAssertNotNil(MockRule(path: "nope").problem)
        XCTAssertNotNil(MockRule(contentType: "a\r\nX-Evil: 1").problem)
    }

    func testHeaderRuleValidationAndMerging() {
        XCTAssertNil(HeaderRule(path: "/*", name: "X-Frame-Options", value: "DENY").problem)
        XCTAssertNotNil(HeaderRule(name: "").problem)
        XCTAssertNotNil(HeaderRule(name: "Bad Name", value: "x").problem)
        XCTAssertNotNil(HeaderRule(name: "Content-Length", value: "0").problem)
        XCTAssertNotNil(HeaderRule(name: "X-A", value: "1\r\nX-B: 2").problem)
        let rules = [HeaderRule(path: "*", name: "X-All", value: "1"),
                     HeaderRule(path: "/api/*", name: "X-All", value: "2"),
                     HeaderRule(path: "/api/*", name: "X-Api", value: "y"),
                     HeaderRule(enabled: false, path: "*", name: "X-Off", value: "z"),
                     HeaderRule(path: "*", name: "Bad Name", value: "x")]
        XCTAssertEqual(HeaderRule.headers(for: "/api/me", in: rules), ["X-All": "2", "X-Api": "y"], "later rules win; disabled and invalid are skipped")
        XCTAssertEqual(HeaderRule.headers(for: "/index.html", in: rules), ["X-All": "1"])
    }

    func testOldSavedOptionsStillDecode() throws {
        let old = #"{"spaMode":true,"liveReload":true,"serveDotfiles":false,"cors":false,"proxyRules":[]}"#
        let o = try JSONDecoder().decode(ServeOptions.self, from: Data(old.utf8))
        XCTAssertTrue(o.mockRules.isEmpty); XCTAssertTrue(o.headerRules.isEmpty)
    }

    func testRulesSurviveARoundTrip() throws {
        let o = ServeOptions(mockRules: [MockRule(method: "GET", path: "/a", status: 418, body: "tea", delayMs: 5)],
                             headerRules: [HeaderRule(path: "/b", name: "X-B", value: "1")])
        let back = try JSONDecoder().decode(ServeOptions.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back, o)
    }
}

final class MockServerTests: XCTestCase {
    private var root: URL!
    private var server: StaticServer?
    private var upstream: FakeUpstream!
    private let log = LogBox()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "FILE".write(to: root.appendingPathComponent("real.txt"), atomically: true, encoding: .utf8)
        try "<html></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        upstream = FakeUpstream(); upstream.start()
    }
    override func tearDownWithError() throws { server?.stop(); upstream.stop(); try? FileManager.default.removeItem(at: root) }

    private func start(_ options: ServeOptions) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: options)
        server?.onRequest = { [log] in log.add($0) }
        return try await server!.start()
    }

    func testMockAnswersWithStatusHeadersAndBody() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(path: "/api/me", status: 201, contentType: "application/json", body: #"{"name":"Ada"}"#)]))
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/api/me"))
        XCTAssertEqual(r.status, 201)
        XCTAssertEqual(r.text, #"{"name":"Ada"}"#)
        XCTAssertEqual(r.headers["content-type"], "application/json")
        XCTAssertEqual(r.headers["content-length"], "14")
    }

    func testMockIsLoggedAsMocked() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(path: "/api/me")]))
        _ = RawHTTP.get(port: port, "/api/me")
        let entry = try XCTUnwrap(log.entries.first { $0.path == "/api/me" })
        XCTAssertEqual(entry.note, "Mocked"); XCTAssertEqual(entry.status, 200)
    }

    func testMockOnlyMatchesItsMethodAndFirstRuleWins() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(method: "POST", path: "/x", status: 202, body: "first"),
                                                            MockRule(path: "/x", status: 203, body: "second")]))
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/x", method: "POST")).text, "first")
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/x")).text, "second")
    }

    func testMockBeatsFilesAndProxyRules() async throws {
        let port = try await start(ServeOptions(proxyRules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")],
                                                mockRules: [MockRule(path: "/real.txt", body: "MOCK"), MockRule(path: "/api/users", body: "FAKE")]))
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/real.txt")).text, "MOCK", "instead of the file")
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/api/users")).text, "FAKE", "instead of the proxy target")
        XCTAssertNil(upstream.last, "the proxy target was never contacted")
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/api/other")).status, 200, "other proxy paths still go through")
        XCTAssertNotNil(upstream.last)
    }

    func testDelayHoldsTheAnswerBack() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(path: "/slow", body: "late", delayMs: 300)]))
        let began = Date()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/slow"))
        XCTAssertEqual(r.text, "late")
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(began), 0.28)
    }

    func testNoContentAndHeadHaveNoBody() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(path: "/none", status: 204, body: "ignored"), MockRule(path: "/h", body: "body")]))
        let none = try XCTUnwrap(RawHTTP.get(port: port, "/none"))
        XCTAssertEqual(none.status, 204); XCTAssertTrue(none.body.isEmpty)
        let head = try XCTUnwrap(RawHTTP.get(port: port, "/h", method: "HEAD"))
        XCTAssertEqual(head.status, 200); XCTAssertTrue(head.body.isEmpty)
        XCTAssertEqual(head.headers["content-length"], "4")
    }

    func testInvalidOrDisabledMocksAreIgnored() async throws {
        let port = try await start(ServeOptions(mockRules: [MockRule(path: "/real.txt", status: 999, body: "BAD"),
                                                            MockRule(enabled: false, path: "/real.txt", body: "OFF")]))
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/real.txt")).text, "FILE")
    }

    func testHeaderRulesReachFilesMocksAndProxiedAnswers() async throws {
        let port = try await start(ServeOptions(
            proxyRules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")],
            mockRules: [MockRule(path: "/mocked", body: "m")],
            headerRules: [HeaderRule(path: "*", name: "X-Env", value: "test"), HeaderRule(path: "/api/*", name: "X-Api", value: "1")]))
        let file = try XCTUnwrap(RawHTTP.get(port: port, "/real.txt"))
        XCTAssertEqual(file.headers["x-env"], "test"); XCTAssertNil(file.headers["x-api"])
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/mocked")).headers["x-env"], "test")
        let proxied = try XCTUnwrap(RawHTTP.get(port: port, "/api/users"))
        XCTAssertEqual(proxied.headers["x-env"], "test"); XCTAssertEqual(proxied.headers["x-api"], "1")
    }

    func testRulesCanBeChangedWhileRunning() async throws {
        let port = try await start(ServeOptions())
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/real.txt")).text, "FILE")
        server?.updateOptions(ServeOptions(mockRules: [MockRule(path: "/real.txt", body: "NOW MOCKED")]))
        XCTAssertEqual(try XCTUnwrap(RawHTTP.get(port: port, "/real.txt")).text, "NOW MOCKED")
    }
}
