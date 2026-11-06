import XCTest
@testable import FolderServeCore

final class RangeHeaderTests: XCTestCase {
    func testExplicitRange() {
        XCTAssertEqual(RangeHeader.parse("bytes=0-99", fileSize: 1000), .partial(0...99))
    }
    func testOpenEnded() {
        XCTAssertEqual(RangeHeader.parse("bytes=100-", fileSize: 1000), .partial(100...999))
    }
    func testSuffix() {
        XCTAssertEqual(RangeHeader.parse("bytes=-500", fileSize: 1000), .partial(500...999))
        XCTAssertEqual(RangeHeader.parse("bytes=-5000", fileSize: 1000), .partial(0...999))
    }
    func testEndClampedToSize() {
        XCTAssertEqual(RangeHeader.parse("bytes=900-5000", fileSize: 1000), .partial(900...999))
    }
    func testStartBeyondEOFIsUnsatisfiable() {
        XCTAssertEqual(RangeHeader.parse("bytes=9999-", fileSize: 100), .unsatisfiable)
    }
    func testGarbageNilAndMultiRangeAreIgnored() {
        XCTAssertEqual(RangeHeader.parse(nil, fileSize: 100), RangeResult.none)
        XCTAssertEqual(RangeHeader.parse("lines=1-2", fileSize: 100), RangeResult.none)
        XCTAssertEqual(RangeHeader.parse("bytes=abc", fileSize: 100), RangeResult.none)
        XCTAssertEqual(RangeHeader.parse("bytes=0-1,5-6", fileSize: 100), RangeResult.none)
    }
    func testZeroByteFileWithRangeIsUnsatisfiable() {
        XCTAssertEqual(RangeHeader.parse("bytes=0-10", fileSize: 0), .unsatisfiable)
    }
    func testReversedRangeIsUnsatisfiable() {
        XCTAssertEqual(RangeHeader.parse("bytes=50-10", fileSize: 100), .unsatisfiable)
    }
}
