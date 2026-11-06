#if DEBUG
import SwiftUI
import FolderServeCore

@MainActor
enum PreviewData {
    static func manager(populated: Bool) -> ServerManager {
        let m = ServerManager(store: PreviewStore())
        guard populated else { return m }
        func entry(_ name: String) -> ServerEntry {
            ServerEntry(id: UUID(), bookmark: Data(), folderPath: "/Users/me/Projects/\(name)", preferredPort: nil,
                        options: ServeOptions(), autoStart: true)
        }
        let a = entry("portfolio-site"), b = entry("react-dashboard"), c = entry("old-docs"), d = entry("blog")
        m.loadPreview(entries: [a, b, c, d], statuses: [
            a.id: .running(port: 8080), b.id: .running(port: 8081), c.id: .folderMissing,
            d.id: .error("Port 3000 is already in use"),
        ])
        return m
    }
}

private struct PreviewStore: ServerStoring {
    func load() -> [ServerEntry] { [] }
    func save(_ entries: [ServerEntry]) {}
}

#Preview("Empty") { MainWindow().environment(PreviewData.manager(populated: false)).frame(width: 900, height: 600) }
#Preview("Populated") { MainWindow().environment(PreviewData.manager(populated: true)).frame(width: 900, height: 700) }
#endif
