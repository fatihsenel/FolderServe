import AppKit

enum FinderReveal {
    /// Shows the folder in Finder (selected in its parent). Returns false when it no longer exists.
    @MainActor @discardableResult
    static func reveal(path: String, fileManager: FileManager = .default) -> Bool {
        guard fileManager.fileExists(atPath: path) else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        return true
    }
}
