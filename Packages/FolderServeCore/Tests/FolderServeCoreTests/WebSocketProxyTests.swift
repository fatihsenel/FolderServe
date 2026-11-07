import XCTest
import Darwin
@testable import FolderServeCore

final class WebSocketProxyTests: XCTestCase {
    private var root: URL!
    private var server: StaticServer?
    private let upstream = FakeUpstream()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        upstream.start()
    }
    override func tearDownWithError() throws { server?.stop(); upstream.stop(); try? FileManager.default.removeItem(at: root) }

    private func start() async throws -> UInt16 {
        let rule = ProxyRule(prefix: "/api", target: "http://127.0.0.1:\(upstream.port)")
        server = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: false, proxyRules: [rule]))
        return try await server!.start()
    }

    private func upgrade(_ port: UInt16, path: String = "/api/ws", extra: String = "") -> String {
        "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\(extra)\r\n"
    }

    func testUpgradeIsTunnelledAndBytesFlowBothWays() async throws {
        let port = try await start()
        let fd = RawHTTP.openSocket(host: "127.0.0.1", port: port)
        XCTAssertGreaterThanOrEqual(fd, 0); defer { close(fd) }
        let req = Array(upgrade(port, extra: "Origin: http://127.0.0.1:\(port)\r\n").utf8)
        _ = send(fd, req, req.count, 0)
        var buf = [UInt8](repeating: 0, count: 4096)
        var got = Data()
        while got.range(of: Data("\r\n\r\n".utf8)) == nil { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; got.append(buf, count: n) }
        XCTAssertTrue(String(decoding: got, as: UTF8.self).hasPrefix("HTTP/1.1 101"))
        let ping = Array("hello-through-the-tunnel".utf8)
        _ = send(fd, ping, ping.count, 0)
        var echoed = Data()
        while echoed.count < ping.count { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; echoed.append(buf, count: n) }
        XCTAssertEqual(String(decoding: echoed, as: UTF8.self), "hello-through-the-tunnel")
        // The upstream saw a rewritten Host/Origin and the handshake key.
        let seen = try XCTUnwrap(upstream.last)
        XCTAssertEqual(seen.target, "/api/ws")
        XCTAssertEqual(seen.headers["host"], "127.0.0.1:\(upstream.port)")
        XCTAssertEqual(seen.headers["origin"], "http://127.0.0.1:\(upstream.port)")
        XCTAssertEqual(seen.headers["sec-websocket-key"], "dGhlIHNhbXBsZSBub25jZQ==")
    }

    func testUpgradeIsLoggedOnce() async throws {
        let port = try await start()
        let logged = LockedBox<[RequestLogEntry]>([])
        server?.onRequest = { e in logged.value.append(e) }
        let fd = RawHTTP.openSocket(host: "127.0.0.1", port: port); defer { close(fd) }
        let req = Array(upgrade(port).utf8); _ = send(fd, req, req.count, 0)
        var buf = [UInt8](repeating: 0, count: 4096); _ = recv(fd, &buf, buf.count, 0)
        try await Task.sleep(nanoseconds: 300_000_000)
        let entries = logged.value
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.status, 101)
        XCTAssertEqual(entries.first?.note, "WebSocket → http://127.0.0.1:\(upstream.port)")
    }

    func testCrossSiteUpgradeIsRefusedWhenCORSIsOff() async throws {
        let port = try await start()
        let r = RawHTTP.request(port: port, upgrade(port, extra: "Origin: http://evil.example\r\n"))
        XCTAssertEqual(r?.status, 403)
        XCTAssertTrue(upstream.seen.isEmpty, "the upstream must never see a cross-site socket")
    }

    func testDeadUpstreamAnswers502() async throws {
        let port = try await start()
        upstream.stop()
        let r = RawHTTP.request(port: port, upgrade(port))
        XCTAssertEqual(r?.status, 502)
    }
}
