import AppKit

@MainActor
enum AppServices {
    static let manager = ServerManager(store: JSONFileStore.default, recentsStore: JSONFileStore.recents)
    /// The Mac App Store updates apps itself and forbids another update path (guideline 2.4.5), so the App Store build
    /// (`-D APPSTORE`, see scripts/appstore.sh) has no update checker at all.
    #if APPSTORE
    @MainActor static let updates: UpdateChecker? = nil
    #else
    @MainActor static let updates: UpdateChecker? = UpdateChecker()
    #endif
}

final class FolderServeAppDelegate: NSObject, NSApplicationDelegate {
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Restores servers at launch, independent of whether the main window is shown
    /// (the app can live in the menu bar only).
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        NSApp.servicesProvider = self
        MainActor.assumeIsolated {
            Self.restoreServers(manager: AppServices.manager)
            Task { await AppServices.updates?.checkIfDue() }
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
            await Self.handleOpen(urls: urls, manager: AppServices.manager) { BrowserOpener.open($0) }
        }
    }

    /// The Services entry "Serve with FolderServe" (Finder ▸ right-click a folder ▸ Services): serves the selected folders and opens them.
    @objc func serveFolders(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = Self.folderURLs(in: pasteboard)
        guard !urls.isEmpty else {
            error.pointee = "No folder was selected." as NSString
            return
        }
        Task { @MainActor in
            await Self.handleService(urls: urls, manager: AppServices.manager) { BrowserOpener.open($0) }
        }
    }

    /// The file URLs on a Services pasteboard that are folders.
    static func folderURLs(in pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return objects.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    /// Serves each folder (a folder that is already served is reused) and calls `open` with its address once it runs.
    @MainActor
    static func handleService(urls: [URL], manager: ServerManager, open: @MainActor (URL) -> Void) async {
        for url in urls {
            let (id, _) = manager.addDropped(url: url)
            for _ in 0..<250 {
                if case .running = manager.statuses[id] { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            if case .running = manager.statuses[id], let target = manager.openURL(for: id) { open(target) }
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
