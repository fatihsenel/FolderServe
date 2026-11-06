import XCTest
@testable import FolderServeCore

final class HTTPRequestParserTests: XCTestCase {
    private func parse(_ s: String) -> HTTPParseResult {
        HTTPRequestParser.parse(Data(s.utf8))
    }

    func testParsesSimpleGET() {
        let raw = "GET /index.html HTTP/1.1\r\nHost: localhost\r\n\r\n"
        guard case let .request(req, consumed) = parse(raw) else { return XCTFail("expected request") }
        XCTAssertEqual(req.method, "GET")
        XCTAssertEqual(req.path, "/index.html")
        XCTAssertNil(req.rawQuery)
        XCTAssertEqual(req.headers["host"], "localhost")
        XCTAssertEqual(consumed, raw.utf8.count)
    }

    func testSplitsQueryAndFragment() {
        guard case let .request(req, _) = parse("GET /app.js?v=3#x HTTP/1.1\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(req.path, "/app.js")
        XCTAssertEqual(req.rawQuery, "v=3")
    }

    func testDecodesPercentAndUnicode() {
        guard case let .request(req, _) = parse("GET /my%20file%20%C3%BC.html HTTP/1.1\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(req.path, "/my file ü.html")
    }

    func testLowercasesHeaderNames() {
        guard case let .request(req, _) = parse("GET / HTTP/1.1\r\nAccept: text/html\r\nRANGE: bytes=0-1\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(req.headers["accept"], "text/html")
        XCTAssertEqual(req.headers["range"], "bytes=0-1")
    }

    func testNeedMoreWithoutBlankLine() {
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nHost: x\r\n"), .needMore)
    }

    func testMalformedRequestLine() {
        XCTAssertEqual(parse("GARBAGE\r\n\r\n"), .malformed)
    }

    func testRejectsHeadersOverMaxSize() {
        let big = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: 20_000)
        XCTAssertEqual(parse(big), .malformed)
    }

    func testConsumedCountsBytesOfFirstRequestOnly() {
        let first = "GET /a HTTP/1.1\r\n\r\n"
        guard case let .request(req, consumed) = parse(first + "GET /b HTTP/1.1\r\n\r\n") else { return XCTFail() }
        XCTAssertEqual(req.path, "/a")
        XCTAssertEqual(consumed, first.utf8.count)
    }

    func testRejectsInvalidPercentEncodingAndNUL() {
        XCTAssertEqual(parse("GET /%zz HTTP/1.1\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("GET /a%00b HTTP/1.1\r\n\r\n"), .malformed)
    }
}
