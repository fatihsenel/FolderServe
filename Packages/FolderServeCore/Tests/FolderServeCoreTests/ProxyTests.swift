import XCTest
import Darwin
@testable import FolderServeCore

final class ProxyRuleUnitTests: XCTestCase {
    func testPrefixMatchingIsSegmentBased() {
        let r = ProxyRule(prefix: "/api", target: "http://localhost:3000")
        XCTAssertTrue(r.matches(path: "/api")); XCTAssertTrue(r.matches(path: "/api/users"))
        XCTAssertFalse(r.matches(path: "/apix")); XCTAssertFalse(r.matches(path: "/other/api"))
    }
    func testPrefixIsNormalised() {
        XCTAssertEqual(ProxyRule(prefix: "api/", target: "http://x").normalizedPrefix, "/api")
        XCTAssertEqual(ProxyRule(prefix: " /uiapi// ", target: "http://x").normalizedPrefix, "/uiapi")
    }
    func testValidation() {
        XCTAssertNil(ProxyRule(prefix: "/uiapi", target: "https://localhost:5003").problem)
        XCTAssertNotNil(ProxyRule(prefix: "/", target: "http://x").problem)
        XCTAssertNotNil(ProxyRule(prefix: "/api", target: "localhost:3000").problem)
        XCTAssertNotNil(ProxyRule(prefix: "/api", target: "ftp://x").problem)
        XCTAssertNotNil(ProxyRule(prefix: "/api", target: "not a url").problem)
        XCTAssertNotNil(ProxyRule(prefix: "/__reload", target: "http://x").problem)
    }
    func testUpstreamURLKeepsPrefixByDefault() {
        let r = ProxyRule(prefix: "/uiapi", target: "https://localhost:5003")
        XCTAssertEqual(r.upstreamURL(path: "/uiapi/Account/Login", rawQuery: nil)?.absoluteString, "https://localhost:5003/uiapi/Account/Login")
    }
    func testUpstreamURLStripsPrefixAndKeepsQuery() {
        let r = ProxyRule(prefix: "/api", target: "http://localhost:3000/v1/", stripPrefix: true)
        XCTAssertEqual(r.upstreamURL(path: "/api/users", rawQuery: "a=1&b=x%20y")?.absoluteString, "http://localhost:3000/v1/users?a=1&b=x%20y")
        XCTAssertEqual(r.upstreamURL(path: "/api", rawQuery: nil)?.absoluteString, "http://localhost:3000/v1/")
    }
    func testUpstreamURLEncodesSpecialCharacters() {
        let r = ProxyRule(prefix: "/api", target: "http://h")
        XCTAssertEqual(r.upstreamURL(path: "/api/a b/ü?", rawQuery: nil)?.absoluteString, "http://h/api/a%20b/%C3%BC%3F")
    }
    func testLocationRewrite() {
        let r = ProxyRule(prefix: "/api", target: "https://localhost:5003")
        XCTAssertEqual(r.rewriteLocation("https://localhost:5003/api/login"), "/api/login")
        XCTAssertEqual(r.rewriteLocation("https://other.example/x"), "https://other.example/x")
        XCTAssertEqual(ProxyRule(prefix: "/api", target: "http://h:1", stripPrefix: true).rewriteLocation("http://h:1/x"), "/api/x")
    }
    func testSetCookieRewrite() {
        XCTAssertEqual(ProxyRule.rewriteSetCookie("a=1; Path=/; Secure; SameSite=None; Domain=example.com; HttpOnly"), "a=1; Path=/; SameSite=Lax; HttpOnly")
        XCTAssertEqual(ProxyRule.rewriteSetCookie("s=x; SameSite=Strict"), "s=x; SameSite=Strict")
    }
    func testSetCookieSplitKeepsExpiresDates() {
        let combined = "a=1; Path=/; Secure, b=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly, c=3"
        XCTAssertEqual(ProxyRule.splitSetCookie(combined),
                       ["a=1; Path=/; Secure", "b=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly", "c=3"])
    }
    func testSameOriginGuard() {
        XCTAssertTrue(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080"]))
        XCTAssertTrue(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "origin": "http://127.0.0.1:8080", "sec-fetch-site": "same-origin"]))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "origin": "https://evil.example"]))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "origin": "http://localhost:4200"]))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "sec-fetch-site": "cross-site"]))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "origin": "null"]))
    }
    func testOldOptionsWithoutProxyRulesDecode() throws {
        let o = try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"spaMode":true,"liveReload":true,"serveDotfiles":false,"cors":true}"#.utf8))
        XCTAssertTrue(o.proxyRules.isEmpty); XCTAssertTrue(o.cors)
    }
    func testLoopbackDetection() {
        for h in ["localhost", "LOCALHOST", "127.0.0.1", "::1", "api.localhost"] { XCTAssertTrue(ProxyForwarder.isLoopback(h), h) }
        for h in ["example.com", "192.168.1.2", "localhost.evil.com", "10.0.0.1"] { XCTAssertFalse(ProxyForwarder.isLoopback(h), h) }
    }
}

