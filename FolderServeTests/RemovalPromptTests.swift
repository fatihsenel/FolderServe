import XCTest
import SwiftUI
import AppKit
import FolderServeCore
@testable import FolderServe

@MainActor
final class RemovalPromptTests: XCTestCase {
    private func entry(name: String? = nil, rules: Int = 0) -> ServerEntry {
        var e = ServerEntry(id: UUID(), bookmark: Data(), folderPath: "/Users/me/Projects/shop-dist", preferredPort: nil,
                            options: ServeOptions(), autoStart: true)
        e.customName = name
        e.options.proxyRules = (0..<rules).map { ProxyRule(prefix: "/api\($0)", target: "http://localhost:300\($0)") }
        return e
    }
    private func kinds(_ e: ServerEntry, _ s: ServerStatus) -> [RemovalPrompt.Consequence.Kind] {
        RemovalPrompt.consequences(for: e, status: s).map(\.kind)
    }

    func testTitleUsesTheShownNameNotTheFolderName() {
        XCTAssertEqual(RemovalPrompt.title(for: entry()), "Remove “shop-dist” from FolderServe?")
        XCTAssertEqual(RemovalPrompt.title(for: entry(name: "Shop (Angular)")), "Remove “Shop (Angular)” from FolderServe?")
    }

    func testStoppedFolderHasNoStopLine() {
        XCTAssertEqual(kinds(entry(), .stopped), [.forgets, .safe])
        XCTAssertEqual(RemovalPrompt.consequences(for: entry(), status: .stopped)[0].text,
                       "It disappears from this list. Its settings will be forgotten.")
    }

    func testRunningFolderSaysItsServerWillStopFirst() {
        let list = RemovalPrompt.consequences(for: entry(), status: .running(port: 8080))
        XCTAssertEqual(list.map(\.kind), [.stops, .forgets, .safe])
        XCTAssertEqual(list[0].text, "Its server on port 8080 will stop.")
    }

    func testSearchingFolderIsMentioned() {
        let search = PortSearch(busy: [], landed: nil, began: Date(), duration: 1.5)
        XCTAssertEqual(kinds(entry(), .finding(search)).first, .stops)
    }

    func testCustomNameAndProxyRulesAreListedAsWhatIsForgotten() {
        XCTAssertTrue(RemovalPrompt.message(for: entry(name: "Shop", rules: 1), status: .stopped).contains("(custom name, 1 proxy rule)"))
        XCTAssertTrue(RemovalPrompt.message(for: entry(rules: 3), status: .stopped).contains("(3 proxy rules)"))
    }

    func testAlwaysReassuresThatFilesAreNotDeleted() {
        for status: ServerStatus in [.stopped, .running(port: 1), .folderMissing, .error("x")] {
            XCTAssertEqual(kinds(entry(), status).last, .safe)
            XCTAssertTrue(RemovalPrompt.message(for: entry(), status: status).hasSuffix("The files in the folder are not deleted."))
        }
    }

    func testRenderConfirmationSnapshots() throws {
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        for (name, e, status) in [("running", entry(name: "Shop (Angular)", rules: 2), ServerStatus.running(port: 8080)),
                                  ("stopped", entry(), ServerStatus.stopped)] {
            let view = RemoveConfirmationView(entry: e, status: status, kind: .angular, onCancel: {}, onConfirm: {})
                .environment(\.isSnapshotRendering, true)
                .frame(width: 640, height: 640).background(Theme.background(.dark))
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(renderer.nsImage?.tiffRepresentation))?.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000)
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("snap-remove-\(name).png"))
        }
    }
}
