import XCTest
@testable import FolderServeCore

final class MIMETypeTests: XCTestCase {
    func testCommonTypes() {
        XCTAssertEqual(MIMEType.forExtension("html"), "text/html; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("js"), "text/javascript; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("mjs"), "text/javascript; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("css"), "text/css; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("json"), "application/json; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("wasm"), "application/wasm")
        XCTAssertEqual(MIMEType.forExtension("svg"), "image/svg+xml")
        XCTAssertEqual(MIMEType.forExtension("png"), "image/png")
        XCTAssertEqual(MIMEType.forExtension("woff2"), "font/woff2")
        XCTAssertEqual(MIMEType.forExtension("mp4"), "video/mp4")
    }

    func testCaseInsensitive() {
        XCTAssertEqual(MIMEType.forExtension("HTML"), "text/html; charset=utf-8")
        XCTAssertEqual(MIMEType.forExtension("PNG"), "image/png")
    }

    func testUnknownFallsBack() {
        XCTAssertEqual(MIMEType.forExtension("zzz"), "application/octet-stream")
        XCTAssertEqual(MIMEType.forExtension(""), "application/octet-stream")
    }
}