final class AddressRewriteUnitTests: XCTestCase {
    private func rewrite(_ text: String, origins: [String] = ["https://localhost:5003"], to local: String = "http://127.0.0.1:8080") -> String? {
        ProxyRule.rewriteAddresses(in: Data(text.utf8), origins: origins, with: local).map { String(decoding: $0, as: UTF8.self) }
    }
    func testReplacesWholeAddressKeepingThePath() {
        XCTAssertEqual(rewrite(#"{"baseUrl":"https://localhost:5003/uiapi/","raw":"https://localhost:5003/"}"#),
                       #"{"baseUrl":"http://127.0.0.1:8080/uiapi/","raw":"http://127.0.0.1:8080/"}"#)
    }
    func testIsCaseInsensitiveForSchemeAndHost() {
        XCTAssertEqual(rewrite("HTTPS://LocalHost:5003/x"), "http://127.0.0.1:8080/x")
    }
    func testHandlesJSONEscapedSlashes() {
        XCTAssertEqual(rewrite(#"{"u":"https:\/\/localhost:5003\/uiapi"}"#), #"{"u":"http:\/\/127.0.0.1:8080\/uiapi"}"#)
    }
    func testDoesNotTouchOtherPortsOrLongerHosts() {
        XCTAssertNil(rewrite("https://localhost:50031/x"))
        XCTAssertNil(rewrite("https://localhost:5003x/x"))
        XCTAssertNil(rewrite("https://localhost.example.com:5003/x") )
        XCTAssertNil(rewrite("https://other.example/x"))
        XCTAssertNil(rewrite("http://localhost:5003/x"), "a different scheme is a different address")
    }
    func testReturnsNilWhenNothingToDoOrNotText() {
        XCTAssertNil(rewrite("no address here"))
        XCTAssertNil(ProxyRule.rewriteAddresses(in: Data([0xff, 0xfe, 0x00, 0x01]), origins: ["https://localhost:5003"], with: "http://x"))
        XCTAssertNil(ProxyRule.rewriteAddresses(in: Data("https://localhost:5003".utf8), origins: [], with: "http://x"))
    }
    func testMultipleOrigins() {
        XCTAssertEqual(rewrite("a https://localhost:5003/ b http://localhost:3000/", origins: ["https://localhost:5003", "http://localhost:3000"]),
                       "a http://127.0.0.1:8080/ b http://127.0.0.1:8080/")
    }
    func testReplacementTextIsNotInterpretedAsATemplate() {
        XCTAssertEqual(rewrite("https://localhost:5003/", to: "http://h$1:80"), "http://h$1:80/")
    }
    func testOldRulesWithoutTheFlagDefaultToRewriting() throws {
        let r = try JSONDecoder().decode(ProxyRule.self, from: Data(#"{"prefix":"/a","target":"http://x:1"}"#.utf8))
        XCTAssertTrue(r.rewriteAddress)
    }
}

final class AddressRewriteIntegrationTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default
    let api = "https://localhost:5003"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("rw-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try #"{ "baseUrl" : "https://localhost:5003/uiapi/" }"#.write(to: root.appendingPathComponent("assets/config.json"), atomically: true, encoding: .utf8)
        try #"const base="https://localhost:5003/uiapi/";"#.write(to: root.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        try "const x = 1;".write(to: root.appendingPathComponent("plain.js"), atomically: true, encoding: .utf8)
        try "<html><body><script>var u='https://localhost:5003/uiapi/'</script></body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "https://localhost:5003 in a text file".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        try "https://localhost:5003 in a css file".write(to: root.appendingPathComponent("a.css"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private func start(rewrite: Bool = true, liveReload: Bool = true, rules: [ProxyRule]? = nil) async throws -> UInt16 {
        let rs = rules ?? [ProxyRule(prefix: "/uiapi", target: api, rewriteAddress: rewrite)]
        server = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: liveReload, proxyRules: rs))
        return try await server.start()
    }
    private func get(_ port: UInt16, _ path: String, host: String? = nil, headers: String = "") throws -> RawResponse {
        try XCTUnwrap(RawHTTP.request(port: port, "GET \(path) HTTP/1.1\r\nHost: \(host ?? "127.0.0.1:\(port)")\r\n\(headers)\r\n"))
    }

    func testConfigJSONPointsAtThisServer() async throws {
        let port = try await start()
        let r = try get(port, "/assets/config.json")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.text, #"{ "baseUrl" : "http://127.0.0.1:\#(port)/uiapi/" }"#)
        XCTAssertEqual(r.headers["content-length"], String(r.body.count))
        XCTAssertEqual(r.headers["content-type"], "application/json; charset=utf-8")
    }

    func testUsesTheHostHeaderTheBrowserUsed() async throws {
        let port = try await start()
        XCTAssertTrue(try get(port, "/main.js", host: "localhost:\(port)").text.contains("http://localhost:\(port)/uiapi/"))
    }

    func testJSAndHTMLAreRewritten_HTMLStillGetsLiveReload() async throws {
        let port = try await start()
        XCTAssertTrue(try get(port, "/main.js").text.contains("http://127.0.0.1:\(port)/uiapi/"))
        let html = try get(port, "/index.html").text
        XCTAssertTrue(html.contains("http://127.0.0.1:\(port)/uiapi/"))
        XCTAssertTrue(html.contains("__reload"), "live reload script is still injected")
    }

    func testSPAFallbackPageIsRewrittenToo() async throws {
        let port = try await start()
        let r = try get(port, "/some/deep/link", headers: "Accept: text/html\r\n")
        XCTAssertTrue(r.text.contains("http://127.0.0.1:\(port)/uiapi/"))
    }

    func testOtherFileTypesAndFilesWithoutTheAddressAreUntouched() async throws {
        let port = try await start()
        XCTAssertEqual(try get(port, "/notes.txt").text, "https://localhost:5003 in a text file")
        XCTAssertEqual(try get(port, "/a.css").text, "https://localhost:5003 in a css file")
        XCTAssertEqual(try get(port, "/plain.js").text, "const x = 1;")
    }

    func testSwitchOffLeavesFilesAlone() async throws {
        let port = try await start(rewrite: false)
        XCTAssertEqual(try get(port, "/assets/config.json").text, #"{ "baseUrl" : "https://localhost:5003/uiapi/" }"#)
    }

    func testNoRulesMeansNoRewriting() async throws {
        let port = try await start(rules: [])
        XCTAssertTrue(try get(port, "/main.js").text.contains("https://localhost:5003"))
    }

    func testInvalidRuleIsIgnored() async throws {
        let port = try await start(rules: [ProxyRule(prefix: "/", target: api)])
        XCTAssertTrue(try get(port, "/main.js").text.contains("https://localhost:5003"))
    }

    func testFilesOverTheSizeLimitAreServedUnchanged() async throws {
        let big = String(repeating: "x", count: ProxyRule.maxRewritableBytes + 10) + " https://localhost:5003"
        try big.write(to: root.appendingPathComponent("big.js"), atomically: true, encoding: .utf8)
        let port = try await start()
        let r = try get(port, "/big.js")
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.text.hasSuffix(" https://localhost:5003"))
    }

    func testRangeRequestsAreServedFromTheOriginalFile() async throws {
        let port = try await start()
        let r = try get(port, "/main.js", headers: "Range: bytes=0-4\r\n")
        XCTAssertEqual(r.status, 206)
        XCTAssertEqual(r.text, "const")
    }

    func testRewritingIsOnlyAnswerToTheRequestingHostNotCached() async throws {
        let port = try await start()
        let a = try get(port, "/main.js", host: "127.0.0.1:\(port)").text
        let b = try get(port, "/main.js", host: "localhost:\(port)").text
        XCTAssertNotEqual(a, b)
    }
}

final class ProxyIntegrationTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    var upstream: FakeUpstream!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("px-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html><body>app</body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: root.appendingPathComponent("api"), withIntermediateDirectories: true)
        try "FILE".write(to: root.appendingPathComponent("api/shadowed.txt"), atomically: true, encoding: .utf8)
        upstream = FakeUpstream(); upstream.start()
    }
    override func tearDownWithError() throws { server?.stop(); upstream.stop(); try? fm.removeItem(at: root) }

    private func start(rules: [ProxyRule]? = nil, cors: Bool = false, timeout: TimeInterval = 60) async throws -> UInt16 {
        let rule = rules ?? [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")]
        server = StaticServer(root: root, port: 0, options: ServeOptions(cors: cors, proxyRules: rule))
        server.proxyTimeout = timeout
        return try await server.start()
    }
    private func send(_ port: UInt16, _ method: String, _ path: String, headers: String = "", body: String = "") throws -> RawResponse {
        var raw = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\(headers)"
        if !body.isEmpty { raw += "Content-Length: \(body.utf8.count)\r\n" }
        raw += "\r\n" + body
        return try XCTUnwrap(RawHTTP.request(port: port, raw))
    }

    func testGETIsForwardedWithPathAndQuery() async throws {
        let port = try await start()
        let r = try send(port, "GET", "/api/users?id=7")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.text, "GET /api/users?id=7 body=")
        XCTAssertEqual(upstream.last?.target, "/api/users?id=7")
    }

    func testPOSTBodyAndHeadersAreForwarded() async throws {
        let port = try await start()
        let json = #"{"user":"a","password":"b"}"#
        let r = try send(port, "POST", "/api/Account/Login", headers: "Content-Type: application/json\r\nAuthorization: Bearer t0k\r\nCookie: s=1\r\n", body: json)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.text, "POST /api/Account/Login body=\(json)")
        XCTAssertEqual(upstream.last?.headers["content-type"], "application/json")
        XCTAssertEqual(upstream.last?.headers["authorization"], "Bearer t0k")
        XCTAssertEqual(upstream.last?.headers["cookie"], "s=1")
        XCTAssertEqual(upstream.last?.headers["accept-encoding"], "identity")
    }

    func testLargeBodyArrivesIntact() async throws {
        let port = try await start()
        let big = String(repeating: "x", count: 300_000)
        let r = try send(port, "PUT", "/api/blob", body: big)
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(upstream.last?.body.count, 300_000)
    }

    func testOriginAndRefererAreRewrittenToTheTarget() async throws {
        let port = try await start()
        _ = try send(port, "POST", "/api/x", headers: "Origin: http://127.0.0.1:\(port)\r\nReferer: http://127.0.0.1:\(port)/page\r\n", body: "{}")
        XCTAssertEqual(upstream.last?.headers["origin"], "http://127.0.0.1:\(upstream.port)")
        XCTAssertEqual(upstream.last?.headers["referer"], "http://127.0.0.1:\(upstream.port)/")
    }

    func testStripPrefix() async throws {
        let port = try await start(rules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)", stripPrefix: true)])
        XCTAssertEqual(try send(port, "GET", "/api/users").text, "GET /users body=")
    }

    func testProxyTakesPrecedenceOverFilesAndOtherPathsStillServed() async throws {
        let port = try await start()
        XCTAssertTrue(try send(port, "GET", "/api/shadowed.txt").text.hasPrefix("GET /api/shadowed.txt"))
        XCTAssertTrue(try send(port, "GET", "/").text.contains("app"))
        XCTAssertTrue(try send(port, "GET", "/apix").text.contains("app"), "SPA fallback, not proxied")
    }

    func testUpstreamStatusAndBodyArePassedThrough() async throws {
        let port = try await start()
        let r = try send(port, "GET", "/api/missing")
        XCTAssertEqual(r.status, 404)
        XCTAssertEqual(r.headers["content-type"], "application/json")
        XCTAssertEqual(r.text, #"{"error":"nope"}"#)
        XCTAssertEqual(try send(port, "GET", "/api/empty").status, 204)
    }

    func testHEADHasNoBody() async throws {
        let port = try await start()
        let r = try send(port, "HEAD", "/api/users")
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.body.isEmpty)
    }

    func testRedirectIsNotFollowedAndLocationIsLocalised() async throws {
        let port = try await start()
        let r = try send(port, "GET", "/api/redirect")
        XCTAssertEqual(r.status, 302)
        XCTAssertEqual(r.headers["location"], "/landing")
    }

    func testSetCookieIsRewrittenAndSplit() async throws {
        let port = try await start()
        let raw = try XCTUnwrap(RawHTTP.rawText(port: port, "GET /api/cookie HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"))
        let cookies = raw.components(separatedBy: "\r\n").filter { $0.lowercased().hasPrefix("set-cookie:") }
        XCTAssertEqual(cookies.count, 2)
        XCTAssertTrue(cookies[0].contains("a=1; Path=/; SameSite=Lax"), cookies[0])
        XCTAssertFalse(cookies[0].lowercased().contains("secure"))
        XCTAssertFalse(cookies[0].lowercased().contains("domain"))
        XCTAssertTrue(cookies[1].contains("Expires=Wed, 21 Oct 2026"), cookies[1])
    }

    func testResponseIsStreamedNotBuffered() async throws {
        let port = try await start()
        let r = try send(port, "GET", "/api/stream")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.text, "onetwothree")
    }

