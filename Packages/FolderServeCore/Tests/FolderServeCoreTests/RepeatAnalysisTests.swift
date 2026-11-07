import XCTest
@testable import FolderServeCore

final class RepeatAnalysisTests: XCTestCase {
    private func entry(_ path: String = "/main.js", at t: TimeInterval = 0, method: String = "GET", _ headers: [String: String] = [:]) -> RequestLogEntry {
        var e = RequestLogEntry(date: Date(timeIntervalSince1970: 1_000 + t), method: method, path: path, status: 200, bytes: 10)
        e.url = "http://127.0.0.1:8080" + path
        e.requestHeaders = HTTPHeaderField.sorted(headers)
        return e
    }

    func testFirstRequestIsNotARepeat() {
        XCTAssertNil(RepeatAnalysis.analyze(entry(), earlier: [entry("/other.js")]))
        XCTAssertNil(RepeatAnalysis.analyze(entry(), earlier: []))
    }

    func testIdenticalHeadersSaidSo() throws {
        let h = ["sec-fetch-dest": "script", "sec-fetch-mode": "cors"]
        let info = try XCTUnwrap(RepeatAnalysis.analyze(entry(at: 0.02, h), earlier: [entry(at: 0, h)]))
        XCTAssertEqual(info.gapMs, 20); XCTAssertEqual(info.count, 2); XCTAssertTrue(info.differences.isEmpty)
        XCTAssertTrue(info.headline.contains("identical headers"))
    }

    func testPreloadThenImportIsRecognisedByFetchDest() throws {
        let info = try XCTUnwrap(RepeatAnalysis.analyze(
            entry(at: 0.05, ["sec-fetch-dest": "script", "sec-fetch-mode": "cors"]),
            earlier: [entry(at: 0, ["sec-fetch-dest": "empty", "sec-fetch-mode": "cors"])]))
        XCTAssertEqual(info.differences.map(\.header), ["sec-fetch-dest"])
        XCTAssertTrue(info.headline.contains("empty → script"))
    }

    func testCacheBypassedWithinAMomentPointsAtDisableCache() throws {
        let info = try XCTUnwrap(RepeatAnalysis.analyze(entry(at: 0.1, ["cache-control": "no-cache"]), earlier: [entry(at: 0, ["cache-control": "no-cache"])]))
        XCTAssertTrue(info.headline.contains("Disable cache"))
    }

    func testLongGapMeansASeparatePageLoad() throws {
        let info = try XCTUnwrap(RepeatAnalysis.analyze(entry(at: 12), earlier: [entry(at: 0)]))
        XCTAssertTrue(info.headline.contains("separate page loads"), info.headline)
    }

    func testPrefetchPurposeWins() throws {
        let info = try XCTUnwrap(RepeatAnalysis.analyze(entry(at: 0.1), earlier: [entry(at: 0, ["sec-purpose": "prefetch"])]))
        XCTAssertTrue(info.headline.contains("prefetch"))
    }

    func testUsesTheClosestEarlierOneAndCountsAll() throws {
        let list = [entry(at: 0), entry(at: 1), entry(at: 2)]
        let info = try XCTUnwrap(RepeatAnalysis.analyze(entry(at: 2.5), earlier: list))
        XCTAssertEqual(info.count, 4); XCTAssertEqual(info.gapMs, 500)
    }

    func testDifferentMethodOrQueryIsNotARepeat() {
        var q = entry(); q.url += "?v=2"
        XCTAssertNil(RepeatAnalysis.analyze(q, earlier: [entry()]))
        XCTAssertNil(RepeatAnalysis.analyze(entry(method: "POST"), earlier: [entry()]))
    }
}
