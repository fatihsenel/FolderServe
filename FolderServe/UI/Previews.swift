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
        a.options.responseDelayMs = 500
        a.options.mocks = [MockRule(method: "GET", path: "/uiapi/Account/Profile", body: #"{"id":7,"name":"Ada","roles":["admin"]}"#),
                           MockRule(method: "POST", path: "/uiapi/Orders", status: 503, body: #"{"error":"Service unavailable"}"#, enabled: false)]
        let b = entry("react-dashboard"), c = entry("old-docs"), d = entry("blog"), e = entry("new-folder")
        let now = Date()
        func line(_ id: UUID, _ method: String, _ path: String, _ status: Int, _ bytes: Int64, _ ago: TimeInterval, ms: Int? = nil) -> LogLine {
            var e = RequestLogEntry(date: now.addingTimeInterval(-ago), method: method, path: path, status: status, bytes: bytes,
                                    category: .classify(path: path, secFetchDest: nil, proxied: path.hasPrefix("/uiapi")))
            e.durationMs = ms ?? (path.hasPrefix("/uiapi") ? 640 : (bytes > 100_000 ? 85 : 3))
            e.url = "http://127.0.0.1:8080" + path
            let proxied = path.hasPrefix("/uiapi")
            e.requestHeaders = [HTTPHeaderField(name: "accept", value: proxied ? "application/json" : "*/*"),
                                HTTPHeaderField(name: "host", value: "127.0.0.1:8080"),
                                HTTPHeaderField(name: "referer", value: "http://127.0.0.1:8080/"),
                                HTTPHeaderField(name: "user-agent", value: "Mozilla/5.0 (Macintosh) Safari/605.1.15")]
                + (proxied ? [HTTPHeaderField(name: "content-type", value: "application/json")] : [])
            e.responseHeaders = [HTTPHeaderField(name: "Cache-Control", value: "no-store"),
                                 HTTPHeaderField(name: "Content-Type", value: proxied ? "application/json; charset=utf-8" : "text/plain; charset=utf-8")]
            if proxied {
                e.upstreamURL = "https://localhost:5003" + path
                e.requestBody = Data(#"{"email":"ada@example.com","password":"••••••"}"#.utf8)
                e.responseBody = Data(#"{"token":"eyJhbGciOi...","user":{"id":7,"name":"Ada"},"roles":["admin","editor"]}"#.utf8)
            }
            return LogLine(serverID: id, entry: e)
        }
        m.loadPreview(entries: [a, b, c, d, e], statuses: [
            a.id: .running(port: 8080), b.id: .running(port: 8081), c.id: .folderMissing,
            d.id: .error("Port 3000 is already in use"),
            e.id: .finding(PortSearch(busy: [8080, 8081], landed: 8082, began: Date().addingTimeInterval(-0.5), duration: 1.5)),
        ], log: [
            line(a.id, "GET", "/", 200, 4_210, 9), line(a.id, "GET", "/assets/app.css", 200, 18_400, 8),
            line(b.id, "GET", "/users/42", 200, 1_024, 5), line(b.id, "GET", "/favicon.ico", 404, 612, 4),
            line(a.id, "GET", "/old-page", 301, 140, 2), line(b.id, "GET", "/.env", 403, 580, 1),
            line(a.id, "POST", "/uiapi/Account/Login", 200, 912, 1, ms: 1240), line(a.id, "GET", "/fonts/inter.woff2", 200, 48_000, 1),
            line(b.id, "GET", "/main-AB12.js", 200, 350_000, 1), line(b.id, "GET", "/logo.png", 200, 9_300, 1),
        ], kinds: [a.id: .angular, b.id: .react, d.id: .vue],
        recents: [entry("landing-page"), entry("docs-preview")],
        console: [
            ConsoleLine(serverID: b.id, message: ConsoleMessage(date: now.addingTimeInterval(-40), level: .warn, text: "Each child in a list should have a unique \"key\" prop.", page: "/users")),
            ConsoleLine(serverID: a.id, message: ConsoleMessage(date: now.addingTimeInterval(-12), level: .error, text: "Login failed: 401 Unauthorized {\"code\":\"bad_credentials\"}", page: "/login")),
            ConsoleLine(serverID: b.id, message: ConsoleMessage(date: now.addingTimeInterval(-3), level: .uncaught, text: "TypeError: Cannot read properties of undefined (reading 'name') (/main-AB12.js:214)", page: "/users/42")),
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

// MARK: - One preview per view
// Entries in the populated manager: [0] running, [1] running, [2] folder missing, [3] error, [4] finding a port.

extension PreviewData {
    /// A running server whose log holds one page load (index.html, its script, stylesheet, font and a failing image).
    /// Returns the page's line too.
    static func pageLoadServer() -> (manager: ServerManager, page: LogLine) {
        let s = runningServer()
        let origin = "http://127.0.0.1:8080"
        let t0 = Date().addingTimeInterval(-5)
        func line(_ path: String, _ category: RequestCategory, endAfter: Double, ms: Int, bytes: Int64, status: Int = 200,
                  referer: String? = nil) -> LogLine {
            var e = RequestLogEntry(date: t0.addingTimeInterval(endAfter), method: "GET", path: path, status: status, bytes: bytes, category: category)
            e.url = origin + path
            e.durationMs = ms
            if let referer { e.requestHeaders = [HTTPHeaderField(name: "referer", value: referer)] }
            return LogLine(serverID: s.id, entry: e)
        }
        let page = line("/", .doc, endAfter: 0.012, ms: 12, bytes: 4_210)
        for l in [page,
                  line("/assets/app.css", .css, endAfter: 0.09, ms: 60, bytes: 18_400, referer: origin + "/"),
                  line("/main.js", .js, endAfter: 0.62, ms: 540, bytes: 350_000, referer: origin + "/"),
                  line("/fonts/inter.woff2", .font, endAfter: 0.31, ms: 190, bytes: 48_000, referer: origin + "/assets/app.css"),
                  line("/missing.png", .img, endAfter: 0.7, ms: 4, bytes: 612, status: 404, referer: origin + "/")] {
            s.manager.append(l)
        }
        return (s.manager, page)
    }

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
#Preview("Add Folder button") {
    HStack(spacing: 30) { AddFolderButton(action: {}); AddFolderButton(action: {}, initiallyHovering: true) }.padding(30)
}

#Preview("Add Folder button – compact and Choose Folder") {
    HStack(spacing: 30) {
        AddFolderButton(title: "Choose Folder…", action: {})
        AddFolderButton(compact: true, action: {}, initiallyHovering: true)
    }.padding(30)
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
#Preview("Activity, errors only") {
    ActivityView(initialStatus: .errors).environment(PreviewData.manager(populated: true)).frame(width: 900, height: 500)
}
#Preview("Edit & Replay") {
    let s = PreviewData.runningServer()
    return EditReplayView(line: PreviewData.requestLine(for: s.id)).environment(s.manager)
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
#Preview("Request detail – XML response") {
    let s = PreviewData.runningServer()
    let xml = #"<?xml version="1.0"?><users total="2"><user id="7"><name>Ada</name><tags><tag>ops</tag><tag>dev</tag></tags></user><user id="9"><name>Linus</name><note/></user></users>"#
    var entry = PreviewData.requestLine(for: s.id).entry
    entry.responseHeaders = [HTTPHeaderField(name: "Content-Type", value: "application/xml")]
    return RequestDetailView(line: LogLine(serverID: s.id, entry: entry), initialTab: .preview,
                             preloaded: LoadedContent(data: Data(xml.utf8)), onClose: {})
        .environment(s.manager).frame(width: 520, height: 600)
}
#Preview("Request detail – page load") {
    let s = PreviewData.pageLoadServer()
    return RequestDetailView(line: s.page, onClose: {}).environment(s.manager).frame(width: 520, height: 600)
}
#Preview("Update banner") {
    UpdateBanner(release: LatestRelease(tag: "v0.1.6", version: AppVersion("0.1.6")!,
                                        url: URL(string: "https://github.com/fatihsenel/FolderServe/releases/tag/v0.1.6")!),
                 current: AppVersion("0.1.5")!)
        .padding(28).frame(width: 760)
}
#Preview("Menu bar") { MenuBarView().environment(PreviewData.manager(populated: true)).frame(width: 320) }
#Preview("Proxy editor") {
    let s = PreviewData.runningServer()
    return ProxyEditorView(entryID: s.id, initialRules: s.manager.entries[0].options.proxyRules).environment(s.manager)
}
#Preview("Activity console") {
    ActivityView(initialMode: .console).environment(PreviewData.manager(populated: true)).frame(width: 900, height: 500)
}
#Preview("Console") { ConsoleView(serverID: nil).environment(PreviewData.manager(populated: true)).frame(width: 800, height: 400) }
#Preview("Mock editor") {
    let s = PreviewData.runningServer()
    return MockEditorView(entryID: s.id, initialRules: s.manager.entries[0].options.mocks).environment(s.manager)
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
