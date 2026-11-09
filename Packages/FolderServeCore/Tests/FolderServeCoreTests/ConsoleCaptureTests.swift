import XCTest
@testable import FolderServeCore

final class ConsoleCaptureTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("con-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html><head><title>t</title></head><body>x</body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private let got = Box()

    private func start(_ options: ServeOptions) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: options)
        let got = self.got
        server.onConsole = { got.add($0) }
        server.onRequest = { got.addRequest($0) }
        return try await server.start()
    }
    private func req(_ port: UInt16, _ raw: String) throws -> RawResponse { try XCTUnwrap(RawHTTP.request(port: port, raw)) }
    private func post(_ port: UInt16, _ body: String, extra: String = "") throws -> RawResponse {
        try req(port, "POST /__console HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\(extra)Content-Length: \(body.utf8.count)\r\n\r\n\(body)")
    }

    // MARK: Parsing and injection

    func testParseKeepsKnownLevelsAndCapsEverything() {
        let json = #"[{"l":"error","m":"boom","u":"/a"},{"l":"log","m":"skip"},{"l":"warn","m":""},{"l":"uncaught","m":"x"},"junk"]"#
        XCTAssertEqual(ConsoleMessage.parse(Data(json.utf8)).count, 0)   // a non-object item makes the whole post invalid
        let ok = #"[{"l":"error","m":"boom","u":"/a"},{"l":"log","m":"skip"},{"l":"warn","m":""},{"l":"uncaught","m":"x"}]"#
        let parsed = ConsoleMessage.parse(Data(ok.utf8))
        XCTAssertEqual(parsed.map(\.level), [.error, .uncaught])
        XCTAssertEqual(parsed.first?.text, "boom")
        XCTAssertEqual(parsed.first?.page, "/a")
        XCTAssertEqual(ConsoleMessage.parse(Data("not json".utf8)), [])
        XCTAssertEqual(ConsoleMessage.parse(Data(#"{"l":"error"}"#.utf8)), [])

        let many = "[" + (0..<80).map { _ in #"{"l":"warn","m":"w"}"# }.joined(separator: ",") + "]"
        XCTAssertEqual(ConsoleMessage.parse(Data(many.utf8)).count, ConsoleMessage.maxPerPost)
        let long = #"[{"l":"error","m":""# + String(repeating: "a", count: 9_000) + #""}]"#
        XCTAssertEqual(ConsoleMessage.parse(Data(long.utf8)).first?.text.count, ConsoleMessage.maxTextLength)
        XCTAssertEqual(ConsoleMessage.parse(Data(count: ConsoleMessage.maxPostBytes + 1)), [])
    }

    func testScriptGoesRightAfterHead() {
        func inject(_ s: String) -> String { String(decoding: ConsoleMessage.inject(into: Data(s.utf8)), as: UTF8.self) }
        let tag = "<script>\(ConsoleMessage.script)</script>"
        XCTAssertEqual(inject("<html><head><title>t</title></head></html>"), "<html><head>\(tag)<title>t</title></head></html>")
        XCTAssertEqual(inject("<HEAD lang=\"en\">x"), "<HEAD lang=\"en\">\(tag)x")
        XCTAssertEqual(inject("<header>h</header>"), "<header>h</header>\(tag)")   // <header> is not <head>
        XCTAssertEqual(inject("<p>fragment</p>"), "<p>fragment</p>\(tag)")
    }

    func testPagesGetTheScriptOnlyWhenTheOptionIsOn() async throws {
        var port = try await start(ServeOptions(liveReload: false))
        var page = try req(port, "GET / HTTP/1.1\r\nHost: localhost\r\nAccept: text/html\r\n\r\n")
        XCTAssertFalse(page.text.contains("__console"))
        XCTAssertEqual(page.headers["content-length"], String(page.body.count))
        server.stop()

        port = try await start(ServeOptions(liveReload: false, captureConsole: true))
        page = try req(port, "GET / HTTP/1.1\r\nHost: localhost\r\nAccept: text/html\r\n\r\n")
        XCTAssertTrue(page.text.contains("<head><script>(function(){var q=[]"))
        XCTAssertFalse(page.text.contains("EventSource"))
        XCTAssertEqual(page.headers["content-length"], String(page.body.count))
        server.stop()

        port = try await start(ServeOptions(liveReload: true, captureConsole: true))
        page = try req(port, "GET / HTTP/1.1\r\nHost: localhost\r\nAccept: text/html\r\n\r\n")
        XCTAssertTrue(page.text.contains("/__console") && page.text.contains("EventSource"))
    }

    // MARK: Endpoint

    func testPostedLinesReachTheAppAndAreNotLoggedAsRequests() async throws {
        let port = try await start(ServeOptions(captureConsole: true))
        let r = try post(port, #"[{"l":"error","m":"TypeError: x is undefined","u":"/orders"}]"#,
                         extra: "Origin: http://127.0.0.1:\(port)\r\nSec-Fetch-Site: same-origin\r\n")
        XCTAssertEqual(r.status, 204)
        let messages = try XCTUnwrap(waitFor { self.got.messages.isEmpty ? nil : self.got.messages })
        XCTAssertEqual(messages.map(\.text), ["TypeError: x is undefined"])
        XCTAssertEqual(messages.first?.page, "/orders")
        usleep(50_000)
        XCTAssertTrue(got.requests.isEmpty)
    }

    func testEndpointIsClosedWhenOffAndToOtherSites() async throws {
        var port = try await start(ServeOptions())
        XCTAssertEqual(try post(port, #"[{"l":"error","m":"x"}]"#).status, 404)
        server.stop()

        port = try await start(ServeOptions(cors: true, captureConsole: true))
        let body = #"[{"l":"error","m":"x"}]"#
        XCTAssertEqual(try post(port, body, extra: "Origin: http://evil.example\r\n").status, 403)
        XCTAssertEqual(try post(port, body, extra: "Sec-Fetch-Site: cross-site\r\n").status, 403)
        XCTAssertEqual(try req(port, "POST /__console HTTP/1.1\r\nHost: evil.example\r\nContent-Length: 2\r\n\r\n[]").status, 403)
        XCTAssertEqual(try req(port, "GET /__console HTTP/1.1\r\nHost: localhost\r\n\r\n").status, 404)
        XCTAssertEqual(try req(port, "POST /__console HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999\r\n\r\n").status, 413)
        usleep(50_000)
        XCTAssertTrue(got.messages.isEmpty)
    }

    func testOlderSavedOptionsHaveItOff() throws {
        XCTAssertFalse(try JSONDecoder().decode(ServeOptions.self, from: Data("{}".utf8)).captureConsole)
    }

    private func waitFor<T>(_ value: () -> T?) -> T? {
        for _ in 0..<200 { if let v = value() { return v }; usleep(10_000) }
        return nil
    }
}

private final class Box: @unchecked Sendable {
    private var m: [ConsoleMessage] = []
    private var r: [RequestLogEntry] = []
    private let lock = NSLock()
    var messages: [ConsoleMessage] { lock.lock(); defer { lock.unlock() }; return m }
    var requests: [RequestLogEntry] { lock.lock(); defer { lock.unlock() }; return r }
    func add(_ x: [ConsoleMessage]) { lock.lock(); m += x; lock.unlock() }
    func addRequest(_ x: RequestLogEntry) { lock.lock(); r.append(x); lock.unlock() }
}
