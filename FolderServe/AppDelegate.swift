import AppKit

@MainActor
enum AppServices {
    static let manager = ServerManager(store: JSONFileStore.default)
    @MainActor static let updates = UpdateChecker()
}

final class FolderServeAppDelegate: NSObject, NSApplicationDelegate {
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Restores servers at launch, independent of whether the main window is shown
    /// (the app can live in the menu bar only).
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        MainActor.assumeIsolated {
            Self.restoreServers(manager: AppServices.manager)
            Task { await AppServices.updates.checkIfDue() }
            if SplashSettings.enabled && !Self.launchedAsLoginItem { SplashController.shared.show(gatingMainWindow: true) }
        }
    }

    /// Login-item launches should be quiet (menu bar only), so no splash.
    private static var launchedAsLoginItem: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    @MainActor
    static func restoreServers(manager: ServerManager) {
        manager.startAutoStartEntries(pinnedOnly: !manager.startServersAtLaunch)
    }

    /// Folders/files dropped on the Dock icon, or passed via `open -a FolderServe <path>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            await Self.handleOpen(urls: urls, manager: AppServices.manager) { NSWorkspace.shared.open($0) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppServices.manager.stopAll() }
    }

    /// Adds every file URL. A dropped *file* serves its parent folder, then `open` is called with the
    /// file's URL once the server is up; a dropped folder is only added.
    @MainActor
    static func handleOpen(urls: [URL], manager: ServerManager, open: @MainActor (URL) -> Void) async {
        for url in urls where url.isFileURL {
            let (id, openPath) = manager.addDropped(url: url)
            guard let openPath else { continue }
            for _ in 0..<250 {
                if case .running = manager.statuses[id] { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if let base = manager.url(for: id), let target = URL(string: openPath, relativeTo: base)?.absoluteURL {
                open(target)
            }
        }
    }
}
