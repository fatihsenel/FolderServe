import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class RequestReplayTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:9001/")!

    private func entry(_ method: String = "GET", url: String = "http://192.168.1.20:8080/api/users?id=7&q=a%20b",
                       headers: [String: String] = [:]) -> RequestLogEntry {
        var e = RequestLogEntry(method: method, path: "/api/users", status: 200, bytes: 10)
        e.url = url
        e.requestHeaders = HTTPHeaderField.sorted(headers)
        return e
    }

    func testPathQueryAndHeadersAreKeptAndTheServerAddressIsTheCurrentOne() throws {
        let e = entry(headers: ["host": "192.168.1.20:8080", "accept": "application/json", "cookie": "s=1",
                                "content-length": "0", "connection": "keep-alive", "authorization": "Bearer t"])
        let r = try RequestReplay.urlRequest(for: e, base: base).get()
        XCTAssertEqual(r.url?.absoluteString, "http://127.0.0.1:9001/api/users?id=7&q=a%20b", "current port, logged path and query")
        XCTAssertEqual(r.httpMethod, "GET")
        XCTAssertEqual(r.value(forHTTPHeaderField: "accept"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: "cookie"), "s=1")
        XCTAssertEqual(r.value(forHTTPHeaderField: "authorization"), "Bearer t")
        XCTAssertNil(r.value(forHTTPHeaderField: "host"))
        XCTAssertNil(r.value(forHTTPHeaderField: "content-length"))
        XCTAssertEqual(r.value(forHTTPHeaderField: RequestLogEntry.replayHeader), "1")
        XCTAssertFalse(r.httpShouldHandleCookies)
    }

    func testBodyIsSentWhenItWasCapturedWhole() throws {
        var e = entry("POST")
        e.requestBody = Data(#"{"a":1}"#.utf8)
        let r = try RequestReplay.urlRequest(for: e, base: base).get()
        XCTAssertEqual(r.httpBody, Data(#"{"a":1}"#.utf8))
    }

    func testCutOffOrDroppedBodiesCannotBeReplayed() {
        var cut = entry("POST"); cut.requestBody = Data("{".utf8); cut.requestBodyTruncated = true
        XCTAssertEqual(RequestReplay.urlRequest(for: cut, base: base).failure, .bodyCutOff)
        var dropped = entry("PUT"); dropped.bodiesDropped = true
        XCTAssertEqual(RequestReplay.urlRequest(for: dropped, base: base).failure, .bodyDropped)
        var get = entry("GET"); get.bodiesDropped = true
        XCTAssertNotNil(try? RequestReplay.urlRequest(for: get, base: base).get(), "a GET has no body to lose")
    }

    func testNeedsARunningServer() {
        XCTAssertEqual(RequestReplay.urlRequest(for: entry(), base: nil).failure, .notRunning)
    }

    func testPathOnlyEntriesWork() throws {
        var e = RequestLogEntry(method: "GET", path: "/a.txt", status: 200, bytes: 1)
        e.url = ""
        XCTAssertEqual(try RequestReplay.urlRequest(for: e, base: base).get().url?.absoluteString, "http://127.0.0.1:9001/a.txt")
    }

    /// End to end: replaying sends a real request that the server logs, marked as a replay.
    func testReplayReachesTheServerAndIsLogged() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("rp-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "hi".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        var url: URL?
        for _ in 0..<250 { url = manager.url(for: id); if url != nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        let base = try XCTUnwrap(url)

        var e = RequestLogEntry(method: "GET", path: "/a.txt", status: 200, bytes: 2)
        e.url = "http://127.0.0.1:1/a.txt"   // an old port: the replay must use the server's current one
        let request = try RequestReplay.urlRequest(for: e, base: base).get()
        let result = await RequestReplay.send(request)
        XCTAssertEqual(try result.get(), 200)

        for _ in 0..<250 where !manager.log.contains(where: { $0.entry.isReplay }) { try await Task.sleep(nanoseconds: 20_000_000) }
        let logged = try XCTUnwrap(manager.log.first { $0.entry.isReplay })
        XCTAssertEqual(logged.entry.path, "/a.txt")
        XCTAssertEqual(logged.entry.status, 200)
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let f) = self { return f } else { return nil } }
}
