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
        var a = entry("portfolio-site")
        a.options.proxyRules = [ProxyRule(prefix: "/uiapi", target: "https://localhost:5003")]
        let b = entry("react-dashboard"), c = entry("old-docs"), d = entry("blog"), e = entry("new-folder")
        let now = Date()
        func line(_ id: UUID, _ method: String, _ path: String, _ status: Int, _ bytes: Int64, _ ago: TimeInterval) -> LogLine {
            LogLine(serverID: id, entry: RequestLogEntry(date: now.addingTimeInterval(-ago), method: method, path: path, status: status, bytes: bytes))
        }
        m.loadPreview(entries: [a, b, c, d, e], statuses: [
            a.id: .running(port: 8080), b.id: .running(port: 8081), c.id: .folderMissing,
            d.id: .error("Port 3000 is already in use"),
            e.id: .finding(PortSearch(busy: [8080, 8081], landed: 8082, began: Date().addingTimeInterval(-0.5), duration: 1.5)),
        ], log: [
            line(a.id, "GET", "/", 200, 4_210, 9), line(a.id, "GET", "/assets/app.css", 200, 18_400, 8),
            line(b.id, "GET", "/users/42", 200, 1_024, 5), line(b.id, "GET", "/favicon.ico", 404, 612, 4),
            line(a.id, "GET", "/old-page", 301, 140, 2), line(b.id, "GET", "/.env", 403, 580, 1),
        ], kinds: [a.id: .angular, b.id: .react, d.id: .vue])
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
