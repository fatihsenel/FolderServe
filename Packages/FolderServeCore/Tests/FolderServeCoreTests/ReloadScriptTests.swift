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

    private let allExist: (String) -> Bool = { _ in true }

    func testOnlyCSSChangesAreStyleReloads() {
        func kind(_ p: [String]) -> ReloadKind { ReloadKind.classify(paths: p, exists: allExist) }
        XCTAssertEqual(kind(["/site/a.css"]), .styles)
        XCTAssertEqual(kind(["/site/a.css", "/site/deep/B.CSS"]), .styles)
        XCTAssertEqual(kind(["/site/a.css", "/site/index.html"]), .full)
        XCTAssertEqual(kind(["/site/app.js"]), .full)
        XCTAssertEqual(kind(["/site/a.css.map"]), .styles)   // a source map next to a stylesheet: nothing to reload
        XCTAssertEqual(kind(["/site/a.css", "/site/a.css.map"]), .styles)
        XCTAssertEqual(kind(["/site/styles.css.ts"]), .full)
        XCTAssertEqual(kind(["/site/a.cssx"]), .full)
        XCTAssertEqual(kind(["/site/a.scss"]), .full)
        XCTAssertEqual(kind(["/site/folder"]), .full)
        XCTAssertEqual(kind([]), .full)
    }

    func testEditorTemporaryFilesAreIgnoredOnceTheyAreGone() {
        // An atomic save reports the original and a temporary file that is renamed away, with a name that depends on the editor and macOS.
        let gone: Set<String> = ["/site/.dat.nosync1234.AbCdEf", "/site/style.css.sb-d1226737-7FLQ8o", "/site/4913", "/site/.style.css.swp"]
        let exists: (String) -> Bool = { !gone.contains($0) }
        func kind(_ p: [String]) -> ReloadKind { ReloadKind.classify(paths: p, exists: exists) }
        XCTAssertEqual(kind(["/site/style.css", "/site/.dat.nosync1234.AbCdEf"]), .styles)
        XCTAssertEqual(kind(["/site/style.css", "/site/style.css.sb-d1226737-7FLQ8o"]), .styles)
        XCTAssertEqual(kind(["/site/style.css", "/site/4913"]), .styles)
        XCTAssertEqual(kind(["/site/style.css", "/site/.style.css.swp"]), .styles)
        // A temporary file alone, or a deleted stylesheet alone, is not a style change we can apply: reload.
        XCTAssertEqual(kind(["/site/.dat.nosync1234.AbCdEf"]), .full)
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/style.css"], exists: { _ in false }), .full)
        // Another page or script in the same burst still reloads, even if it was deleted.
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/style.css", "/site/index.html.sb-1234"], exists: { $0.hasSuffix(".css") }), .styles)   // vanished temp file: ignored
        XCTAssertEqual(kind(["/site/style.css", "/site/index.html.sb-1234"]), .full)   // ...but a file that is still there is a real change
        XCTAssertEqual(ReloadKind.classify(paths: ["/site/style.css", "/site/index.html"], exists: { $0.hasSuffix(".css") }), .full)
        XCTAssertEqual(kind(["/site/style.css", "/site/app.js"]), .full)
    }

    func testMessagesMatchWhatTheScriptExpects() {
        XCTAssertEqual(ReloadKind.styles.message, "data: css\n\n")
        XCTAssertEqual(ReloadKind.full.message, "data: reload\n\n")
        XCTAssertTrue(ReloadScript.source.contains("e.data!=='css'"))
    }
}
