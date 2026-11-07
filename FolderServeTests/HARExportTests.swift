import XCTest
import FolderServeCore
@testable import FolderServe

final class HARExportTests: XCTestCase {
    private func line(_ method: String, _ url: String, status: Int = 200, at seconds: TimeInterval = 0, ms: Int? = 12,
                      configure: (inout RequestLogEntry) -> Void = { _ in }) -> LogLine {
        var e = RequestLogEntry(date: Date(timeIntervalSince1970: 1_700_000_000 + seconds), method: method, path: "/p", status: status, bytes: 5)
        e.url = url
        e.durationMs = ms
        configure(&e)
        return LogLine(serverID: UUID(), entry: e)
    }

    private func entries(_ lines: [LogLine], bodies: [UUID: HARBody] = [:]) throws -> [[String: Any]] {
        let data = try HARExport.make(lines: lines, bodies: bodies, appVersion: "9.9")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let log = try XCTUnwrap(root["log"] as? [String: Any])
        XCTAssertEqual(log["version"] as? String, "1.2")
        XCTAssertEqual((log["creator"] as? [String: Any])?["name"] as? String, "FolderServe")
        XCTAssertEqual((log["creator"] as? [String: Any])?["version"] as? String, "9.9")
        return try XCTUnwrap(log["entries"] as? [[String: Any]])
    }

    func testEntriesAreWrittenOldestFirstWithTimes() throws {
        let newer = line("GET", "http://127.0.0.1:8080/b", at: 5)
        let older = line("GET", "http://127.0.0.1:8080/a", at: 1, ms: 250)
        let out = try entries([newer, older])
        XCTAssertEqual(out.compactMap { ($0["request"] as? [String: Any])?["url"] as? String },
                       ["http://127.0.0.1:8080/a", "http://127.0.0.1:8080/b"])
        XCTAssertEqual(out[0]["time"] as? Int, 250)
        XCTAssertEqual((out[0]["timings"] as? [String: Any])?["wait"] as? Int, 250)
        XCTAssertEqual(out[0]["startedDateTime"] as? String, "2023-11-14T22:13:21.000Z")
    }

    func testRequestAndResponseDetails() throws {
        let l = line("POST", "http://127.0.0.1:8080/uiapi/Login?next=%2Fhome&x=1", status: 302) { e in
            e.requestHeaders = [HTTPHeaderField(name: "Content-Type", value: "application/json")]
            e.requestBody = Data(#"{"a":1}"#.utf8)
            e.responseHeaders = [HTTPHeaderField(name: "Location", value: "/home"), HTTPHeaderField(name: "Content-Type", value: "text/html")]
        }
        let e = try XCTUnwrap(entries([l]).first)
        let req = try XCTUnwrap(e["request"] as? [String: Any])
        XCTAssertEqual(req["method"] as? String, "POST")
        XCTAssertEqual(req["httpVersion"] as? String, "HTTP/1.1")
        XCTAssertEqual(req["bodySize"] as? Int, 7)
        let query = try XCTUnwrap(req["queryString"] as? [[String: String]])
        XCTAssertEqual(query, [["name": "next", "value": "/home"], ["name": "x", "value": "1"]])
        let post = try XCTUnwrap(req["postData"] as? [String: Any])
        XCTAssertEqual(post["mimeType"] as? String, "application/json")
        XCTAssertEqual(post["text"] as? String, #"{"a":1}"#)
        let res = try XCTUnwrap(e["response"] as? [String: Any])
        XCTAssertEqual(res["status"] as? Int, 302)
        XCTAssertEqual(res["statusText"] as? String, HTTPStatus.reason(302))
        XCTAssertEqual(res["redirectURL"] as? String, "/home")
        XCTAssertEqual((res["headers"] as? [[String: String]])?.first, ["name": "Location", "value": "/home"])
    }

    func testResponseBodiesAreTextBase64OrMarkedIncomplete() throws {
        let text = line("GET", "http://127.0.0.1:8080/a.json") { $0.responseHeaders = [HTTPHeaderField(name: "content-type", value: "application/json")] }
        let image = line("GET", "http://127.0.0.1:8080/a.png") { $0.responseHeaders = [HTTPHeaderField(name: "content-type", value: "image/png")] }
        let cut = line("GET", "http://127.0.0.1:8080/big.json") { $0.responseHeaders = [HTTPHeaderField(name: "content-type", value: "application/json")] }
        let none = line("GET", "http://127.0.0.1:8080/none")
        let png = Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff])
        let bodies = [text.id: HARBody(data: Data(#"{"ok":true}"#.utf8), complete: true),
                      image.id: HARBody(data: png, complete: true),
                      cut.id: HARBody(data: Data("[1,2".utf8), complete: false)]
        let out = try entries([text, image, cut, none].enumerated().map { i, l in
            var l = l; l.entry.date = Date(timeIntervalSince1970: 1_700_000_000 + Double(i)); return l }, bodies: bodies)
        func content(_ i: Int) -> [String: Any] { (out[i]["response"] as! [String: Any])["content"] as! [String: Any] }
        XCTAssertEqual(content(0)["text"] as? String, #"{"ok":true}"#)
        XCTAssertNil(content(0)["encoding"])
        XCTAssertEqual(content(1)["text"] as? String, png.base64EncodedString())
        XCTAssertEqual(content(1)["encoding"] as? String, "base64")
        XCTAssertEqual(content(2)["comment"] as? String, "Only the start of the response body was captured.")
        XCTAssertNil(content(3)["text"], "no body known: size only")
        XCTAssertEqual(content(3)["size"] as? Int, 5)
    }

    func testBinaryRequestBodyIsLeftOutWithANote() throws {
        let l = line("PUT", "http://127.0.0.1:8080/up") { $0.requestBody = Data([0xff, 0xfe, 0x00]) }
        let post = try XCTUnwrap(((try entries([l]).first)?["request"] as? [String: Any])?["postData"] as? [String: Any])
        XCTAssertEqual(post["text"] as? String, "")
        XCTAssertEqual(post["comment"] as? String, "The request body is binary and is not included.")
    }

    func testAnEmptyListIsStillAValidHAR() throws {
        XCTAssertEqual(try entries([]).count, 0)
    }
}
