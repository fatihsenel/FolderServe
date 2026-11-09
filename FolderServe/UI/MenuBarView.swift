import SwiftUI
import AppKit

struct MenuBarView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()).resizable().frame(width: 20, height: 20)
                Text("FolderServe").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if manager.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "folder.badge.plus")
                        .font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                    Text("Drop a folder here to serve it").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(.secondary.opacity(isTargeted ? 0.9 : 0.4)))
            } else {
                VStack(spacing: 6) {
                    ForEach(manager.entries) { MenuBarRow(entry: $0) }
                }
            }
            if !manager.recents.isEmpty { MenuBarRecents() }
            Divider()
            HStack {
                AddFolderButton(title: "Add Folder…", compact: true) { addFolders() }
                Spacer()
                Group {
                    Button("Open App") { openApp() }
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
                .buttonStyle(.plain)
                .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 340)
        .modifier(MenuBarDropModifier(enabled: !isSnapshot, isTargeted: $isTargeted))
    }

    private var summary: String {
        let running = manager.statuses.values.filter { if case .running = $0 { return true } else { return false } }.count
        return running == 0 ? "Nothing running" : "\(running) running"
    }

    private func openApp() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func addFolders() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        FolderPicker.addFolders(to: manager)
    }
}

private struct MenuBarRow: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.openWindow) private var openWindow
    let entry: ServerEntry
    private var status: ServerStatus { manager.statuses[entry.id] ?? .stopped }
    private var isRunning: Bool { if case .running = status { return true } else { return false } }
    private var isFinding: Bool { if case .finding = status { return true } else { return false } }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.statusColor(status)).frame(width: 9, height: 9)
                .shadow(color: Theme.statusColor(status).opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(entry.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if let kind = manager.projectKinds[entry.id] { ProjectBadge(kind: kind, showsName: false) }
                }
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if errorCount > 0 {
                Button { showErrors() } label: {
                    Text(errorCount > 99 ? "99+" : String(errorCount))
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.failed, in: Capsule())
                }
                .help("\(errorCount) failed request\(errorCount == 1 ? "" : "s") — show them in Activity")
                .accessibilityLabel("\(errorCount) failed requests")
            }
            Button { openInBrowser() } label: { Image(systemName: "safari") }
                .disabled(!isRunning).help("Open in browser")
            Button { copyURL() } label: { Image(systemName: "doc.on.doc") }
                .disabled(!isRunning).help("Copy URL")
            Button { isRunning ? manager.stop(entry.id) : manager.start(entry.id) } label: {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isRunning ? Theme.failed : Theme.running)
            }
            .disabled(status == .folderMissing || isFinding)
            .help(isRunning ? "Stop" : "Start")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.running.opacity(manager.highlightedIDs.contains(entry.id) ? 0.9 : 0), lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.running.opacity(manager.highlightedIDs.contains(entry.id) ? 0.16 : 0)))
                .animation(.smooth(duration: 0.5), value: manager.highlightedIDs.contains(entry.id))
                .allowsHitTesting(false))
        .contextMenu { menuItems }
    }

    private var errorCount: Int { manager.unseenErrors[entry.id] ?? 0 }

    @ViewBuilder private var menuItems: some View {
        Button("Open in Browser") { openInBrowser() }.disabled(!isRunning)
        Button("Copy URL") { copyURL() }.disabled(!isRunning)
        if status != .folderMissing { Button("Show in Finder") { FinderReveal.reveal(path: entry.folderPath) } }
        Button("Show Requests") { showActivity(.any) }
        Divider()
        Button { manager.toggleShare(entry.id) } label: {
            if entry.options.shareOnNetwork { Label("Share on network", systemImage: "checkmark") } else { Text("Share on network") }
        }
        Divider()
        Button("Remove…") { openApp(); manager.requestRemoval(entry.id) }
    }

    private func openInBrowser() {
        guard let url = manager.openURL(for: entry.id) else { return }
        BrowserOpener.open(url)
    }

    private func showErrors() {
        manager.markErrorsSeen(entry.id)
        showActivity(.errors)
    }

    private func showActivity(_ status: StatusFilter) {
        manager.showActivity(for: entry.id, status: status)
        openApp()
    }

    private func openApp() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var detail: String {
        switch status {
        case .running(let port): return "\(manager.hostName(for: entry.id)):\(String(port))"
        case .stopped: return "Stopped"
        case .finding: return "Finding port…"
        case .error(let message): return message
        case .folderMissing: return "Folder missing"
        }
    }

    private func copyURL() {
        guard let url = manager.url(for: entry.id) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

/// Folders removed from the list earlier: one click serves one again (with its old name, port and options) and opens it.
struct MenuBarRecents: View {
    @Environment(ServerManager.self) private var manager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Recent folders").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { manager.clearRecents() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).handCursor()
            }
            ForEach(manager.recents) { recent in
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                    Text(recent.displayName).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.location(of: recent.folderPath)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                    Button { manager.forgetRecent(recent.id) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Forget this folder")
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { serve(recent) }
                .handCursor()
                .help("Serve \(recent.folderPath) again and open it")
            }
        }
    }

    /// The parent folder's name ("Projects" for /Users/me/Projects/site), enough to tell two same-named folders apart.
    static func location(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    }

    private func serve(_ recent: ServerEntry) {
        Task {
            guard let id = await manager.reopenRecent(recent.id), let url = manager.openURL(for: id) else { return }
            BrowserOpener.open(url)
        }
    }
}

private struct MenuBarDropModifier: ViewModifier {
    @Environment(ServerManager.self) private var manager
    let enabled: Bool
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: URL.self) { urls, _ in
                for url in urls { _ = manager.addDropped(url: url) }
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}

/// The small number next to the menu bar icon when pages have failed requests nobody has looked at.
enum MenuBarBadge {
    static func text(forErrors count: Int) -> String? {
        count <= 0 ? nil : (count > 9 ? "9+" : String(count))
    }
}
