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
