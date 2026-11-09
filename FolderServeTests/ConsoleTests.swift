import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class ConsoleTests: XCTestCase {
    var manager: ServerManager!
    var base: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        base = fm.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try "<html><head></head><body>x</body></html>".write(to: base.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        manager.stopAll()
        try? fm.removeItem(at: base)
    }

    private func message(_ text: String, _ level: ConsoleMessage.Level = .error) -> ConsoleMessage {
        ConsoleMessage(level: level, text: text, page: "/p")
    }

    func testLinesAreKeptPerServerNewestFirstAndCapped() {
        let a = UUID(), b = UUID()
        manager.appendConsole([message("1"), message("2")], serverID: a)
        manager.appendConsole([message("3")], serverID: b)
        XCTAssertEqual(manager.consoleLines(for: nil).map(\.message.text), ["3", "2", "1"])
        XCTAssertEqual(manager.consoleLines(for: a).map(\.message.text), ["2", "1"])
        manager.clearConsole(for: a)
        XCTAssertEqual(manager.consoleLines(for: nil).map(\.message.text), ["3"])
        manager.appendConsole((0..<(ServerManager.maxConsoleLines + 20)).map { message(String($0)) }, serverID: a)
        XCTAssertEqual(manager.consoleLines.count, ServerManager.maxConsoleLines)
        XCTAssertEqual(manager.consoleLines(for: nil).first?.message.text, String(ServerManager.maxConsoleLines + 19))
        manager.clearConsole(for: nil)
        XCTAssertTrue(manager.consoleLines.isEmpty)
    }

    func testAPagePostReachesTheManagerOnlyWithTheOptionOn() async throws {
        let id = manager.add(folder: base)
        await manager.startNow(id)
        let url = try XCTUnwrap(manager.url(for: id)).appendingPathComponent("__console")
        func post() async throws -> Int {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data(#"[{"l":"uncaught","m":"ReferenceError: y is not defined","u":"/"}]"#.utf8)
            let (_, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        let off = try await post()
        XCTAssertEqual(off, 404)

        var options = try XCTUnwrap(manager.entries.first).options
        options.captureConsole = true
        manager.setOptions(id, options)
        let on = try await post()
        XCTAssertEqual(on, 204)
        for _ in 0..<100 where manager.consoleLines.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(manager.consoleLines(for: id).map(\.message.text), ["ReferenceError: y is not defined"])
        XCTAssertTrue(manager.log.allSatisfy { $0.entry.path != "/__console" || $0.entry.status == 404 })

        manager.remove(id)
        XCTAssertTrue(manager.consoleLines.isEmpty)
    }

    func testRowHelpers() {
        let line = ConsoleLine(serverID: UUID(), message: ConsoleMessage(level: .warn, text: "w", page: ""))
        XCTAssertEqual(ConsoleView.origin(of: line, serverName: "site", showServer: true), "site · /")
        XCTAssertEqual(ConsoleView.origin(of: line, serverName: "site", showServer: false), "/")
        XCTAssertEqual(ConsoleView.color(.warn), Theme.warning)
        XCTAssertEqual(ConsoleView.color(.uncaught), Theme.failed)
        XCTAssertEqual(ServeOptions(captureConsole: true).enabledExtrasCount, ServeOptions().enabledExtrasCount + 1)
    }
}
