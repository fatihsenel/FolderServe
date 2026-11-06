import XCTest
@testable import FolderServeCore

final class DirectoryListingTests: XCTestCase {
    var dir: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: dir) }

    private func touch(_ name: String) throws {
        try "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func mkdir(_ name: String) throws {
        try fm.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: false)
    }

    func testFoldersFirstThenFilesAlphabetical() throws {
        try touch("b.txt"); try touch("a.txt"); try mkdir("zdir"); try mkdir("adir")
        let html = DirectoryListing.html(directory: dir, urlPath: "/x/", showDotfiles: false)
        let order = ["adir/", "zdir/", "a.txt", "b.txt"].map { html.range(of: "href=\"\($0)\"")!.lowerBound }
        XCTAssertEqual(order, order.sorted())
    }

    func testHidesDotfilesUnlessEnabled() throws {
        try touch(".env"); try touch("a.txt")
        XCTAssertFalse(DirectoryListing.html(directory: dir, urlPath: "/", showDotfiles: false).contains(".env"))
        XCTAssertTrue(DirectoryListing.html(directory: dir, urlPath: "/", showDotfiles: true).contains(".env"))
    }

    func testEscapesHTMLInNames() throws {
        try touch("<b>x&y.txt")
        let html = DirectoryListing.html(directory: dir, urlPath: "/", showDotfiles: false)
        XCTAssertFalse(html.contains("<b>x"))
        XCTAssertTrue(html.contains("&lt;b&gt;x&amp;y.txt"))
    }

    func testLinksArePercentEncoded() throws {
        try touch("my file ü.html")
        let html = DirectoryListing.html(directory: dir, urlPath: "/", showDotfiles: false)
        XCTAssertTrue(html.contains("href=\"my%20file%20%C3%BC.html\""))
    }

    func testParentLinkOnlyBelowRoot() throws {
        XCTAssertFalse(DirectoryListing.html(directory: dir, urlPath: "/", showDotfiles: false).contains("href=\"../\""))
        XCTAssertTrue(DirectoryListing.html(directory: dir, urlPath: "/sub/", showDotfiles: false).contains("href=\"../\""))
    }

    func testErrorPageContainsStatusAndEscapedMessage() {
        let html = ErrorPage.html(status: 404, message: "<b>nope</b>")
        XCTAssertTrue(html.contains("404"))
        XCTAssertTrue(html.contains("&lt;b&gt;nope&lt;/b&gt;"))
        XCTAssertFalse(html.contains("<b>nope"))
    }
}
