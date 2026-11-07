import XCTest
import SwiftUI
@testable import FolderServe

/// Renders the main window to PNG files so the layout can be inspected without a display.
/// Output goes to $FOLDERSERVE_SNAPSHOT_DIR (default: the sandbox temp dir) and is printed.
@MainActor
final class SnapshotTests: XCTestCase {
    private func render(_ name: String, populated: Bool, scheme: ColorScheme, tab: SidebarItem = .servers) throws {
        let view = MainWindow(initialSelection: tab)
            .environment(PreviewData.manager(populated: populated))
            .environment(\.colorScheme, scheme)
            .environment(\.isSnapshotRendering, true)
            .frame(width: 960, height: 720)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage, "no image for \(name)")
        let tiff = try XCTUnwrap(image.tiffRepresentation)
        let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000)
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("snap-\(name).png")
        try png.write(to: url)
        print("SNAPSHOT:", url.path)
    }

    func testRenderNarrowWindowSnapshot() throws {
        let view = MainWindow(initialSelection: .servers)
            .environment(PreviewData.manager(populated: true))
            .environment(\.colorScheme, .dark)
            .environment(\.isSnapshotRendering, true)
            .frame(width: 860, height: 760)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(renderer.nsImage?.tiffRepresentation))?.representation(using: .png, properties: [:]))
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("snap-narrow-dark.png"))
    }

    func testRenderMainWindowSnapshots() throws {
        try render("empty-dark", populated: false, scheme: .dark)
        try render("populated-dark", populated: true, scheme: .dark)
        try render("populated-light", populated: true, scheme: .light)
        try render("activity-dark", populated: true, scheme: .dark, tab: .activity)
        try render("settings-dark", populated: true, scheme: .dark, tab: .settings)
    }

    func testRenderMenuBarSnapshots() throws {
        for (name, populated) in [("menubar-empty", false), ("menubar-populated", true)] {
            let view = MenuBarView()
                .environment(PreviewData.manager(populated: populated))
                .environment(\.colorScheme, .dark)
                .environment(\.isSnapshotRendering, true)
                .background(Color(white: 0.15))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 5_000)
            let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("snap-\(name).png"))
        }
    }

    func testRenderSplashSnapshots() throws {
        let dir = ProcessInfo.processInfo.environment["FOLDERSERVE_SNAPSHOT_DIR"] ?? NSTemporaryDirectory()
        for (label, time) in [("early", 0.9), ("late", 2.3)] {
            let renderer = ImageRenderer(content: SplashView(time: time).padding(30).background(Color(white: 0.1)))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let tiff = try XCTUnwrap(image.tiffRepresentation)
            let png = try XCTUnwrap(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000)
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("splash-signal-\(label).png"))
        }
    }
}
