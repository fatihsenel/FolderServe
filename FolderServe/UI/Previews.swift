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
            LogLine(serverID: id, entry: RequestLogEntry(date: now.addingTimeInterval(-ago), method: method, path: path, status: status, bytes: bytes,
                                                         category: .classify(path: path, secFetchDest: nil, proxied: path.hasPrefix("/uiapi"))))
        }
        m.loadPreview(entries: [a, b, c, d, e], statuses: [
            a.id: .running(port: 8080), b.id: .running(port: 8081), c.id: .folderMissing,
            d.id: .error("Port 3000 is already in use"),
            e.id: .finding(PortSearch(busy: [8080, 8081], landed: 8082, began: Date().addingTimeInterval(-0.5), duration: 1.5)),
        ], log: [
            line(a.id, "GET", "/", 200, 4_210, 9), line(a.id, "GET", "/assets/app.css", 200, 18_400, 8),
            line(b.id, "GET", "/users/42", 200, 1_024, 5), line(b.id, "GET", "/favicon.ico", 404, 612, 4),
            line(a.id, "GET", "/old-page", 301, 140, 2), line(b.id, "GET", "/.env", 403, 580, 1),
            line(a.id, "POST", "/uiapi/Account/Login", 200, 912, 1), line(a.id, "GET", "/fonts/inter.woff2", 200, 48_000, 1),
            line(b.id, "GET", "/main-AB12.js", 200, 350_000, 1), line(b.id, "GET", "/logo.png", 200, 9_300, 1),
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

// MARK: - One preview per view
// Entries in the populated manager: [0] running, [1] running, [2] folder missing, [3] error, [4] finding a port.

extension PreviewData {
    /// A populated manager plus the id of its first (running) server.
    static func runningServer() -> (manager: ServerManager, id: UUID) {
        let m = manager(populated: true)
        return (m, m.entries[0].id)
    }

    static func requestLine(for id: UUID) -> LogLine {
        LogLine(serverID: id, entry: RequestLogEntry(
            date: Date(), method: "GET", path: "/assets/app.css", status: 200, bytes: 18_400,
            category: .classify(path: "/assets/app.css", secFetchDest: nil, proxied: false)))
    }
}

#Preview("Servers") { ServersView().environment(PreviewData.manager(populated: true)).frame(width: 900, height: 700) }
#Preview("Servers – drop targeted") {
    ServersView(initiallyTargeted: true).environment(PreviewData.manager(populated: true)).frame(width: 900, height: 700)
}
#Preview("Server card") {
    let s = PreviewData.runningServer()
    return ServerCardView(entryID: s.id).environment(s.manager).padding().frame(width: 700)
}
#Preview("Sidebar") {
    SidebarView(selection: .constant(.servers)).environment(PreviewData.manager(populated: true)).frame(width: 220, height: 500)
}
#Preview("Activity") {
    let s = PreviewData.runningServer()
    return ActivityView(initialSelection: s.id).environment(s.manager).frame(width: 900, height: 700)
}
#Preview("Request detail") {
    let s = PreviewData.runningServer()
    return RequestDetailView(line: PreviewData.requestLine(for: s.id), onClose: {})
        .environment(s.manager).frame(width: 520, height: 600)
}
#Preview("Request detail – JSON response") {
    let s = PreviewData.runningServer()
    let json = #"{"user":{"id":42,"name":"Ada","admin":true,"manager":null,"roles":["ops","dev"],"score":9.5},"ok":true}"#
    return RequestDetailView(line: PreviewData.requestLine(for: s.id), initialTab: .preview,
                             preloaded: LoadedContent(data: Data(json.utf8)), onClose: {})
        .environment(s.manager).frame(width: 520, height: 600)
}
#Preview("Menu bar") { MenuBarView().environment(PreviewData.manager(populated: true)).frame(width: 320) }
#Preview("Proxy editor") {
    let s = PreviewData.runningServer()
    return ProxyEditorView(entryID: s.id, initialRules: s.manager.entries[0].options.proxyRules).environment(s.manager)
}
#Preview("Options popover") {
    let s = PreviewData.runningServer()
    return OptionsPopoverView(entryID: s.id).environment(s.manager)
}
#Preview("Share popover") {
    let s = PreviewData.runningServer()
    return SharePopoverView(entryID: s.id).environment(s.manager)
}
#Preview("Remove confirmation") {
    let m = PreviewData.manager(populated: true)
    return RemoveConfirmationView(entry: m.entries[0], status: m.statuses[m.entries[0].id] ?? .stopped,
                                  kind: .angular, onCancel: {}, onConfirm: {})
}
#Preview("Port scan") {
    PortScanView(search: PortSearch(busy: [8080, 8081], landed: 8082, began: Date().addingTimeInterval(-0.5), duration: 1.5))
        .padding().frame(width: 360)
}
#Preview("Drop zone") { DropZoneView(isTargeted: false, addFolder: {}).padding().frame(width: 600, height: 320) }
#Preview("Drop zone – targeted") { DropZoneView(isTargeted: true, addFolder: {}).padding().frame(width: 600, height: 320) }
#Preview("Drop overlay") { DropOverlayView().frame(width: 600, height: 400) }
#Preview("Drop burst") { DropBurstView(point: CGPoint(x: 150, y: 150)).frame(width: 300, height: 300) }
#Preview("Round action button") {
    HStack(spacing: 20) {
        RoundActionButton(isRunning: false, isBusy: false, action: {})
        RoundActionButton(isRunning: true, isBusy: false, action: {})
        RoundActionButton(isRunning: false, isBusy: true, action: {})
    }.padding()
}
#Preview("Project badge") {
    HStack { ForEach(ProjectKind.allCases, id: \.self) { ProjectBadge(kind: $0) } }.padding()
}
#Preview("Option badge") { HStack { OptionBadge(text: "SPA"); OptionBadge(text: "HTTPS", warning: true) }.padding() }
#Preview("Splash") { SplashView(time: 1.0).frame(width: SplashSettings.size.width, height: SplashSettings.size.height) }
#endif
