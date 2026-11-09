import XCTest
import FolderServeCore
@testable import FolderServe

@MainActor
final class BrowserOpenerTests: XCTestCase {
    func testNormalizedPath() {
        XCTAssertEqual(BrowserOpener.normalizedPath(""), "")
        XCTAssertEqual(BrowserOpener.normalizedPath("   "), "")
        XCTAssertEqual(BrowserOpener.normalizedPath("/docs/index.html"), "/docs/index.html")
        XCTAssertEqual(BrowserOpener.normalizedPath("docs/index.html"), "/docs/index.html")
        XCTAssertEqual(BrowserOpener.normalizedPath(" /app?tab=2#top "), "/app?tab=2#top")
        XCTAssertEqual(BrowserOpener.normalizedPath("/a%20b"), "/a%20b")
    }

    func testNormalizedPathRefusesAnythingThatIsNotAPathOnTheServer() {
        for bad in ["http://evil.example/", "//evil.example/x", "javascript:alert(1)//://", "/a b", "/a\nb", "/a\r\nHost: x", "https://x"] {
            XCTAssertNil(BrowserOpener.normalizedPath(bad), bad)
        }
    }

    func testTargetAppendsThePathToTheServerAddress() {
        let base = URL(string: "http://127.0.0.1:8080/")!
        XCTAssertEqual(BrowserOpener.target(base: base, path: "").absoluteString, "http://127.0.0.1:8080/")
        XCTAssertEqual(BrowserOpener.target(base: base, path: "/docs/index.html").absoluteString, "http://127.0.0.1:8080/docs/index.html")
        XCTAssertEqual(BrowserOpener.target(base: base, path: "app?tab=2#top").absoluteString, "http://127.0.0.1:8080/app?tab=2#top")
        XCTAssertEqual(BrowserOpener.target(base: URL(string: "https://my-site.localhost:8443/")!, path: "/x").absoluteString,
                       "https://my-site.localhost:8443/x")
    }

    func testAnInvalidPathFallsBackToTheRoot() {
        let base = URL(string: "http://127.0.0.1:8080/")!
        XCTAssertEqual(BrowserOpener.target(base: base, path: "http://evil.example/").absoluteString, "http://127.0.0.1:8080/")
        XCTAssertEqual(BrowserOpener.target(base: base, path: "//evil.example/").absoluteString, "http://127.0.0.1:8080/")
    }

    func testInstalledBrowsersAreOnlyKnownOnesWithNames() {
        let found = BrowserOpener.installed()
        for b in found {
            XCTAssertTrue(BrowserOpener.knownBrowserIDs.contains(b.id))
            XCTAssertFalse(b.name.isEmpty)
            XCTAssertTrue(FileManager.default.fileExists(atPath: b.url.path))
        }
        XCTAssertEqual(Set(found.map(\.id)).count, found.count)
    }

    func testOpenPathIsStoredAndOldSettingsDecodeWithoutIt() throws {
        var o = ServeOptions(); o.openPath = "/docs"
        let again = try JSONDecoder().decode(ServeOptions.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(again.openPath, "/docs")
        let old = try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"spaMode":true}"#.utf8))
        XCTAssertEqual(old.openPath, "")
        XCTAssertEqual(ServeOptions(openPath: "/x").enabledExtrasCount, ServeOptions().enabledExtrasCount + 1)
    }

    func testManagerOpenURLUsesTheFoldersOpenPath() async throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bo-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let manager = ServerManager(store: InMemoryStore(), defaultStartPort: UInt16.random(in: 20_000...50_000), minSearchDuration: 0)
        defer { manager.stopAll() }
        let id = manager.add(folder: dir)
        var base: URL?
        for _ in 0..<250 { base = manager.url(for: id); if base != nil { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(manager.openURL(for: id), base)
        var options = try XCTUnwrap(manager.entries.first?.options)
        options.openPath = "/docs/index.html"
        manager.setOptions(id, options)
        XCTAssertEqual(manager.openURL(for: id)?.absoluteString, base!.absoluteString + "docs/index.html")
        XCTAssertNil(manager.openURL(for: UUID()))
    }
}
