import SwiftUI
import FolderServeCore

@main
struct FolderServeApp: App {
    @State private var manager = ServerManager(store: JSONFileStore.default)
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var body: some Scene {
        WindowGroup("FolderServe") {
            MainWindow()
                .environment(manager)
                .task { if !Self.isRunningTests { manager.startAutoStartEntries() } }
        }
        .windowStyle(.hiddenTitleBar)
    }
}
