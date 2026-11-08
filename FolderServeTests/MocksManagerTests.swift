import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class MocksManagerTests: XCTestCase {
    func testSettersStoreRulesAndCountActiveOnes() throws {
        let manager = PreviewData.manager(populated: true)
        let id = try XCTUnwrap(manager.entries.first).id
        manager.setMockRules(id, [MockRule(path: "/a"), MockRule(enabled: false, path: "/b"), MockRule(path: "nope")])
        manager.setHeaderRules(id, [HeaderRule(path: "*", name: "X-A", value: "1"), HeaderRule(name: "")])
        let options = try XCTUnwrap(manager.entries.first { $0.id == id }).options
        XCTAssertEqual(options.mockRules.count, 3)
        XCTAssertEqual(options.headerRules.count, 2)
        XCTAssertEqual(options.activeMockCount, 2, "one enabled valid mock and one valid header; disabled and invalid ones do not count")
    }

    func testAMockChangesARunningServerWithoutARestart() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("mm-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "FILE".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        var url: URL?
        for _ in 0..<250 { url = manager.url(for: id); if url != nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        let base = try XCTUnwrap(url)

        func get(_ path: String) async throws -> (Int, String, String?) {
            let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent(path))
            let r = response as! HTTPURLResponse
            return (r.statusCode, String(decoding: data, as: UTF8.self), r.value(forHTTPHeaderField: "X-Env"))
        }
        let before = try await get("a.txt")
        XCTAssertEqual(before.1, "FILE")
        manager.setMockRules(id, [MockRule(path: "/a.txt", status: 418, body: "teapot")])
        manager.setHeaderRules(id, [HeaderRule(path: "*", name: "X-Env", value: "demo")])
        let mocked = try await get("a.txt")
        XCTAssertEqual(mocked.0, 418); XCTAssertEqual(mocked.1, "teapot"); XCTAssertEqual(mocked.2, "demo")
        manager.setMockRules(id, [])
        let back = try await get("a.txt")
        XCTAssertEqual(back.1, "FILE"); XCTAssertEqual(back.2, "demo", "the header rule stays")
    }
}
