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
                .environment(\.updates, AppServices.updates)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            #if !APPSTORE
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { if let updates = AppServices.updates { Task { await UpdatePrompt.checkAndShow(updates) } } }
            }
            #endif
            CommandGroup(replacing: .newItem) {
                Button("Add Folder…") { FolderPicker.addFolders(to: manager) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView().environment(manager)
        } label: {
            MenuBarLabel(glyph: Self.menuBarGlyph).environment(manager)
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
