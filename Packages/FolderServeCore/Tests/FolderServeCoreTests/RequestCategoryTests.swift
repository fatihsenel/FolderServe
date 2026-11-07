import XCTest
@testable import FolderServeCore

final class RequestCategoryTests: XCTestCase {
    private func c(_ path: String, dest: String? = nil, proxied: Bool = false) -> RequestCategory {
        .classify(path: path, secFetchDest: dest, proxied: proxied)
    }

    func testByExtensionWithoutBrowserHint() {
        XCTAssertEqual(c("/main-AB12.js"), .js); XCTAssertEqual(c("/x.mjs"), .js); XCTAssertEqual(c("/x.js.map"), .js)
        XCTAssertEqual(c("/a/b.css"), .css)
        XCTAssertEqual(c("/logo.PNG"), .img); XCTAssertEqual(c("/i.svg"), .img); XCTAssertEqual(c("/favicon.ico"), .img)
        XCTAssertEqual(c("/f.woff2"), .font); XCTAssertEqual(c("/f.ttf"), .font)
        XCTAssertEqual(c("/v.mp4"), .media); XCTAssertEqual(c("/s.mp3"), .media)
        XCTAssertEqual(c("/index.html"), .doc); XCTAssertEqual(c("/"), .doc); XCTAssertEqual(c("/users/42"), .doc)
        XCTAssertEqual(c("/assets/config.json"), .fetch)
        XCTAssertEqual(c("/x.wasm"), .other); XCTAssertEqual(c("-"), .other)
    }

    func testBrowserSecFetchDestWinsOverExtension() {
        XCTAssertEqual(c("/users/42", dest: "empty"), .fetch, "extensionless fetch() is not a document")
        XCTAssertEqual(c("/users/42", dest: "document"), .doc)
        XCTAssertEqual(c("/data.js", dest: "empty"), .fetch)
        XCTAssertEqual(c("/x", dest: "script"), .js); XCTAssertEqual(c("/x", dest: "worker"), .js)
        XCTAssertEqual(c("/x", dest: "style"), .css)
        XCTAssertEqual(c("/x", dest: "image"), .img)
        XCTAssertEqual(c("/x", dest: "font"), .font)
        XCTAssertEqual(c("/x", dest: "video"), .media); XCTAssertEqual(c("/x", dest: "audio"), .media)
        XCTAssertEqual(c("/x", dest: "iframe"), .doc)
    }

    func testProxiedCallsAreFetchUnlessTheBrowserSaysOtherwise() {
        XCTAssertEqual(c("/uiapi/Account/Login", proxied: true), .fetch)
        XCTAssertEqual(c("/uiapi/report.pdf", proxied: true), .fetch)
        XCTAssertEqual(c("/uiapi/photo.png", dest: "image", proxied: true), .img)
    }

    func testEveryCategoryHasALabel() {
        XCTAssertEqual(RequestCategory.allCases.map(\.label), ["Fetch/XHR", "Doc", "JS", "CSS", "Img", "Media", "Font", "Other"])
    }
}

final class RequestLogCategoryIntegrationTests: XCTestCase {
    var root: URL!; var server: StaticServer!; let fm = FileManager.default
    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("cat-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        try "a{}".write(to: root.appendingPathComponent("a.css"), atomically: true, encoding: .utf8)
        try "1".write(to: root.appendingPathComponent("data"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? fm.removeItem(at: root) }

    func testServedRequestsAreLoggedWithTheirCategory() async throws {
        server = StaticServer(root: root, port: 0, options: ServeOptions())
        let box = LogBox(); server.onRequest = { box.add($0) }
        let port = try await server.start()
        _ = RawHTTP.get(port: port, "/a.css")
        _ = RawHTTP.get(port: port, "/data", headers: "Sec-Fetch-Dest: empty\r\n")
        _ = RawHTTP.get(port: port, "/", headers: "Sec-Fetch-Dest: document\r\n")
        _ = RawHTTP.get(port: port, "/missing.png")
        try await Task.sleep(nanoseconds: 300_000_000)
        let byPath = Dictionary(box.entries.map { ($0.path, $0.category) }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byPath["/a.css"], .css)
        XCTAssertEqual(byPath["/data"], .fetch)
        XCTAssertEqual(byPath["/"], .doc)
        XCTAssertEqual(byPath["/missing.png"], .img, "a 404 still belongs to the kind of thing that was asked for")
    }
}
