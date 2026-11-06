import SwiftUI
import FolderServeCore

@main
struct FolderServeApp: App {
    @NSApplicationDelegateAdaptor(FolderServeAppDelegate.self) private var appDelegate
    private let manager = AppServices.manager
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        Window("FolderServe", id: "main") {
            MainWindow()
                .environment(manager)
                .task { if !Self.isRunningTests { manager.startAutoStartEntries() } }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
