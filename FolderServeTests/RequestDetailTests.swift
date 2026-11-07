import XCTest
import SwiftUI
import AppKit
import FolderServeCore
@testable import FolderServe

@MainActor
final class RequestDetailTests: XCTestCase {
    // MARK: helpers

    func testJSONIsPrettyPrintedWithSortedKeys() {
        let out = RequestDetailView.displayText(Data(#"{"b":1,"a":{"x":"y/z"}}"#.utf8), contentType: "application/json")
        XCTAssertTrue(out.contains("\n"))
        XCTAssertLessThan(out.range(of: "\"a\"")!.lowerBound, out.range(of: "\"b\"")!.lowerBound)
        XCTAssertTrue(out.contains("y/z"), "slashes are not escaped")
    }

    func testJSONIsDetectedWithoutAContentType() {
        XCTAssertTrue(RequestDetailView.displayText(Data(#"[1,2]"#.utf8), contentType: nil).contains("\n"))
    }

    func testJSONLeavesGetTheirTextAndColour() throws {
        let root = try XCTUnwrap(RequestDetailView.jsonRoot(Data(#"{"s":"a/b","n":36,"f":9.5,"t":true,"z":null}"#.utf8)) as? [String: Any])
        let s = RequestDetailView.jsonLeaf(root["s"]!), n = RequestDetailView.jsonLeaf(root["n"]!), f = RequestDetailView.jsonLeaf(root["f"]!)
        let t = RequestDetailView.jsonLeaf(root["t"]!), z = RequestDetailView.jsonLeaf(root["z"]!)
        XCTAssertEqual(s.text, "\"a/b\""); XCTAssertEqual(s.color, RequestDetailView.jsonStringColor)
        XCTAssertEqual(n.text, "36"); XCTAssertEqual(n.color, RequestDetailView.jsonNumberColor)
        XCTAssertEqual(f.text, "9.5")
        XCTAssertEqual(t.text, "true"); XCTAssertEqual(t.color, RequestDetailView.jsonLiteralColor)
        XCTAssertEqual(z.text, "null"); XCTAssertEqual(z.color, RequestDetailView.jsonLiteralColor)
    }

    func testOneAndZeroAreNumbersNotBooleans() throws {
        let root = try XCTUnwrap(RequestDetailView.jsonRoot(Data(#"{"a":1,"b":0,"c":false}"#.utf8)) as? [String: Any])
        XCTAssertEqual(RequestDetailView.jsonLeaf(root["a"]!).text, "1")
        XCTAssertEqual(RequestDetailView.jsonLeaf(root["b"]!).text, "0")
        XCTAssertEqual(RequestDetailView.jsonLeaf(root["c"]!).text, "false")
    }

    func testStringsAreQuotedAndEscaped() {
        XCTAssertEqual(RequestDetailView.jsonQuoted("a\"b\nc/d"), #""a\"b\nc/d""#)
    }

    func testOnlyJSONObjectsAndArraysBecomeATree() {
        XCTAssertNil(RequestDetailView.jsonRoot(Data("{oops".utf8)))
        XCTAssertNil(RequestDetailView.jsonRoot(Data("hello".utf8)))
        XCTAssertNil(RequestDetailView.jsonRoot(Data("42".utf8)))
        XCTAssertNil(RequestDetailView.jsonRoot(Data("a=1&b=2".utf8)))
        XCTAssertNotNil(RequestDetailView.jsonRoot(Data("[1,2]".utf8)))
        XCTAssertNil(RequestDetailView.jsonRoot(Data(repeating: 0x20, count: RequestDetailView.jsonHighlightLimit) + Data("[1]".utf8)), "too big for a tree")
    }

    /// Renders the JSON tree in several fold states (frames for a demo animation) to $FOLDERSERVE_SNAPSHOT_DIR.
    func testRenderJSONFoldFrames() throws {
        let json = #"{"ok":true,"user":{"id":42,"name":"Ada","roles":["ops","dev"],"address":{"city":"Istanbul","zip":"34000"}},"items":[{"id":1},{"id":2}]}"#
        let root = try XCTUnwrap(RequestDetailView.jsonRoot(Data(json.utf8)))
        let frames: [(String, Set<String>)] = [
            ("0-open", []),
            ("1-address", ["/user/address"]),
            ("2-roles", ["/user/address", "/user/roles"]),
            ("3-items", ["/user/address", "/user/roles", "/items"]),
            ("4-user", ["/user", "/items"]),
            ("5-all", ["/user", "/items", "/ok"]),
        ]
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        for (name, folded) in frames {
            let view = JSONTreeView(root: root, copyText: json, folded: folded)
                .padding(14)
                .frame(width: 480, alignment: .topLeading)
                .frame(height: 360, alignment: .topLeading)
                .background(Theme.background(.dark))
                .environment(\.colorScheme, .dark)
                .environment(\.isSnapshotRendering, true)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(renderer.nsImage?.tiffRepresentation))?.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fold-\(name).png"))
        }
    }

    func testActivityDurationText() {
        XCTAssertEqual(ActivityView.durationText(nil), "—")
        XCTAssertEqual(ActivityView.durationText(0), "< 1 ms")
        XCTAssertEqual(ActivityView.durationText(42), "42 ms")
        XCTAssertEqual(ActivityView.durationText(999), "999 ms")
        XCTAssertEqual(ActivityView.durationText(1240), "1.24 s")
    }

    func testActivityDurationColourGetsWarmerWhenSlower() {
        XCTAssertEqual(ActivityView.durationColor(299), .secondary)
        XCTAssertEqual(ActivityView.durationColor(300), Theme.warning)
        XCTAssertEqual(ActivityView.durationColor(999), Theme.warning)
        XCTAssertEqual(ActivityView.durationColor(1000), Theme.failed)
        XCTAssertEqual(ActivityView.durationColor(nil), .secondary)
    }

    func testActivitySearchMatchesEveryWordInAnyCase() {
        var e = RequestLogEntry(method: "POST", path: "/uiapi/Account/Login", status: 200, bytes: 912, note: "→ https://localhost:5003", category: .fetch)
        e.durationMs = 5
        XCTAssertTrue(ActivityView.matches(e, query: ""))
        XCTAssertTrue(ActivityView.matches(e, query: "   "))
        XCTAssertTrue(ActivityView.matches(e, query: "login"))
        XCTAssertTrue(ActivityView.matches(e, query: "LOGIN post 200"))
        XCTAssertTrue(ActivityView.matches(e, query: "localhost:5003"), "the note is searched")
        XCTAssertTrue(ActivityView.matches(e, query: "fetch"), "the type label is searched")
        XCTAssertFalse(ActivityView.matches(e, query: "login get"), "every word has to match")
        XCTAssertFalse(ActivityView.matches(e, query: "404"))
    }

    private func curlEntry(_ method: String, _ url: String, headers: [(String, String)] = [], body: Data? = nil) -> RequestLogEntry {
        var e = RequestLogEntry(method: method, path: "/x", status: 200, bytes: 1)
        e.url = url
        e.requestHeaders = headers.map { HTTPHeaderField(name: $0.0, value: $0.1) }
        e.requestBody = body
        return e
    }

    func testCurlForAPlainGet() {
        let cmd = RequestDetailView.curlCommand(for: curlEntry("GET", "http://127.0.0.1:8080/a?b=1",
                                                              headers: [("Accept", "*/*"), ("Host", "127.0.0.1:8080"), ("Connection", "keep-alive")]))
        XCTAssertEqual(cmd, "curl 'http://127.0.0.1:8080/a?b=1' \\\n  -H 'Accept: */*'")
    }

    func testCurlForAPostKeepsHeadersAndBodyAndEscapesQuotes() {
        let cmd = RequestDetailView.curlCommand(for: curlEntry("POST", "http://127.0.0.1:8080/uiapi/Login",
            headers: [("content-type", "application/json"), ("Content-Length", "20"), ("Accept-Encoding", "gzip, br")],
            body: Data(#"{"name":"O'Neil"}"#.utf8)))
        XCTAssertTrue(cmd.contains("-X POST"))
        XCTAssertTrue(cmd.contains("-H 'content-type: application/json'"))
        XCTAssertFalse(cmd.lowercased().contains("content-length"))
        XCTAssertTrue(cmd.contains("--compressed"))
        XCTAssertFalse(cmd.lowercased().contains("accept-encoding"))
        XCTAssertTrue(cmd.contains(#"--data-raw '{"name":"O'\''Neil"}'"#), cmd)
    }

    func testCurlLeavesOutBodiesItCannotRepeatAndSaysSo() {
        var cut = curlEntry("POST", "http://127.0.0.1:8080/a", body: Data("abc".utf8))
        cut.requestBodyTruncated = true
        XCTAssertFalse(RequestDetailView.curlCommand(for: cut).contains("--data-raw"))
        XCTAssertTrue(RequestDetailView.curlCommand(for: cut).contains("# The request body was cut off"))
        let binary = curlEntry("PUT", "http://127.0.0.1:8080/a", body: Data([0xff, 0xfe, 0x00]))
        XCTAssertTrue(RequestDetailView.curlCommand(for: binary).contains("# The request body is binary"))
    }

    func testCurlAddsInsecureOnlyForLoopbackHttps() {
        XCTAssertTrue(RequestDetailView.curlCommand(for: curlEntry("GET", "https://127.0.0.1:8443/")).contains("--insecure"))
        XCTAssertTrue(RequestDetailView.curlCommand(for: curlEntry("GET", "https://localhost:5003/x")).contains("--insecure"))
        XCTAssertFalse(RequestDetailView.curlCommand(for: curlEntry("GET", "https://example.com/")).contains("--insecure"))
        XCTAssertFalse(RequestDetailView.curlCommand(for: curlEntry("GET", "http://127.0.0.1:8080/")).contains("--insecure"))
        XCTAssertTrue(RequestDetailView.curlCommand(for: curlEntry("HEAD", "http://127.0.0.1:8080/")).contains("--head"))
    }

    private func timed(_ ms: Int?, _ path: String) -> LogLine {
        var e = RequestLogEntry(method: "GET", path: path, status: 200, bytes: 1)
        e.durationMs = ms
        return LogLine(serverID: UUID(), entry: e)
    }

    func testSlowestFirstOrdersByTimeAndKeepsUntimedLast() {
        let lines = [timed(5, "/a"), timed(nil, "/b"), timed(900, "/c"), timed(5, "/d"), timed(300, "/e")]
        XCTAssertEqual(ActivityView.ordered(lines, slowestFirst: false).map(\.entry.path), ["/a", "/b", "/c", "/d", "/e"])
        XCTAssertEqual(ActivityView.ordered(lines, slowestFirst: true).map(\.entry.path), ["/c", "/e", "/a", "/d", "/b"],
                       "longest first; equal times keep their order; unknown times go last")
    }

    func testOnlyASlowEnoughRequestGetsTheSlowestMarker() {
        let slow = timed(1240, "/slow")
        XCTAssertEqual(ActivityView.slowestID(in: [timed(3, "/a"), slow, timed(85, "/b")]), slow.id)
        XCTAssertNil(ActivityView.slowestID(in: [timed(3, "/a"), timed(299, "/b")]), "299 ms is below the threshold")
        XCTAssertNil(ActivityView.slowestID(in: [slow]), "nothing to compare it with")
        XCTAssertNil(ActivityView.slowestID(in: [timed(nil, "/a"), timed(nil, "/b")]))
    }

    func testBrokenJSONIsShownAsIs() {
        XCTAssertEqual(RequestDetailView.displayText(Data("{oops".utf8), contentType: "application/json"), "{oops")
    }

    func testFormBodiesAreDecoded() {
        let out = RequestDetailView.displayText(Data("user=a%40b.com&note=hello+world&empty=".utf8), contentType: "application/x-www-form-urlencoded")
        XCTAssertEqual(out, "user: a@b.com\nnote: hello world\nempty: ")
    }

    func testTextDetection() {
        XCTAssertTrue(RequestDetailView.isText(Data("<html>".utf8), contentType: "text/html"))
        XCTAssertTrue(RequestDetailView.isText(Data("{}".utf8), contentType: "application/json; charset=utf-8"))
        XCTAssertTrue(RequestDetailView.isText(Data("var a".utf8), contentType: "application/javascript"))
        XCTAssertFalse(RequestDetailView.isText(Data([0x89, 0x50, 0x4e, 0x47]), contentType: "image/png"))
        XCTAssertFalse(RequestDetailView.isText(Data("text but octet".utf8), contentType: "application/octet-stream"))
        XCTAssertTrue(RequestDetailView.isText(Data("plain".utf8), contentType: nil), "unknown type, looks like text")
        XCTAssertFalse(RequestDetailView.isText(Data([0, 1, 2, 3, 4]), contentType: nil), "unknown type, binary")
    }

    func testGarbageIsNotAFont() {
        XCTAssertNil(RequestDetailView.sampleFont(from: Data("not a font".utf8)))
    }

    // MARK: snapshots

    private func entry(method: String, path: String, status: Int, category: RequestCategory, type: String, url: String? = nil) -> RequestLogEntry {
        var e = RequestLogEntry(method: method, path: path, status: status, bytes: 912, category: category)
        e.url = url ?? "http://127.0.0.1:8080\(path)"
        e.requestHeaders = [HTTPHeaderField(name: "accept", value: "application/json"), HTTPHeaderField(name: "content-type", value: "application/json"),
                            HTTPHeaderField(name: "host", value: "127.0.0.1:8080"), HTTPHeaderField(name: "user-agent", value: "Mozilla/5.0 (Macintosh)")]
        e.responseHeaders = [HTTPHeaderField(name: "Cache-Control", value: "no-store"), HTTPHeaderField(name: "Content-Type", value: type),
                             HTTPHeaderField(name: "Set-Cookie", value: "session=abc; Path=/; HttpOnly; SameSite=Lax")]
        e.durationMs = 42
        return e
    }

    private func render(_ name: String, _ view: some View) throws {
        let framed = view.environment(PreviewData.manager(populated: true)).environment(\.colorScheme, .dark)
            .environment(\.isSnapshotRendering, true).frame(width: 480, height: 720).padding(20)
            .background(Theme.background(.dark))
        let renderer = ImageRenderer(content: framed); renderer.scale = 2
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(renderer.nsImage?.tiffRepresentation))?.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 5_000)
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("snap-detail-\(name).png"))
    }

    private func samplePNG() -> Data {
        let image = NSImage(size: NSSize(width: 160, height: 90))
        image.lockFocus()
        NSGradient(colors: [.systemPurple, .systemTeal])!.draw(in: NSRect(x: 0, y: 0, width: 160, height: 90), angle: 20)
        NSColor.white.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: 60, y: 25, width: 40, height: 40)).fill()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testRenderActivityWithSelectedRequest() throws {
        let manager = PreviewData.manager(populated: true)
        let line = try XCTUnwrap(manager.logLines(for: nil).first { $0.entry.category == .fetch } ?? manager.logLines(for: nil).first)
        for (name, width) in [("wide", 1180.0), ("narrow", 640.0)] {
            let view = ActivityView(initialSelection: line.id)
                .environment(manager).environment(\.colorScheme, .dark).environment(\.isSnapshotRendering, true)
                .frame(width: width, height: 640).background(Theme.background(.dark))
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(renderer.nsImage?.tiffRepresentation))?.representation(using: .png, properties: [:]))
            let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("snap-activity-selected-\(name).png"))
        }
    }

    func testRenderDetailSnapshots() throws {
        var api = entry(method: "POST", path: "/uiapi/Account/Login", status: 200, category: .fetch, type: "application/json; charset=utf-8")
        api.upstreamURL = "https://localhost:5003/uiapi/Account/Login"
        api.requestBody = Data(#"{"email":"ada@example.com","password":"••••••"}"#.utf8)
        api.responseBody = Data(#"{"token":"eyJhbGciOi...","user":{"id":7,"name":"Ada"},"roles":["admin","editor"]}"#.utf8)
        let apiLine = LogLine(serverID: UUID(), entry: api)
        let body = LoadedContent(data: api.responseBody, totalSize: 912)
        try render("headers", RequestDetailView(line: apiLine, initialTab: .headers, preloaded: body) {})
        try render("payload", RequestDetailView(line: apiLine, initialTab: .payload, preloaded: body) {})
        try render("response", RequestDetailView(line: apiLine, initialTab: .response, preloaded: body) {})
        try render("preview-json", RequestDetailView(line: apiLine, initialTab: .preview, preloaded: body) {})

        var img = entry(method: "GET", path: "/assets/images/logo.png", status: 200, category: .img, type: "image/png")
        img.servedFile = "/Users/me/site/assets/images/logo.png"
        let png = samplePNG()
        try render("preview-image", RequestDetailView(line: LogLine(serverID: UUID(), entry: img), initialTab: .preview,
                                                      preloaded: LoadedContent(data: png, totalSize: Int64(png.count))) {})
    }
}
