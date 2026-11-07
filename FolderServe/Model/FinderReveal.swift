import AppKit

enum FinderReveal {
    /// The folder itself, or the closest parent that still exists (the folder may have been moved or deleted).
    static func target(for path: String, fileManager: FileManager = .default) -> URL? {
        var url = URL(fileURLWithPath: path)
        while !fileManager.fileExists(atPath: url.path) {
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return url
    }

    /// Shows the folder in Finder (selected in its parent). Returns false when nothing could be shown.
    @MainActor @discardableResult
    static func reveal(path: String) -> Bool {
        guard let url = target(for: path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }
}
