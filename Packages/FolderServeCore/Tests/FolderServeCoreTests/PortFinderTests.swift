import XCTest
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
}
