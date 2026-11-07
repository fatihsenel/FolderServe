import SwiftUI
import AppKit
import FolderServeCore

@main
struct FolderServeApp: App {
    @NSApplicationDelegateAdaptor(FolderServeAppDelegate.self) private var appDelegate
    private let manager = AppServices.manager

    var body: some Scene {
        Window("FolderServe", id: "main") {
            MainWindow()
                .environment(manager)
        }
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView().environment(manager)
        } label: {
            Image(nsImage: Self.menuBarGlyph)
        }
        .menuBarExtraStyle(.window)
    }

    private static let menuBarGlyph: NSImage = {
        let image = NSImage(named: "MenuBarGlyph") ?? NSImage(systemSymbolName: "folder", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
