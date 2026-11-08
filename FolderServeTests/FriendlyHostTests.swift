import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class FriendlyHostTests: XCTestCase {
    func testSlugs() {
        XCTAssertEqual(HostSlug.make("Portfolio Site"), "portfolio-site")
        XCTAssertEqual(HostSlug.make("  my_app (v2)!  "), "my-app-v2")
        XCTAssertEqual(HostSlug.make("Müşteri Sitesi"), "musteri-sitesi")
        XCTAssertEqual(HostSlug.make("Kullanıcı İşlemleri"), "kullanici-islemleri")
        XCTAssertEqual(HostSlug.make("---"), "folder")
        XCTAssertEqual(HostSlug.make(""), "folder")
        XCTAssertEqual(HostSlug.make("日本語"), "folder", "nothing usable left")
        let long = HostSlug.make(String(repeating: "ab-", count: 40))
        XCTAssertLessThanOrEqual(long.count, HostSlug.maxLength)
        XCTAssertFalse(long.hasSuffix("-")); XCTAssertFalse(long.hasPrefix("-"))
    }

    func testURLUsesTheNameOnlyWhenTheOptionIsOn() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("My Site-\(UUID().uuidString.prefix(4))")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        manager.rename(id, to: "Demo App")
        for _ in 0..<250 where manager.url(for: id) == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(manager.url(for: id)?.host, "127.0.0.1")
        XCTAssertEqual(manager.hostName(for: id), "127.0.0.1")

        var options = try XCTUnwrap(manager.entries.first { $0.id == id }).options
        options.friendlyHost = true
        manager.setOptions(id, options)
        XCTAssertEqual(manager.url(for: id)?.host, "demo-app.localhost")
        XCTAssertEqual(manager.hostName(for: id), "demo-app.localhost")
        XCTAssertEqual(manager.url(for: id)?.port, manager.url(for: id).flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.port })

        manager.rename(id, to: "Other Name")
        XCTAssertEqual(manager.hostName(for: id), "other-name.localhost", "follows the label")
    }

    func testTheServerAnswersOnTheNameAddress() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("fh-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "hello".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        var options = try XCTUnwrap(manager.entries.first { $0.id == id }).options
        options.friendlyHost = true
        manager.setOptions(id, options)
        for _ in 0..<250 where manager.url(for: id) == nil { try await Task.sleep(nanoseconds: 20_000_000) }
        let base = try XCTUnwrap(manager.url(for: id))
        XCTAssertTrue(base.host?.hasSuffix(".localhost") == true)
        do {
            let (data, response) = try await URLSession.shared.data(from: base.appendingPathComponent("a.txt"))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
        } catch let error as URLError where error.code == .cannotFindHost || error.code == .dnsLookupFailed {
            throw XCTSkip("This machine does not resolve *.localhost (\(error.code.rawValue))")
        }
    }

    func testOptionCountsInTheOptionsBadge() {
        XCTAssertEqual(ServeOptions(spaMode: false, friendlyHost: true).enabledExtrasCount, 1)
    }

    func testOlderSettingsDefaultToTheNumericAddress() throws {
        let o = try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"spaMode":true}"#.utf8))
        XCTAssertFalse(o.friendlyHost)
    }
}
