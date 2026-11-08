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
                            title(for: entry)
                            if let kind = manager.projectKinds[entryID] { ProjectBadge(kind: kind) }
                            if entry.options.https { OptionBadge(text: "HTTPS") }
                            if entry.options.cors { OptionBadge(text: "CORS", warning: true).help("CORS is on: any website open in your browser can read the files served here.") }
                            if entry.startsAlways {
                                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                                    .help("Always starts when FolderServe opens")
                                    .accessibilityLabel("Always starts at launch")
                            }
                        }
                        Text(entry.folderPath).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        statusLine
                    }
                    Spacer(minLength: 12)
                    RoundActionButton(isRunning: isRunning, isBusy: status == .folderMissing || isFinding) {
                        isRunning ? manager.stop(entryID) : manager.start(entryID)
                    }
                }
                Divider().opacity(0.4)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 18) {
                        togglesGroup(entry)
                        Spacer(minLength: 8)
                        buttonsGroup(entry)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 18) { togglesGroup(entry) }
                        HStack(spacing: 10) { Spacer(minLength: 0); buttonsGroup(entry) }
                    }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .card()
            .justAddedGlow(manager.highlightedIDs.contains(entryID))
        }
    }


    @ViewBuilder private func togglesGroup(_ entry: ServerEntry) -> some View {
        Toggle("Live reload", isOn: binding(\.liveReload, entry)).toggleStyle(GlowToggleStyle()).fixedSize()
        HStack(spacing: 4) {
            Toggle("Share", isOn: binding(\.shareOnNetwork, entry)).toggleStyle(GlowToggleStyle()).fixedSize()
                .help("Make this folder reachable from other devices on your network (phone, tablet). Shows a QR code when running.")
            if entry.options.shareOnNetwork {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                    .foregroundStyle(Theme.warning)
                    .help("Sharing is on: anyone on your network can open this folder (and use its proxy rules). Turn it off when you are done.")
                    .accessibilityLabel("Warning: reachable by everyone on your network")
            }
        }
    }

    @ViewBuilder private func buttonsGroup(_ entry: ServerEntry) -> some View {
        Group {
            Button { showingProxy = true } label: {
                let n = entry.options.proxyRules.count
                Label(n == 0 ? "Proxy" : "Proxy · \(n)", systemImage: "arrow.triangle.swap")
            }
            .help("Forward /api-style requests to another server (no CORS errors)")
            .popover(isPresented: $showingProxy, arrowEdge: .bottom) {
                ProxyEditorView(entryID: entryID, initialRules: entry.options.proxyRules)
            }
            Button { showingOptions = true } label: {
                let n = entry.options.enabledExtrasCount
                Label(n == 0 ? "Options" : "Options · \(n)", systemImage: "slider.horizontal.3")
            }
            .help("SPA mode, Cache, HTTPS, CORS")
            .popover(isPresented: $showingOptions, arrowEdge: .bottom) { OptionsPopoverView(entryID: entryID) }
            Button { open() } label: { Label("Open", systemImage: "safari") }.disabled(!isRunning)
            if status != .folderMissing {
                Button { FinderReveal.reveal(path: entry.folderPath) } label: { Label("Finder", systemImage: "folder") }
                    .help("Show this folder in Finder")
            }
            Button(role: .destructive) { manager.requestRemoval(entryID) } label: { Image(systemName: "trash") }
                .help("Remove this folder")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .fixedSize()
    }

    @State private var isEditing = false
    @State private var draft = ""
    @State private var hoveringTitle = false
    @State private var cancelled = false
    @FocusState private var titleFocused: Bool
    @State private var showingProxy = false
    @State private var showingShare = false
    @State private var showingOptions = false
    @State private var outsideClick = OutsideClickMonitor()

    @ViewBuilder private func title(for entry: ServerEntry) -> some View {
        if isEditing {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 1.5))
                .frame(maxWidth: 320)
                .focused($titleFocused)
                .onSubmit { commitRename() }
                .onExitCommand { cancelled = true; isEditing = false }
                .onChange(of: titleFocused) { _, focused in if !focused && isEditing { commitRename() } }
                .onAppear {
                    titleFocused = true
                    outsideClick.start { commitRename() }
                }
                .onDisappear { outsideClick.stop() }
        } else {
            HStack(spacing: 6) {
                Text(entry.displayName).font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Button { beginRename(entry) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(hoveringTitle ? 0.95 : 0.6))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(hoveringTitle ? 0.22 : 0.1)))
                        .overlay(Circle().strokeBorder(.white.opacity(hoveringTitle ? 0.35 : 0.18), lineWidth: 0.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Rename (label only — the folder on disk is not changed)")
                .accessibilityLabel("Rename \(entry.displayName)")
            }
            .contentShape(Rectangle())
            .onHover { hoveringTitle = $0 }
            .onTapGesture(count: 2) { beginRename(entry) }
            .contextMenu {
                if status != .folderMissing { Button("Show in Finder") { FinderReveal.reveal(path: entry.folderPath) } }
                Button("Rename…") { beginRename(entry) }
                Button { manager.setAlwaysStart(entryID, !entry.startsAlways) } label: {
                    if entry.startsAlways { Label("Always start at launch", systemImage: "checkmark") } else { Text("Always start at launch") }
                }
                if entry.customName != nil { Button("Use folder name") { manager.rename(entryID, to: "") } }
            }
        }
    }

    private func beginRename(_ entry: ServerEntry) {
        draft = entry.displayName
        cancelled = false
        isEditing = true
    }

    private func commitRename() {
        guard isEditing else { return }
        isEditing = false
        if !cancelled { manager.rename(entryID, to: draft) }
    }

    private var isRunning: Bool { if case .running = status { return true } else { return false } }
    private var isFinding: Bool { if case .finding = status { return true } else { return false } }

    private var statusIcon: some View {
        ZStack {
            Circle().fill(Theme.statusColor(status).opacity(0.35)).blur(radius: 14).frame(width: 64, height: 64)
            Circle().fill(.ultraThinMaterial).frame(width: 56, height: 56)
                .overlay(Circle().strokeBorder(Theme.statusColor(status).opacity(0.8), lineWidth: 2))
            Image(systemName: "folder.fill").font(.system(size: 24))
                .foregroundStyle(Theme.statusColor(status))
                .symbolEffect(.pulse, isActive: isFinding)
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .finding(let search):
            PortScanView(search: search)
        case .running(let port):
            HStack(spacing: 8) {
                Button { open() } label: {
                    Text(manager.url(for: entryID)?.absoluteString ?? "http://127.0.0.1:\(String(port))/").font(.system(.callout, design: .monospaced))
                }.buttonStyle(.link)
                Button { copyURL() } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)) }
                    .buttonStyle(.borderless).help("Copy URL").accessibilityLabel("Copy URL")
                if entry?.options.shareOnNetwork == true {
                    Button { showingShare = true } label: { Image(systemName: "qrcode").font(.system(size: 13)) }
                        .buttonStyle(.borderless).help("Open this folder on your phone").accessibilityLabel("Show QR code")
                        .popover(isPresented: $showingShare, arrowEdge: .bottom) { SharePopoverView(entryID: entryID) }
                }
            }
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

/// Calls `onOutsideClick` when the mouse goes down anywhere except inside a text field being edited.
/// (SwiftUI does not drop text-field focus when a plain background is clicked on macOS.)
@MainActor
final class OutsideClickMonitor {
    private var token: Any?

    func start(_ onOutsideClick: @escaping () -> Void) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            let hit = event.window?.contentView?.hitTest(event.locationInWindow)
            let insideField = (hit as? NSText)?.isFieldEditor == true || hit is NSTextField
            if !insideField { DispatchQueue.main.async { onOutsideClick() } }
            return event   // let the click carry on (buttons still work)
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    deinit { if let token { NSEvent.removeMonitor(token) } }
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

    /// Asks for folders and starts serving each one (the Add Folder button, the menu bar and ⌘O all use this).
    @MainActor static func addFolders(to manager: ServerManager) {
        for url in pickFolders(allowsMultiple: true) { manager.add(folder: url) }
    }
}
