import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class MenuBarActionsTests: XCTestCase {
    private func entry(_ status: Int, path: String = "/app.js", headers: [HTTPHeaderField] = []) -> RequestLogEntry {
        var e = RequestLogEntry(method: "GET", path: path, status: status, bytes: 0)
        e.requestHeaders = headers
        return e
    }

    private func manager() -> (ServerManager, UUID) {
        let m = ServerManager(store: InMemoryStore(), defaultStartPort: 40_000, minSearchDuration: 0)
        let e = ServerEntry(id: UUID(), bookmark: Data(), folderPath: "/tmp/site", preferredPort: nil, options: ServeOptions(), autoStart: true)
        m.loadPreview(entries: [e], statuses: [e.id: .running(port: 40_000)])
        return (m, e.id)
    }

    func testOnlyRealFailuresCount() {
        XCTAssertTrue(entry(404).countsAsUnseenError)
        XCTAssertTrue(entry(502).countsAsUnseenError)
        XCTAssertFalse(entry(200).countsAsUnseenError)
        XCTAssertFalse(entry(304).countsAsUnseenError)
        XCTAssertFalse(entry(404, path: "/favicon.ico").countsAsUnseenError)
        XCTAssertFalse(entry(404, path: "/favicon.ico?v=2").countsAsUnseenError)
        XCTAssertFalse(entry(500, headers: [HTTPHeaderField(name: RequestLogEntry.replayHeader, value: "1")]).countsAsUnseenError)
        let detached = [HTTPHeaderField(name: "Sec-Fetch-Site", value: "none"), HTTPHeaderField(name: "Sec-Fetch-Dest", value: "empty")]
        XCTAssertFalse(entry(404, headers: detached).countsAsUnseenError)
    }

    func testFailuresAreCountedPerServerAndCleared() {
        let (m, id) = manager()
        m.append(LogLine(serverID: id, entry: entry(200)))
        m.append(LogLine(serverID: id, entry: entry(404)))
        m.append(LogLine(serverID: id, entry: entry(500)))
        XCTAssertEqual(m.unseenErrors[id], 2)
        XCTAssertEqual(m.unseenErrorTotal, 2)
        m.markErrorsSeen(id)
        XCTAssertEqual(m.unseenErrorTotal, 0)
        m.append(LogLine(serverID: id, entry: entry(404)))
        m.clearLog(for: id)
        XCTAssertEqual(m.unseenErrorTotal, 0)
        m.append(LogLine(serverID: id, entry: entry(404)))
        m.stop(id)
        XCTAssertEqual(m.unseenErrorTotal, 0)
    }

    func testShowActivityLeavesARequestForTheWindow() {
        let (m, id) = manager()
        m.showActivity(for: id, status: .errors)
        XCTAssertEqual(m.activityRequest, ActivityRequest(serverID: id, status: .errors))
    }

    func testBadgeText() {
        XCTAssertNil(MenuBarBadge.text(forErrors: 0))
        XCTAssertEqual(MenuBarBadge.text(forErrors: 3), "3")
        XCTAssertEqual(MenuBarBadge.text(forErrors: 9), "9")
        XCTAssertEqual(MenuBarBadge.text(forErrors: 10), "9+")
    }

    func testFailedServersCountTowardTheBadge() {
        let (m, id) = manager()
        XCTAssertEqual(m.attentionCount, 0)
        m.append(LogLine(serverID: id, entry: entry(404)))
        XCTAssertEqual(m.attentionCount, 1)
        let e = ServerEntry(id: UUID(), bookmark: Data(), folderPath: "/tmp/b", preferredPort: nil, options: ServeOptions(), autoStart: true)
        m.loadPreview(entries: [e], statuses: [e.id: .error("Port 3000 is already in use")])
        XCTAssertEqual(m.failedServerCount, 1)
        XCTAssertEqual(m.attentionCount, 1)
    }

    func testEveryRequestAdvancesTheTick() {
        let (m, id) = manager()
        let before = m.requestTick
        m.append(LogLine(serverID: id, entry: entry(200)))
        XCTAssertEqual(m.requestTick, before + 1)
    }

    func testPulseRules() {
        XCTAssertTrue(MenuBarBadge.shouldPulse(reduceMotion: false, alreadyPulsing: false))
        XCTAssertFalse(MenuBarBadge.shouldPulse(reduceMotion: true, alreadyPulsing: false))
        XCTAssertFalse(MenuBarBadge.shouldPulse(reduceMotion: false, alreadyPulsing: true))
    }
}
