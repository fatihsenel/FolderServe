import XCTest
@testable import FolderServeCore

final class PathResolverTests: XCTestCase {
    var root: URL!
    var outside: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        let base = fm.temporaryDirectory.appendingPathComponent("fs-\(UUID().uuidString)")
        root = base.appendingPathComponent("site")
        outside = base.appendingPathComponent("outside")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root.deletingLastPathComponent())
    }

    @discardableResult
    private func write(_ rel: String, _ body: String = "x") throws -> URL {
        let url = root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func resolver(_ o: ServeOptions = ServeOptions()) -> PathResolver {
        PathResolver(root: root, options: o)
    }

    private func real(_ u: URL) -> URL { u.resolvingSymlinksInPath() }

    func testServesFile() throws {
        let f = try write("a.txt")
        XCTAssertEqual(resolver().resolve(path: "/a.txt", acceptsHTML: false), .file(real(f)))
    }

    func testDirectoryWithIndexServesIndex() throws {
        let f = try write("docs/index.html")
        XCTAssertEqual(resolver().resolve(path: "/docs/", acceptsHTML: true), .file(real(f)))
    }

    func testDirectoryWithoutIndexListsIt() throws {
        try write("docs/a.txt")
        XCTAssertEqual(resolver().resolve(path: "/docs/", acceptsHTML: true),
                       .directoryListing(real(root.appendingPathComponent("docs"))))
    }

    func testRootWithoutIndexListsRoot() throws {
        try write("a.txt")
        XCTAssertEqual(resolver().resolve(path: "/", acceptsHTML: true), .directoryListing(real(root)))
    }

    func testDirectoryWithoutTrailingSlashRedirects() throws {
        try write("docs/a.txt")
        XCTAssertEqual(resolver().resolve(path: "/docs", acceptsHTML: true), .redirect("/docs/"))
    }

    func testDotDotIsForbidden() throws {
        try "s".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(resolver().resolve(path: "/../outside/secret.txt", acceptsHTML: false), .forbidden)
        XCTAssertEqual(resolver().resolve(path: "/a/../../x", acceptsHTML: false), .forbidden)
    }

    func testSymlinkEscapingRootIsForbidden() throws {
        try "s".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: root.appendingPathComponent("link.txt"),
                                  withDestinationURL: outside.appendingPathComponent("secret.txt"))
        try fm.createSymbolicLink(at: root.appendingPathComponent("dirlink"), withDestinationURL: outside)
        XCTAssertEqual(resolver().resolve(path: "/link.txt", acceptsHTML: false), .forbidden)
        XCTAssertEqual(resolver().resolve(path: "/dirlink/secret.txt", acceptsHTML: false), .forbidden)
    }

    func testSiblingDirWithSharedPrefixIsForbidden() throws {
        // root is ".../site"; a sibling ".../site2" must not pass a naive prefix check.
        let sibling = root.deletingLastPathComponent().appendingPathComponent("site2")
        try fm.createDirectory(at: sibling, withIntermediateDirectories: true)
        try "s".write(to: sibling.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(at: root.appendingPathComponent("sib"), withDestinationURL: sibling)
        XCTAssertEqual(resolver().resolve(path: "/sib/f.txt", acceptsHTML: false), .forbidden)
    }

    func testSymlinkInsideRootIsServed() throws {
        let target = try write("real.txt")
        try fm.createSymbolicLink(at: root.appendingPathComponent("alias.txt"), withDestinationURL: target)
        XCTAssertEqual(resolver().resolve(path: "/alias.txt", acceptsHTML: false), .file(real(target)))
    }

    func testDotfileIsForbiddenByDefaultAndServedWhenEnabled() throws {
        let f = try write(".env")
        XCTAssertEqual(resolver().resolve(path: "/.env", acceptsHTML: false), .forbidden)
        var o = ServeOptions(); o.serveDotfiles = true
        XCTAssertEqual(resolver(o).resolve(path: "/.env", acceptsHTML: false), .file(real(f)))
    }

    func testNestedDotDirectoryForbidden() throws {
        try write(".git/config")
        XCTAssertEqual(resolver().resolve(path: "/.git/config", acceptsHTML: false), .forbidden)
    }

    func testSPAFallbackForExtensionlessPath() throws {
        let idx = try write("index.html")
        XCTAssertEqual(resolver().resolve(path: "/users/42", acceptsHTML: true), .file(real(idx)))
    }

    func testSPANoFallbackForMissingAsset() throws {
        try write("index.html")
        XCTAssertEqual(resolver().resolve(path: "/missing.js", acceptsHTML: true), .notFound)
    }

    func testSPANoFallbackWhenNotAcceptingHTML() throws {
        try write("index.html")
        XCTAssertEqual(resolver().resolve(path: "/users/42", acceptsHTML: false), .notFound)
    }

    func testSPAOffReturnsNotFound() throws {
        try write("index.html")
        var o = ServeOptions(); o.spaMode = false
        XCTAssertEqual(resolver(o).resolve(path: "/users/42", acceptsHTML: true), .notFound)
    }

    func testSPAWithoutRootIndexReturnsNotFound() {
        XCTAssertEqual(resolver().resolve(path: "/users/42", acceptsHTML: true), .notFound)
    }

    func testUnicodeAndSpacesInName() throws {
        let f = try write("my file ü.html")
        XCTAssertEqual(resolver().resolve(path: "/my file ü.html", acceptsHTML: true), .file(real(f)))
    }
}
