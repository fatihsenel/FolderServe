import SwiftUI
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
            Image(systemName: "globe.americas.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