    func testUpstreamDownReturns502() async throws {
        let dead = FakeUpstream(); dead.start(); let deadPort = dead.port; dead.stop()
        let port = try await start(rules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(deadPort)")])
        let r = try send(port, "GET", "/api/x")
        XCTAssertEqual(r.status, 502)
        XCTAssertTrue(r.text.contains("Cannot reach"))
    }

    func testSlowUpstreamReturns504() async throws {
        let port = try await start(timeout: 0.5)
        let r = try send(port, "GET", "/api/slow")
        XCTAssertEqual(r.status, 504)
    }

    func testCrossOriginRequestsAreBlockedWithoutCORS() async throws {
        let port = try await start()
        let before = upstream.seen.count
        let r = try send(port, "POST", "/api/transfer", headers: "Origin: https://evil.example\r\n", body: "{}")
        XCTAssertEqual(r.status, 403)
        let r2 = try send(port, "GET", "/api/x", headers: "Sec-Fetch-Site: cross-site\r\n")
        XCTAssertEqual(r2.status, 403)
        XCTAssertEqual(upstream.seen.count, before, "nothing may reach the backend")
    }

    func testCrossOriginAllowedWhenCORSIsOnAndHeadersAdded() async throws {
        let port = try await start(cors: true)
        let r = try send(port, "GET", "/api/x", headers: "Origin: http://localhost:4200\r\n")
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.headers["access-control-allow-origin"], "*", "ours replaces the upstream's")
    }

