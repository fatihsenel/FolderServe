import XCTest
@testable import FolderServeCore

final class LANSharingTests: XCTestCase {
    func testPrivateAddressesAndLocalNamesAllowedOnlyWhenSharing() {
        for h in ["192.168.1.20:8080", "10.0.0.5", "172.16.4.9:80", "172.31.255.1", "macbook.local:8080", "Fatih-Mac.local"] {
            XCTAssertTrue(HostPolicy.isAllowed(h, allowLAN: true), h)
            XCTAssertFalse(HostPolicy.isAllowed(h), "\(h) must be refused when not shared")
        }
    }
    func testPublicNamesAndAddressesStayRefusedEvenWhenSharing() {
        for h in ["evil.example", "8.8.8.8", "172.32.0.1", "192.169.1.1", "localhost.evil.com", "10.0.0.256", "a.local.evil.com", "192.168.1.1.evil.com"] {
            XCTAssertFalse(HostPolicy.isAllowed(h, allowLAN: true), h)
        }
    }
    func testLoopbackStillWorksEitherWay() {
        XCTAssertTrue(HostPolicy.isAllowed("127.0.0.1:8080", allowLAN: true))
        XCTAssertTrue(HostPolicy.isAllowed("localhost", allowLAN: false))
    }
    func testOldSettingsDecodeWithSharingOff() throws {
        XCTAssertFalse(try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"cors":true}"#.utf8)).shareOnNetwork)
    }
    func testLANAddressesLookLikeIPv4() {
        for a in LANAddress.ipv4Addresses() { XCTAssertEqual(a.split(separator: ".").count, 4, a); XCTAssertFalse(a.hasPrefix("127.")) }
    }

    func testSharedServerAnswersOnTheLANAddressAndOffServerDoesNot() async throws {
        guard let lan = LANAddress.ipv4Addresses().first else { throw XCTSkip("no LAN interface") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hi".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let shared = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: false, shareOnNetwork: true))
        let sp = try await shared.start(); defer { shared.stop() }
        let ok = RawHTTP.request(port: sp, "GET /a.txt HTTP/1.1\r\nHost: \(lan):\(sp)\r\n\r\n", host: lan)
        XCTAssertEqual(ok?.status, 200); XCTAssertEqual(ok?.text, "hi")
        let rebind = RawHTTP.request(port: sp, "GET /a.txt HTTP/1.1\r\nHost: evil.example\r\n\r\n", host: lan)
        XCTAssertEqual(rebind?.status, 403)

        let local = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: false))
        let lp = try await local.start(); defer { local.stop() }
        XCTAssertNil(RawHTTP.request(port: lp, "GET /a.txt HTTP/1.1\r\nHost: \(lan)\r\n\r\n", host: lan), "not shared: the LAN address must not connect")
    }
}
