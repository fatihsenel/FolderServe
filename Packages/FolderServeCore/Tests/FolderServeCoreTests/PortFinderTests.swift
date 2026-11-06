import XCTest
import Darwin
@testable import FolderServeCore

final class PortFinderTests: XCTestCase {
    var servers: [StaticServer] = []
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        servers.forEach { $0.stop() }
        try? FileManager.default.removeItem(at: root)
    }

    private func occupy() async throws -> UInt16 {
        let s = StaticServer(root: root, port: 0, options: ServeOptions())
        servers.append(s)
        return try await s.start()
    }

    func testReturnsStartPortWhenFree() async throws {
        let p = try await occupy()
        servers.removeLast().stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(PortFinder.firstFree(startingAt: p), p)
    }

    func testSkipsOccupiedPort() async throws {
        let p = try await occupy()
        let found = try XCTUnwrap(PortFinder.firstFree(startingAt: p))
        XCTAssertGreaterThan(found, p)
    }

    func testReturnsNilWhenRangeExhausted() async throws {
        let p = try await occupy()
        XCTAssertNil(PortFinder.firstFree(startingAt: p, upTo: p))
    }

    /// After a server restarts, sockets lingering in TIME_WAIT must not make the old port look taken
    /// (NWListener itself can rebind it), otherwise the URL drifts from :8080 to :8081 on every relaunch.
    func testPortWithTimeWaitConnectionsIsStillFree() throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        listen(listener, 1)
        var bound = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(listener, $0, &len) }
        }
        let port = UInt16(bigEndian: bound.sin_port)

        let client = RawHTTP.openSocket(host: "127.0.0.1", port: port)
        let accepted = accept(listener, nil, nil)
        close(accepted)   // server side closes first -> its port enters TIME_WAIT
        usleep(50_000)
        close(client)
        close(listener)

        XCTAssertEqual(PortFinder.firstFree(startingAt: port), port)
    }
}
