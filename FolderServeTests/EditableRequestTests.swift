import XCTest
import FolderServeCore
@testable import FolderServe

final class EditableRequestTests: XCTestCase {
    private let base = URL(string: "http://127.0.0.1:8080")!

    private func entry(method: String = "POST", path: String = "/api/users?page=2", headers: [(String, String)] = [],
                       body: String? = nil) -> RequestLogEntry {
        var e = RequestLogEntry(date: Date(), method: method, path: path, status: 200, bytes: 0, category: .fetch)
        e.url = "http://127.0.0.1:9999" + path
        e.requestHeaders = headers.map { HTTPHeaderField(name: $0.0, value: $0.1) }
        e.requestBody = body.map { Data($0.utf8) }
        return e
    }

    private func request(_ r: EditableRequest) throws -> URLRequest { try r.urlRequest(base: base).get() }

    func testStartsFromTheLoggedRequestWithoutClientManagedHeaders() {
        let r = EditableRequest(entry: entry(headers: [("Host", "x"), ("Content-Length", "5"), ("Accept", "application/json"),
                                                       ("X-FolderServe-Replay", "1"), (":authority", "y")], body: #"{"a":1}"#))
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.target, "/api/users?page=2")
        XCTAssertEqual(r.headers.map(\.name), ["Accept"])
        XCTAssertEqual(r.body, #"{"a":1}"#)
        XCTAssertNil(r.bodyNote)
    }

    func testUnchangedEditSendsTheSameRequestToTheCurrentServer() throws {
        let r = try request(EditableRequest(entry: entry(headers: [("Accept", "application/json")], body: "hello")))
        XCTAssertEqual(r.url?.absoluteString, "http://127.0.0.1:8080/api/users?page=2")
        XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(r.value(forHTTPHeaderField: RequestLogEntry.replayHeader), "1")
        XCTAssertEqual(r.httpBody, Data("hello".utf8))
    }

    func testEditsToMethodTargetHeadersAndBodyAreSent() throws {
        var e = EditableRequest(entry: entry(headers: [("Authorization", "Bearer old"), ("Accept", "*/*")], body: "old"))
        e.method = "put"
        e.target = "/api/users/7?force=true"
        e.headers[0].value = "Bearer new"
        e.headers.remove(at: 1)
        e.headers.append(.init(name: "X-Debug", value: "1"))
        e.body = #"{"name":"Ada"}"#
        let r = try request(e)
        XCTAssertEqual(r.httpMethod, "PUT")
        XCTAssertEqual(r.url?.absoluteString, "http://127.0.0.1:8080/api/users/7?force=true")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer new")
        XCTAssertNil(r.value(forHTTPHeaderField: "Accept"))
        XCTAssertEqual(r.value(forHTTPHeaderField: "X-Debug"), "1")
        XCTAssertEqual(r.httpBody, Data(#"{"name":"Ada"}"#.utf8))
    }

    func testSwitchingToGETDropsTheBody() throws {
        var e = EditableRequest(entry: entry(body: "payload"))
        e.method = "GET"
        XCTAssertNil(try request(e).httpBody)
        XCTAssertFalse(e.hasBody)
    }

    func testTargetMustBeAPathOnTheServer() {
        for bad in ["api/users", "//evil.example/x", "http://evil.example/x", "", "/a\nb", "/a b\r\nHost: x"] {
            var e = EditableRequest(entry: entry())
            e.target = bad
            XCTAssertEqual(e.urlRequest(base: base).failure, .badTarget, bad)
        }
    }

    func testHeaderValidation() {
        func problem(_ name: String, _ value: String) -> EditableRequest.Problem? {
            var e = EditableRequest(entry: entry())
            e.headers = [.init(name: name, value: value)]
            return e.urlRequest(base: base).failure
        }
        XCTAssertEqual(problem("Bad Name", "x"), .badHeaderName("Bad Name"))
        XCTAssertEqual(problem("X:Y", "x"), .badHeaderName("X:Y"))
        XCTAssertEqual(problem("", "orphan value"), .badHeaderName(""))
        XCTAssertEqual(problem("Host", "evil.example"), .reservedHeader("Host"))
        XCTAssertEqual(problem("content-length", "1"), .reservedHeader("content-length"))
        XCTAssertEqual(problem("X-Replay-Marker", "a\r\nInjected: 1"), .badHeaderValue("X-Replay-Marker"))   // "\r\n" is one Character
        XCTAssertEqual(problem("X-A", "a\nb"), .badHeaderValue("X-A"))
        XCTAssertNil(problem("X-Fine", "tab\tis ok"))
        XCTAssertNil(problem("", ""))       // an empty row is ignored
    }

    func testMethodMustBeOneOfTheOffered() {
        var e = EditableRequest(entry: entry())
        e.method = "TRACE"
        XCTAssertEqual(e.urlRequest(base: base).failure, .badMethod("TRACE"))
    }

    func testNoServerMeansNothingToSendTo() {
        XCTAssertEqual(EditableRequest(entry: entry()).urlRequest(base: nil).failure, .notRunning)
    }

    func testBinaryBodyIsKeptUnlessReplacedByTypedText() throws {
        var e = entry()
        e.requestBody = Data([0xFF, 0xFE, 0x00, 0x01])
        var r = EditableRequest(entry: e)
        XCTAssertEqual(r.body, "")
        XCTAssertNotNil(r.bodyNote)
        XCTAssertEqual(try request(r).httpBody, Data([0xFF, 0xFE, 0x00, 0x01]))
        r.body = "text instead"
        XCTAssertEqual(try request(r).httpBody, Data("text instead".utf8))
    }

    func testCutOffBodyStartsEmptyWithANote() throws {
        var e = entry(body: "partial")
        e.requestBodyTruncated = true
        let r = EditableRequest(entry: e)
        XCTAssertEqual(r.body, "")
        XCTAssertNotNil(r.bodyNote)
        XCTAssertNil(try request(r).httpBody)
    }

    func testDroppedBodyStartsEmptyWithANote() {
        var e = entry()
        e.bodiesDropped = true
        XCTAssertNotNil(EditableRequest(entry: e).bodyNote)
    }

    func testRepeatedHeaderNamesAreAllSent() throws {
        var e = EditableRequest(entry: entry())
        e.headers = [.init(name: "X-Tag", value: "a"), .init(name: "X-Tag", value: "b")]
        XCTAssertEqual(try request(e).value(forHTTPHeaderField: "X-Tag"), "a,b")
    }
}

extension EditableRequestTests {
    /// End to end: the edited address and header reach the server, which logs them as a replay.
    @MainActor func testEditedRequestReachesTheServerWithTheChanges() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("er-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "a".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "bee".write(to: dir.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        var url: URL?
        for _ in 0..<250 { url = manager.url(for: id); if url != nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        let base = try XCTUnwrap(url)

        var original = RequestLogEntry(method: "GET", path: "/a.txt", status: 200, bytes: 1)
        original.url = "http://127.0.0.1:1/a.txt"
        var edit = EditableRequest(entry: original)
        edit.target = "/b.txt"
        edit.headers.append(.init(name: "X-Debug", value: "on"))
        let request = try edit.urlRequest(base: base).get()
        let status = try await RequestReplay.send(request).get()
        XCTAssertEqual(status, 200)

        for _ in 0..<250 where !manager.log.contains(where: { $0.entry.isReplay }) { try await Task.sleep(nanoseconds: 20_000_000) }
        let logged = try XCTUnwrap(manager.log.first { $0.entry.isReplay })
        XCTAssertEqual(logged.entry.path, "/b.txt")
        XCTAssertEqual(logged.entry.requestHeaders.first { $0.name.lowercased() == "x-debug" }?.value, "on")
    }
}

private extension Result {
    var failure: Failure? { if case .failure(let e) = self { return e } else { return nil } }
}
