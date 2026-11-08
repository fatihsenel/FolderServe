import XCTest
@testable import FolderServeCore

final class ReloadScriptTests: XCTestCase {
    private let tag = "<script>\(ReloadScript.source)</script>"

    private func inject(_ s: String) -> String {
        String(decoding: ReloadScript.inject(into: Data(s.utf8)), as: UTF8.self)
    }

    func testInjectsBeforeClosingBody() {
        XCTAssertEqual(inject("<html><body>hi</body></html>"), "<html><body>hi\(tag)</body></html>")
    }

    func testInjectsBeforeUppercaseClosingBody() {
        XCTAssertEqual(inject("<BODY>hi</BODY>"), "<BODY>hi\(tag)</BODY>")
    }

    func testAppendsWhenNoClosingBody() {
        XCTAssertEqual(inject("<h1>fragment</h1>"), "<h1>fragment</h1>\(tag)")
    }

    func testUsesLastClosingBody() {
        XCTAssertEqual(inject("<script>'</body>'</script></body>"), "<script>'</body>'</script>\(tag)</body>")
    }

    func testNonUTF8BytesSurvive() {
        let input = Data([0xFF, 0xFE, 0x41]) + Data("</body>".utf8)
        let out = ReloadScript.inject(into: input)
        XCTAssertEqual(Array(out.prefix(3)), [0xFF, 0xFE, 0x41])
        XCTAssertTrue(String(decoding: out, as: UTF8.self).contains("EventSource"))
    }

    func testOnlyCSSChangesAreStyleReloads() {
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/a.css"]), .styles)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/a.css", "/site/deep/B.CSS"]), .styles)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/a.css", "/site/index.html"]), .full)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/app.js"]), .full)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/a.css.map"]), .full)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/a.css~"]), .full)   // an editor's temporary file: be safe and reload
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/folder"]), .full)
        XCTAssertEqual(ReloadKind.classify(paths: []), .full)
    }

    func testMessagesMatchWhatTheScriptExpects() {
        XCTAssertEqual(ReloadKind.styles.message, "data: css\n\n")
        XCTAssertEqual(ReloadKind.full.message, "data: reload\n\n")
        XCTAssertTrue(ReloadScript.source.contains("e.data!=='css'"))
    }
}
