import XCTest
@testable import FolderServe

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    override func setUp() {
        defaults = UserDefaults(suiteName: "update-tests-\(UUID().uuidString)")!
        clock = Date(timeIntervalSince1970: 1_000_000)
    }

    private func release(_ tag: String) -> LatestRelease {
        LatestRelease(tag: tag, version: AppVersion(tag)!, url: URL(string: "https://github.com/fatihsenel/FolderServe/releases/tag/\(tag)")!)
    }

    private func checker(current: String = "0.1.0", latest: String = "v0.2.0", counter: Counter = Counter()) -> UpdateChecker {
        UpdateChecker(currentVersion: AppVersion(current), defaults: defaults, now: { [unowned self] in self.clock },
                      fetch: { [self] in counter.count += 1; return release(latest) })
    }

    final class Counter { var count = 0 }

    // MARK: versions

    func testVersionsCompareNumerically() {
        XCTAssertLessThan(AppVersion("0.1.0")!, AppVersion("0.2.0")!)
        XCTAssertLessThan(AppVersion("0.9.0")!, AppVersion("0.10.0")!, "not as text")
        XCTAssertLessThan(AppVersion("1.9.9")!, AppVersion("2.0")!)
        XCTAssertEqual(AppVersion("v1.2")!, AppVersion("1.2.0")!, "a leading v and missing zeros are ignored")
        XCTAssertLessThan(AppVersion("0.2.0-beta")!, AppVersion("0.2.0")!)
        XCTAssertGreaterThan(AppVersion("0.2.1-beta")!, AppVersion("0.2.0")!)
    }

    func testBadVersionsAreRejected() {
        for bad in ["", "v", "abc", "1.x", "1..2", "1.2.3.4.5"] { XCTAssertNil(AppVersion(bad), bad) }
    }

    // MARK: reading GitHub's answer

    private func json(tag: String = "v0.2.0", url: String = "https://github.com/fatihsenel/FolderServe/releases/tag/v0.2.0",
                      draft: Bool = false, prerelease: Bool = false) -> Data {
        Data(#"{"tag_name":"\#(tag)","html_url":"\#(url)","draft":\#(draft),"prerelease":\#(prerelease),"name":"x"}"#.utf8)
    }

    func testParsesTheLatestRelease() throws {
        let r = try UpdateChecker.parse(json())
        XCTAssertEqual(r.tag, "v0.2.0"); XCTAssertEqual(r.version, AppVersion("0.2.0"))
        XCTAssertEqual(r.url.absoluteString, "https://github.com/fatihsenel/FolderServe/releases/tag/v0.2.0")
    }

    func testRefusesDraftsPrereleasesAndOtherSites() {
        XCTAssertThrowsError(try UpdateChecker.parse(json(draft: true)))
        XCTAssertThrowsError(try UpdateChecker.parse(json(prerelease: true)))
        XCTAssertThrowsError(try UpdateChecker.parse(json(url: "https://evil.example.com/FolderServe")), "another host")
        XCTAssertThrowsError(try UpdateChecker.parse(json(url: "https://github.com/someone/else/releases/tag/v9")), "another project")
        XCTAssertThrowsError(try UpdateChecker.parse(json(url: "http://github.com/fatihsenel/FolderServe/releases")), "not https")
        XCTAssertThrowsError(try UpdateChecker.parse(json(url: "https://github.com.evil.com/fatihsenel/FolderServe/x")))
        XCTAssertThrowsError(try UpdateChecker.parse(json(tag: "nightly")), "not a version")
        XCTAssertThrowsError(try UpdateChecker.parse(Data("not json".utf8)))
        XCTAssertThrowsError(try UpdateChecker.parse(Data("{}".utf8)))
    }

    // MARK: checking

    func testNewerReleaseBecomesAvailableAndShowsABanner() async {
        let c = checker()
        await c.checkIfDue()
        XCTAssertEqual(c.state, .available(release("v0.2.0")))
        XCTAssertEqual(c.bannerRelease?.tag, "v0.2.0")
    }

    func testSameOrOlderReleaseIsUpToDate() async {
        let same = checker(current: "0.2.0"); await same.checkIfDue()
        XCTAssertEqual(same.state, .upToDate); XCTAssertNil(same.bannerRelease)
        defaults.removeObject(forKey: UpdateChecker.lastCheckKey)   // the two checkers share one store: make the second one due
        let newer = checker(current: "0.3.0"); await newer.checkIfDue()
        XCTAssertEqual(newer.state, .upToDate)
    }

    func testAutomaticChecksHappenOnceADay() async {
        let counter = Counter()
        let c = checker(counter: counter)
        await c.checkIfDue(); XCTAssertEqual(counter.count, 1)
        clock += 3_600
        await c.checkIfDue(); XCTAssertEqual(counter.count, 1, "an hour later: not due")
        clock += 24 * 3_600
        await c.checkIfDue(); XCTAssertEqual(counter.count, 2, "a day later: due")
    }

    func testTurnedOffMeansNoAutomaticCheck() async {
        defaults.set(false, forKey: UpdateChecker.enabledKey)
        let counter = Counter()
        let c = checker(counter: counter)
        await c.checkIfDue()
        XCTAssertEqual(counter.count, 0); XCTAssertEqual(c.state, .idle)
        await c.checkNow()
        XCTAssertEqual(counter.count, 1, "Check now still works")
    }

    func testDismissingHidesThatVersionUntilANewerOneAppears() async {
        let c = checker()
        await c.checkIfDue()
        c.dismissBanner()
        XCTAssertNil(c.bannerRelease)
        XCTAssertEqual(defaults.string(forKey: UpdateChecker.dismissedKey), "v0.2.0", "remembered across launches")
        let again = UpdateChecker(currentVersion: AppVersion("0.1.0"), defaults: defaults, now: { self.clock }, fetch: { self.release("v0.2.0") })
        clock += 2 * 24 * 3_600
        await again.checkIfDue()
        XCTAssertNil(again.bannerRelease, "the same release stays hidden after a relaunch")
        let newer = UpdateChecker(currentVersion: AppVersion("0.1.0"), defaults: defaults, now: { self.clock }, fetch: { self.release("v0.3.0") })
        clock += 2 * 24 * 3_600
        await newer.checkIfDue()
        XCTAssertEqual(newer.bannerRelease?.tag, "v0.3.0", "a newer release is shown again")
    }

    func testCheckNowShowsAClosedBannerAgain() async {
        let c = checker()
        await c.checkIfDue(); c.dismissBanner()
        await c.checkNow()
        XCTAssertNotNil(c.bannerRelease)
    }

    func testFailureIsReportedAndNotRetriedAtEveryLaunch() async {
        let counter = Counter()
        let c = UpdateChecker(currentVersion: AppVersion("0.1.0"), defaults: defaults, now: { self.clock },
                              fetch: { counter.count += 1; throw UpdateError.network("offline") })
        await c.checkIfDue()
        guard case .failed(let message) = c.state else { return XCTFail("\(c.state)") }
        XCTAssertTrue(message.contains("offline"))
        XCTAssertNil(c.bannerRelease, "a failed check never shows a banner")
        await c.checkIfDue()
        XCTAssertEqual(counter.count, 1)
    }

    func testStatusTexts() {
        let v = AppVersion("0.1.0")!
        XCTAssertEqual(UpdateChecker.State.upToDate.statusText(v), "You have the latest version (0.1.0).")
        XCTAssertTrue(UpdateChecker.State.available(release("v0.2.0")).statusText(v).contains("0.2.0"))
    }
}

private extension UpdateChecker.State {
    func statusText(_ current: AppVersion) -> String { UpdateStatusText.make(self, current: current) }
}
