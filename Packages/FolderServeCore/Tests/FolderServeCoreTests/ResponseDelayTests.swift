import XCTest
@testable import FolderServeCore

final class ResponseDelayTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("dly-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "hello".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    private func start(_ options: ServeOptions) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: options)
        return try await server.start()
    }
    private func timed(_ port: UInt16, _ raw: String) throws -> (RawResponse, TimeInterval) {
        let began = Date()
        let r = try XCTUnwrap(RawHTTP.request(port: port, raw))
        return (r, Date().timeIntervalSince(began))
    }

    func testEffectiveDelayIsClampedAndOlderSettingsHaveNone() throws {
        XCTAssertEqual(ServeOptions().effectiveDelayMs, 0)
        XCTAssertEqual(ServeOptions(responseDelayMs: -5).effectiveDelayMs, 0)
        XCTAssertEqual(ServeOptions(responseDelayMs: 700).effectiveDelayMs, 700)
        XCTAssertEqual(ServeOptions(responseDelayMs: 99_999).effectiveDelayMs, ServeOptions.maxDelayMs)
        XCTAssertEqual(try JSONDecoder().decode(ServeOptions.self, from: Data("{}".utf8)).responseDelayMs, 0)
    }

    func testAnswersAreHeldBackAndTheTimeIsLogged() async throws {
        let logged = Durations()
        let port = try await start(ServeOptions(mocks: [MockRule(path: "/api/x", body: "m")], responseDelayMs: 300))
        server.onRequest = { logged.add($0.durationMs ?? -1) }
        let (file, fileTime) = try timed(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(file.text, "hello")
        XCTAssertGreaterThanOrEqual(fileTime, 0.28)
        let (mock, mockTime) = try timed(port, "GET /api/x HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(mock.text, "m")
        XCTAssertGreaterThanOrEqual(mockTime, 0.28)
        let (missing, missingTime) = try timed(port, "GET /nope.txt HTTP/1.1\r\nHost: localhost\r\n\r\n")
        XCTAssertEqual(missing.status, 404)
        XCTAssertGreaterThanOrEqual(missingTime, 0.28)
        for _ in 0..<100 where logged.values.count < 3 { usleep(10_000) }
        XCTAssertTrue(logged.values.allSatisfy { $0 >= 280 }, "\(logged.values)")
    }

    func testNoDelayByDefaultAndChangingTheOptionAppliesAtOnce() async throws {
        let port = try await start(ServeOptions())
        XCTAssertLessThan(try timed(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").1, 0.2)
        server.updateOptions(ServeOptions(responseDelayMs: 250))
        XCTAssertGreaterThanOrEqual(try timed(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").1, 0.23)
        server.updateOptions(ServeOptions())
        XCTAssertLessThan(try timed(port, "GET /a.txt HTTP/1.1\r\nHost: localhost\r\n\r\n").1, 0.2)
    }

    func testLiveReloadConnectionAndHostCheckAreNotDelayed() async throws {
        let port = try await start(ServeOptions(responseDelayMs: 2000))
        let began = Date()
        let r = try XCTUnwrap(RawHTTP.request(port: port, "GET /__reload HTTP/1.1\r\nHost: localhost\r\n\r\n", readLimit: 10))
        XCTAssertEqual(r.status, 200)
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.0)
        XCTAssertLessThan(try timed(port, "GET /a.txt HTTP/1.1\r\nHost: evil.example\r\n\r\n").1, 1.0)
    }
}

private final class Durations: @unchecked Sendable {
    private var v: [Int] = []
    private let lock = NSLock()
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return v }
    func add(_ x: Int) { lock.lock(); v.append(x); lock.unlock() }
}
