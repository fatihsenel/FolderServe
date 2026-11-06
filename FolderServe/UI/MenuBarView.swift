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
                Image(systemName: "globe.americas.fill").foregroundStyle(Theme.accent)
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
            Divider()
            HStack {
                Button { addFolders() } label: { Label("Add Folder…", systemImage: "plus") }
                Spacer()
                Button("Open App") { openApp() }
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.callout)
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
        for url in FolderPicker.pickFolders(allowsMultiple: true) { manager.add(folder: url) }
    }
}

private struct MenuBarRow: View {
    @Environment(ServerManager.self) private var manager
    let entry: ServerEntry
    private var status: ServerStatus { manager.statuses[entry.id] ?? .stopped }
    private var isRunning: Bool { if case .running = status { return true } else { return false } }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.statusColor(status)).frame(width: 9, height: 9)
                .shadow(color: Theme.statusColor(status).opacity(0.8), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { copyURL() } label: { Image(systemName: "doc.on.doc") }
                .disabled(!isRunning).help("Copy URL")
            Button { isRunning ? manager.stop(entry.id) : manager.start(entry.id) } label: {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isRunning ? Theme.failed : Theme.running)
            }
            .disabled(status == .folderMissing)
            .help(isRunning ? "Stop" : "Start")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var detail: String {
        switch status {
        case .running(let port): return "127.0.0.1:\(String(port))"
        case .stopped: return "Stopped"
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
