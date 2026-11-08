import XCTest
@testable import FolderServeCore

final class HostPolicyTests: XCTestCase {
    func testLoopbackNamesAndAddressesAreAllowed() {
        for host in ["localhost", "localhost:8080", "LOCALHOST", "127.0.0.1", "127.0.0.1:3000", "127.1.2.3",
                     "[::1]", "[::1]:8080", "app.localhost", "app.localhost:5173"] {
            XCTAssertTrue(HostPolicy.isAllowed(host), host)
        }
    }

    func testMissingHostIsAllowed() {
        XCTAssertTrue(HostPolicy.isAllowed(nil))
    }

    func testForeignHostsAreRejected() {
        for host in ["evil.example.com", "evil.example.com:8080", "localhost.evil.com", "127.0.0.1.evil.com",
                     "192.168.1.5", "192.168.1.5:80", "[2001:db8::1]:80", "", "notlocalhost", "evil.com#.localhost"] {
            XCTAssertFalse(HostPolicy.isAllowed(host), host)
        }
    }
}

final class LocalhostNameServerTests: XCTestCase {
    func testAFolderIsServedUnderItsLocalhostName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ln-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "named".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }
        let server = StaticServer(root: root, port: 0, options: ServeOptions())
        let port = try await server.start()
        defer { server.stop() }
        let ok = try XCTUnwrap(RawHTTP.request(port: port, "GET /a.txt HTTP/1.1\r\nHost: my-site.localhost:\(port)\r\n\r\n"))
        XCTAssertEqual(ok.status, 200); XCTAssertEqual(ok.text, "named")
        let rebinding = try XCTUnwrap(RawHTTP.request(port: port, "GET /a.txt HTTP/1.1\r\nHost: my-site.localhost.evil.com:\(port)\r\n\r\n"))
        XCTAssertEqual(rebinding.status, 403, "only names ending in .localhost are accepted")
    }
}
