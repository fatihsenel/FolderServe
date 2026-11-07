import SwiftUI
import AppKit
import FolderServeCore

struct ServerCardView: View {
    @Environment(ServerManager.self) private var manager
    let entryID: UUID

    private var entry: ServerEntry? { manager.entries.first { $0.id == entryID } }
    private var status: ServerStatus { manager.statuses[entryID] ?? .stopped }

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(entry.displayName).font(.system(size: 19, weight: .semibold, design: .rounded))
                            if let kind = manager.projectKinds[entryID] { ProjectBadge(kind: kind) }
                        }
                        Text(entry.folderPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        statusLine
                    }
                    Spacer(minLength: 12)
                    RoundActionButton(isRunning: isRunning, isBusy: status == .folderMissing) {
                        isRunning ? manager.stop(entryID) : manager.start(entryID)
                    }
                }
                Divider().opacity(0.4)
                HStack(spacing: 18) {
                    Toggle("Live reload", isOn: binding(\.liveReload, entry)).toggleStyle(.switch)
                    Toggle("SPA mode", isOn: binding(\.spaMode, entry)).toggleStyle(.switch)
                        .help("Serve index.html for unknown paths so client-side routers work")
                    Spacer()
                    Button { open() } label: { Label("Open", systemImage: "safari") }.disabled(!isRunning)
                    Button { copyURL() } label: { Label("Copy URL", systemImage: "doc.on.doc") }.disabled(!isRunning)
                    Button(role: .destructive) { manager.remove(entryID) } label: { Image(systemName: "trash") }
                        .help("Remove this folder")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .card()
        }
    }

    private var isRunning: Bool { if case .running = status { return true } else { return false } }

    private var statusIcon: some View {
        ZStack {
            Circle().fill(Theme.statusColor(status).opacity(0.35)).blur(radius: 14).frame(width: 64, height: 64)
            Circle().fill(.ultraThinMaterial).frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(Theme.statusColor(status).opacity(0.8), lineWidth: 2))
            Image(systemName: "folder.fill").font(.system(size: 24))
                .foregroundStyle(Theme.statusColor(status))
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .running(let port):
            Button { open() } label: {
                Text("http://127.0.0.1:\(String(port))/").font(.system(.callout, design: .monospaced))
            }.buttonStyle(.link)
        case .stopped:
            Text("Stopped").font(.callout).foregroundStyle(.secondary)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(Theme.failed)
        case .folderMissing:
            HStack {
                Label("Folder missing", systemImage: "questionmark.folder.fill").font(.callout).foregroundStyle(Theme.warning)
                Button("Relocate…") { relocate() }.controlSize(.small)
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ServeOptions, Bool>, _ entry: ServerEntry) -> Binding<Bool> {
        Binding(
            get: { entry.options[keyPath: keyPath] },
            set: { newValue in
                var options = entry.options
                options[keyPath: keyPath] = newValue
                manager.setOptions(entryID, options)
            })
    }

    private func open() { if let url = manager.url(for: entryID) { NSWorkspace.shared.open(url) } }

    private func copyURL() {
        guard let url = manager.url(for: entryID) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    private func relocate() {
        if let url = FolderPicker.pickFolders(allowsMultiple: false).first { manager.relocate(entryID, to: url) }
    }
}

enum FolderPicker {
    @MainActor static func pickFolders(allowsMultiple: Bool) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = allowsMultiple
        panel.prompt = "Serve"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
