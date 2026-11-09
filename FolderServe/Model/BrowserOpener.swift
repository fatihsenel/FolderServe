import AppKit

/// An installed browser the user can pick in Settings.
struct InstalledBrowser: Identifiable, Equatable {
    let id: String          // bundle identifier
    let name: String
    let url: URL
}

/// Opens a served page in the browser chosen in Settings (the system default when none is chosen or it was uninstalled).
enum BrowserOpener {
    /// UserDefaults key holding the chosen browser's bundle identifier ("" = system default).
    static let defaultsKey = "openBrowserID"

    /// Browsers FolderServe offers when they are installed (other apps that can open web links are not browsers for this purpose).
    static let knownBrowserIDs = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi", "org.chromium.Chromium",
        "com.google.Chrome.canary", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen", "com.kagi.kagimacOS",
    ]

    static func installed(workspace: NSWorkspace = .shared) -> [InstalledBrowser] {
        knownBrowserIDs.compactMap { id in
            guard let url = workspace.urlForApplication(withBundleIdentifier: id) else { return nil }
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return InstalledBrowser(id: id, name: name, url: url)
        }
    }

    /// Opens `url` in the chosen browser, or in the default one.
    @MainActor
    static func open(_ url: URL, defaults: UserDefaults = .standard, workspace: NSWorkspace = .shared) {
        let id = defaults.string(forKey: defaultsKey) ?? ""
        if !id.isEmpty, let app = installed(workspace: workspace).first(where: { $0.id == id })?.url {
            workspace.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(url)
        }
    }

    // MARK: Open path

    /// What to store for text typed in the "Open at" field: "" for blank, the path with a leading "/", or nil when it is not
    /// a path on the server (another host, a scheme, control characters). A query (`?tab=2`) and a fragment are kept.
    static func normalizedPath(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        guard !text.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }), !text.contains(" "),
              !text.hasPrefix("//"), !text.contains("://") else { return nil }
        let path = text.hasPrefix("/") ? text : "/" + text
        guard let parts = URLComponents(string: path), parts.scheme == nil, parts.host == nil else { return nil }
        return path
    }

    /// The server's address with the chosen page appended (the root when the path is empty or not valid).
    static func target(base: URL, path: String) -> URL {
        guard let clean = normalizedPath(path), !clean.isEmpty, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false),
              let typed = URLComponents(string: clean) else { return base }
        parts.percentEncodedPath = typed.percentEncodedPath
        parts.percentEncodedQuery = typed.percentEncodedQuery
        parts.percentEncodedFragment = typed.percentEncodedFragment
        return parts.url ?? base
    }
}