    func testForeignHostIsStillRejected() async throws {
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.request(port: port, "GET /api/x HTTP/1.1\r\nHost: evil.example.com\r\n\r\n"))
        XCTAssertEqual(r.status, 403)
    }

    func testInvalidRulesAreIgnored() async throws {
        let port = try await start(rules: [ProxyRule(prefix: "/api", target: "nonsense")])
        XCTAssertEqual(try send(port, "GET", "/api/shadowed.txt").text, "FILE")
    }

    func testRulesCanBeChangedWhileRunning() async throws {
        let port = try await start(rules: [])
        XCTAssertEqual(try send(port, "GET", "/api/shadowed.txt").text, "FILE")
        server.updateOptions(ServeOptions(proxyRules: [ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")]))
        XCTAssertTrue(try send(port, "GET", "/api/shadowed.txt").text.hasPrefix("GET /api/shadowed.txt"))
    }

    func testRequestLogMentionsTheTarget() async throws {
        let port = try await start()
        let box = LogBox()
        server.onRequest = { box.add($0) }
        _ = try send(port, "GET", "/api/users")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(box.entries.last?.note, "→ http://127.0.0.1:\(upstream.port)")
        XCTAssertEqual(box.entries.last?.status, 200)
    }
}

/// The case from ASP.NET Core development: an HTTPS API on localhost with a self-signed certificate.
final class ProxySelfSignedHTTPSTests: XCTestCase {
    private var dir: URL!
    private var openssl: Process?
    private var server: StaticServer?

    override func tearDown() { openssl?.terminate(); server?.stop(); if let dir { try? FileManager.default.removeItem(at: dir) } }

    func testSelfSignedHTTPSOnLoopbackIsAccepted() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/openssl") else { throw XCTSkip("openssl not available") }
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("uiapi/Account"), withIntermediateDirectories: true)
        try "LOGIN-PAGE".write(to: dir.appendingPathComponent("uiapi/Account/Login"), atomically: true, encoding: .utf8)
        func run(_ args: [String]) throws {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); p.arguments = args
            p.currentDirectoryURL = dir; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try p.run(); p.waitUntilExit()
            if p.terminationStatus != 0 { throw XCTSkip("openssl \(args.first ?? "") failed") }
        }
        try run(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "k.pem", "-out", "c.pem", "-days", "1", "-subj", "/CN=localhost"])

        let apiPort = UInt16.random(in: 30_000...60_000)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        p.arguments = ["s_server", "-accept", "\(apiPort)", "-cert", "c.pem", "-key", "k.pem", "-WWW"]
        p.currentDirectoryURL = dir; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); openssl = p
        var up = false
        for _ in 0..<40 { let fd = RawHTTP.openSocket(host: "127.0.0.1", port: apiPort); if fd >= 0 { close(fd); up = true; break }; try await Task.sleep(nanoseconds: 100_000_000) }
        guard up else { throw XCTSkip("openssl s_server did not start") }

        let root = dir.appendingPathComponent("site"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let s = StaticServer(root: root, port: 0, options: ServeOptions(proxyRules: [ProxyRule(prefix: "/uiapi", target: "https://127.0.0.1:\(apiPort)")]))
        server = s
        let port = try await s.start()
        let r = try XCTUnwrap(RawHTTP.request(port: port, "GET /uiapi/Account/Login HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"))
        XCTAssertEqual(r.status, 200, r.text)
        XCTAssertEqual(r.text, "LOGIN-PAGE")
    }
}

final class LogBox: @unchecked Sendable {
    private let lock = NSLock(); private var _e: [RequestLogEntry] = []
    func add(_ e: RequestLogEntry) { lock.lock(); _e.append(e); lock.unlock() }
    var entries: [RequestLogEntry] { lock.lock(); defer { lock.unlock() }; return _e }
}
