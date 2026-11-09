import XCTest
@testable import FolderServe

final class StatusFilterTests: XCTestCase {
    func testFamiliesCoverTheirRangesExactly() {
        XCTAssertTrue(StatusFilter.success.matches(status: 200))
        XCTAssertTrue(StatusFilter.success.matches(status: 206))
        XCTAssertTrue(StatusFilter.success.matches(status: 299))
        XCTAssertFalse(StatusFilter.success.matches(status: 199))
        XCTAssertFalse(StatusFilter.success.matches(status: 300))

        XCTAssertTrue(StatusFilter.redirect.matches(status: 301))
        XCTAssertTrue(StatusFilter.redirect.matches(status: 304))
        XCTAssertTrue(StatusFilter.redirect.matches(status: 399))
        XCTAssertFalse(StatusFilter.redirect.matches(status: 299))
        XCTAssertFalse(StatusFilter.redirect.matches(status: 400))

        XCTAssertFalse(StatusFilter.errors.matches(status: 399))
        XCTAssertTrue(StatusFilter.errors.matches(status: 400))
        XCTAssertTrue(StatusFilter.errors.matches(status: 404))
        XCTAssertTrue(StatusFilter.errors.matches(status: 502))
    }

    func testAnyMatchesEverything() {
        for status in [0, 101, 200, 304, 404, 500, 999] { XCTAssertTrue(StatusFilter.any.matches(status: status)) }
    }

    func testEveryFilterHasALabelAndDetail() {
        for f in StatusFilter.allCases {
            XCTAssertFalse(f.label.isEmpty)
            XCTAssertFalse(f.detail.isEmpty)
        }
        XCTAssertEqual(StatusFilter.allCases.first, .any)
    }
}
