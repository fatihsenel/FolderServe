import XCTest
@testable import FolderServeCore

final class SmokeTests: XCTestCase {
    func testVersionIsNotEmpty() {
        XCTAssertFalse(FolderServeCore.version.isEmpty)
    }
}
