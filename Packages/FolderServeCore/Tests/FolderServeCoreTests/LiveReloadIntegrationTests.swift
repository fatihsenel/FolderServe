import XCTest
import Darwin
@testable import FolderServeCore

final class LiveReloadIntegrationTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default
    private let marker = "EventSource('/__reload')"

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("lr-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        server?.stop()
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ rel: String, _ body: String) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try body.write(to: url, atomically: false, encoding: .utf8)
        return url
    }

    private func start(_ o: ServeOptions = ServeOptions()) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: o)
        return try await server.start()
    }

    /// Opens /__reload and returns the socket after the response headers have arrived.
    private func openSSE(port: UInt16) throws -> Int32 {
        let fd = RawHTTP.openSocket(host: "127.0.0.1", port: port)
        XCTAssertGreaterThanOrEqual(fd, 0)
        let req = Array("GET /__reload HTTP/1.1\r\nHost: x\r\nAccept: text/event-stream\r\n\r\n".utf8)
        _ = send(fd, req, req.count, 0)
        let head = readSSE(fd, until: ": connected", timeout: 3)
        XCTAssertTrue(head.contains("text/event-stream"), "SSE headers: \(head)")
        return fd
    }

    /// Reads from `fd` until `needle` appears or `timeout` seconds pass; returns everything read.
    private func readSSE(_ fd: Int32, until needle: String, timeout: TimeInterval) -> String {
        var acc = Data()
        let deadline = Date().addingTimeInterval(timeout)
        var buf = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            if poll(&pfd, 1, 100) > 0 {
                let n = recv(fd, &buf, buf.count, 0)
                if n <= 0 { break }
                acc.append(buf, count: n)
                if String(decoding: acc, as: UTF8.self).contains(needle) { break }
            }
        }
        return String(decoding: acc, as: UTF8.self)
    }

    func testHTMLGetsScriptWithCorrectContentLength() async throws {
        try write("index.html", "<html><body>hi</body></html>")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/index.html"))
        XCTAssertTrue(r.text.contains(marker))
        XCTAssertEqual(r.headers["content-length"], String(r.body.count))
    }

    func testNonHTMLIsNeverModified() async throws {
        try write("a.css", "body{}")
        try write("a.js", "var x=1</body>")
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/a.css")?.text, "body{}")
        XCTAssertEqual(RawHTTP.get(port: port, "/a.js")?.text, "var x=1</body>")
    }

    func testSPAFallbackResponseGetsScript() async throws {
        try write("index.html", "<body></body>")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/users/42", headers: "Accept: text/html\r\n"))
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.text.contains(marker))
    }

    func testRangeRequestsOnHTMLAreNotInjected() async throws {
        try write("index.html", "0123456789")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/index.html", headers: "Range: bytes=0-3\r\n"))
        XCTAssertEqual(r.status, 206)
        XCTAssertEqual(r.text, "0123")
    }

    func testDirectoryListingGetsScript() async throws {
        try write("a.txt", "x")
        let port = try await start()
        XCTAssertTrue(RawHTTP.get(port: port, "/")?.text.contains(marker) ?? false)
    }

    func testNoInjectionWhenLiveReloadOff() async throws {
        try write("index.html", "<body>hi</body>")
        let port = try await start(ServeOptions(liveReload: false))
        XCTAssertFalse(RawHTTP.get(port: port, "/index.html")?.text.contains(marker) ?? true)
        server.updateOptions(ServeOptions(liveReload: true))
        XCTAssertTrue(RawHTTP.get(port: port, "/index.html")?.text.contains(marker) ?? false)
    }

    func testFileChangeSendsReloadEvent() async throws {
        let f = try write("index.html", "<body>1</body>")
        let port = try await start()
        let fd = try openSSE(port: port)
        defer { close(fd) }
        try await Task.sleep(nanoseconds: 400_000_000)
        try "<body>2</body>".write(to: f, atomically: false, encoding: .utf8)
        let got = readSSE(fd, until: "data:", timeout: 3)
        XCTAssertTrue(got.contains("data:"), "expected reload event, got: \(got)")
    }

    func testNoEventWhenLiveReloadOff() async throws {
        let f = try write("index.html", "<body>1</body>")
        let port = try await start(ServeOptions(liveReload: false))
        let fd = try openSSE(port: port)
        defer { close(fd) }
        try await Task.sleep(nanoseconds: 400_000_000)
        try "<body>2</body>".write(to: f, atomically: false, encoding: .utf8)
        XCTAssertFalse(readSSE(fd, until: "data:", timeout: 1.2).contains("data:"))
    }
}
