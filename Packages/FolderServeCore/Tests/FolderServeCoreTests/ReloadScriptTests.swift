import XCTest
@testable import FolderServeCore

final class ReloadScriptTests: XCTestCase {
    private let tag = "<script>new EventSource('/__reload').onmessage=()=>location.reload()</script>"

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
}
