import XCTest
@testable import FolderServeCore

final class ChunkedBodyTests: XCTestCase {
    private func decode(_ s: String, max: Int = 1_000) -> ChunkedBody.Result { ChunkedBody.decode(Data(s.utf8), maxSize: max) }

    func testJoinsChunks() {
        XCTAssertEqual(decode("5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n"),
                       .complete(body: Data("hello world".utf8), consumed: 26))
    }

    func testEmptyBody() {
        XCTAssertEqual(decode("0\r\n\r\n"), .complete(body: Data(), consumed: 5))
    }

    func testHexSizesAreCaseInsensitive() {
        let body = String(repeating: "x", count: 26)
        XCTAssertEqual(decode("1A\r\n\(body)\r\n0\r\n\r\n"), .complete(body: Data(body.utf8), consumed: 4 + 26 + 2 + 5))
        XCTAssertEqual(decode("1a\r\n\(body)\r\n0\r\n\r\n"), .complete(body: Data(body.utf8), consumed: 4 + 26 + 2 + 5))
    }

    func testExtensionsAndTrailersAreIgnored() {
        guard case .complete(let body, let consumed) = decode("2;ext=1\r\nhi\r\n0\r\nTrailer: x\r\nOther: y\r\n\r\nNEXT") else { return XCTFail() }
        XCTAssertEqual(String(decoding: body, as: UTF8.self), "hi")
        XCTAssertEqual(consumed, "2;ext=1\r\nhi\r\n0\r\nTrailer: x\r\nOther: y\r\n\r\n".utf8.count, "bytes after the body are left alone")
    }

    func testIncompleteInputNeedsMore() {
        for partial in ["", "5", "5\r\nhel", "5\r\nhello", "5\r\nhello\r\n", "5\r\nhello\r\n0\r\n", "5\r\nhello\r\n0\r\nTrailer: x\r\n"] {
            XCTAssertEqual(decode(partial), .needMore, partial)
        }
    }

    func testMalformedInput() {
        XCTAssertEqual(decode("zz\r\nhello\r\n0\r\n\r\n"), .malformed, "size is not hex")
        XCTAssertEqual(decode("\r\nhello"), .malformed, "empty size")
        XCTAssertEqual(decode("5\r\nhelloXX0\r\n\r\n"), .malformed, "chunk not followed by CRLF")
        XCTAssertEqual(decode("123456789\r\n"), .malformed, "absurd size")
        XCTAssertEqual(ChunkedBody.decode(Data(repeating: 0x41, count: 2_000), maxSize: 10), .malformed, "no size line in a long run")
    }

    func testTooLarge() {
        XCTAssertEqual(decode("5\r\nhello\r\n5\r\nworld\r\n0\r\n\r\n", max: 8), .tooLarge)
        XCTAssertEqual(decode("ffffff\r\n", max: 100), .tooLarge, "refused from the size line, before the data arrives")
    }
}
