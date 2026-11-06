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
