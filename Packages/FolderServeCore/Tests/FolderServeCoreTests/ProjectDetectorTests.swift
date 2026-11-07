import XCTest
@testable import FolderServeCore

final class ProjectDetectorTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
    private func pkg(_ deps: String...) throws {
        let body = deps.map { "\"\($0)\": \"1.0.0\"" }.joined(separator: ",")
        try write("package.json", "{\"dependencies\": {\(body)}}")
    }

    func testAngularJson() throws { try write("angular.json", "{}"); XCTAssertEqual(ProjectDetector.detect(root: dir), .angular) }
    func testReactPackage() throws { try pkg("react", "react-dom"); XCTAssertEqual(ProjectDetector.detect(root: dir), .react) }
    func testNextBeatsReact() throws { try pkg("react", "next"); XCTAssertEqual(ProjectDetector.detect(root: dir), .next) }
    func testNuxtBeatsVue() throws { try pkg("vue", "nuxt"); XCTAssertEqual(ProjectDetector.detect(root: dir), .nuxt) }
    func testVue() throws { try pkg("vue"); XCTAssertEqual(ProjectDetector.detect(root: dir), .vue) }
    func testSvelteKit() throws { try pkg("@sveltejs/kit", "svelte"); XCTAssertEqual(ProjectDetector.detect(root: dir), .svelte) }
    func testViteOnly() throws { try pkg("vite"); XCTAssertEqual(ProjectDetector.detect(root: dir), .vite) }
    func testDevDependenciesCount() throws {
        try write("package.json", "{\"devDependencies\": {\"@angular/core\": \"17\"}}")
        XCTAssertEqual(ProjectDetector.detect(root: dir), .angular)
    }
    func testPlainHTML() throws { try write("index.html", "<h1>hi</h1>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .html) }
    func testEmptyFolder() { XCTAssertNil(ProjectDetector.detect(root: dir)) }
    func testMalformedPackageJSON() throws { try write("package.json", "{nope"); XCTAssertNil(ProjectDetector.detect(root: dir)) }

    func testBuiltAngular() throws { try write("index.html", "<body><app-root></app-root><script src=\"main-X.js\"></script>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .angular) }
    func testBuiltAngularCustomSelector() throws {
        try write("index.html", "<body><my-shell></my-shell><script src=\"polyfills-AB12.js\" type=\"module\"></script><script src=\"main-CD34.js\" type=\"module\"></script>")
        XCTAssertEqual(ProjectDetector.detect(root: dir), .angular)
    }
    func testBrowserFolderWithMainBundleIsAngular() throws {
        let browser = dir.appendingPathComponent("browser")
        try FileManager.default.createDirectory(at: browser, withIntermediateDirectories: true)
        try "<body><x-root></x-root><script src=\"main-ZZ.js\"></script>".write(to: browser.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDetector.detect(root: browser), .angular)
    }
    func testBrowserFolderNameAloneIsNotEnough() throws {
        let browser = dir.appendingPathComponent("browser")
        try FileManager.default.createDirectory(at: browser, withIntermediateDirectories: true)
        try "<h1>hi</h1>".write(to: browser.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDetector.detect(root: browser), .html)
    }
    func testAngularSSRBrowserFolderWithCsrIndex() throws {
        let browser = dir.appendingPathComponent("browser")
        try FileManager.default.createDirectory(at: browser, withIntermediateDirectories: true)
        try "<x-root></x-root><script src=\"main-ZZ.js\"></script>".write(to: browser.appendingPathComponent("index.csr.html"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDetector.detect(root: browser), .angular)
    }
    func testBuiltNext() throws { try write("index.html", "<script src=\"/_next/static/a.js\"></script>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .next) }
    func testBuiltReactVite() throws { try write("index.html", "<div id=\"root\"></div><script type=\"module\" src=\"/assets/i.js\"></script>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .react) }
    func testBuiltVueVite() throws { try write("index.html", "<div id=\"app\"></div><script type=\"module\" src=\"/assets/i.js\"></script>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .vue) }
    func testPlainRootDivIsNotReact() throws { try write("index.html", "<div id=\"root\"></div>"); XCTAssertEqual(ProjectDetector.detect(root: dir), .html) }

    func testSymlinkedPackageJSONOutsideRootIgnored() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("pd-out-\(UUID().uuidString).json")
        try "{\"dependencies\": {\"react\": \"1\"}}".write(to: outside, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("package.json"), withDestinationURL: outside)
        XCTAssertNil(ProjectDetector.detect(root: dir))
    }
}
