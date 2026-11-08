import XCTest
@testable import FolderServeCore

final class PageLoadAnalysisTests: XCTestCase {
    private let origin = "http://127.0.0.1:8080"

    /// `end`: seconds after the start of the test at which the answer was sent; `ms`: how long it took.
    private func entry(_ path: String, end: TimeInterval, ms: Int = 10, category: RequestCategory = .js,
                       referer: String? = nil, status: Int = 200, bytes: Int64 = 100) -> RequestLogEntry {
        var e = RequestLogEntry(date: Date(timeIntervalSince1970: 1_000 + end), method: "GET", path: path, status: status,
                                bytes: bytes, category: category)
        e.url = origin + path
        e.durationMs = ms
        if let referer { e.requestHeaders = [HTTPHeaderField(name: "referer", value: referer)] }
        return e
    }

    private var pageURL: String { origin + "/" }

    func testPageAndItsFilesAreGroupedWithATotal() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let js = entry("/app.js", end: 0.30, ms: 200, referer: pageURL)
        let css = entry("/app.css", end: 0.40, ms: 300, category: .css, referer: pageURL)
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, js, css]))
        XCTAssertEqual(load.files.map(\.path), ["/app.js", "/app.css"])
        XCTAssertEqual(load.totalMs, 400, "page started at 0.00 s, last file finished at 0.40 s")
        XCTAssertEqual(load.slowest?.path, "/app.css")
        XCTAssertEqual(load.bytes, 300)
        XCTAssertEqual(load.failed, 0)
    }

    func testFilesLoadedByAStylesheetBelongToThePage() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let css = entry("/app.css", end: 0.20, ms: 100, category: .css, referer: pageURL)
        let font = entry("/f.woff2", end: 0.35, ms: 100, category: .font, referer: origin + "/app.css")
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, css, font]))
        XCTAssertEqual(load.files.count, 2)
    }

    func testRequestsFromOtherPagesAreLeftOut() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let mine = entry("/app.js", end: 0.2, referer: pageURL)
        let other = entry("/x.js", end: 0.25, referer: origin + "/other.html")
        let detached = entry("/app.js", end: 0.3)   // DevTools re-fetch: no referer
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, mine, other, detached]))
        XCTAssertEqual(load.files.map(\.id), [mine.id])
    }

    func testLoadStopsWhenItGoesQuiet() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let early = entry("/app.js", end: 0.3, referer: pageURL)
        let poll = entry("/api/poll", end: 30, category: .fetch, referer: pageURL)   // 30 s later: not part of the load
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, early, poll]))
        XCTAssertEqual(load.files.count, 1)
        XCTAssertLessThan(load.totalMs, 1000)
    }

    func testAReloadStartsANewLoad() throws {
        let first = entry("/", end: 0.05, ms: 50, category: .doc)
        let a = entry("/app.js", end: 0.2, referer: pageURL)
        let second = entry("/", end: 1.0, ms: 50, category: .doc)
        let b = entry("/app.js", end: 1.2, referer: pageURL)
        let log = [first, a, second, b]
        XCTAssertEqual(PageLoadAnalysis.analyze(first, in: log)?.files.map(\.id), [a.id])
        XCTAssertEqual(PageLoadAnalysis.analyze(second, in: log)?.files.map(\.id), [b.id])
    }

    func testFollowingALinkIsNotPartOfThePage() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let link = entry("/about.html", end: 0.5, ms: 20, category: .doc, referer: pageURL)
        let aboutJS = entry("/about.js", end: 0.6, referer: origin + "/about.html")
        let mine = entry("/app.js", end: 0.2, referer: pageURL)
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, mine, link, aboutJS]))
        XCTAssertEqual(load.files.map(\.id), [mine.id])
    }

    func testFailedFilesAreCounted() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let missing = entry("/gone.png", end: 0.2, category: .img, referer: pageURL, status: 404)
        let load = try XCTUnwrap(PageLoadAnalysis.analyze(page, in: [page, missing]))
        XCTAssertEqual(load.failed, 1)
    }

    func testNothingToReportWithoutFilesOrForNonPages() {
        let page = entry("/", end: 0.05, category: .doc)
        XCTAssertNil(PageLoadAnalysis.analyze(page, in: [page]))
        let js = entry("/app.js", end: 0.2, referer: pageURL)
        XCTAssertNil(PageLoadAnalysis.analyze(js, in: [page, js]), "only documents have a page load")
    }

    func testFragmentInTheRefererIsIgnored() throws {
        let page = entry("/", end: 0.05, ms: 50, category: .doc)
        let js = entry("/app.js", end: 0.2, referer: pageURL + "#/home")
        XCTAssertEqual(PageLoadAnalysis.analyze(page, in: [page, js])?.files.count, 1)
    }
}
