import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(ServerManager.self) private var manager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var showSplash = SplashSettings.enabled
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @AppStorage(BrowserOpener.defaultsKey) private var browserID = ""
    @State private var browsers = BrowserOpener.installed()

    /// The title and the note below stay put; only the list of settings scrolls, inside its card, when the window is too short
    /// for it (an update notice above takes room too). Before, the rows were squeezed: descriptions cut to "…" and the notice
    /// pushed out of the window.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 30, weight: .bold, design: .rounded))
            ViewThatFits(in: .vertical) {
                rows.card()
                scrollingRows.card()
            }
            Text("Servers listen on 127.0.0.1 only, so other devices cannot reach them — unless you turn on Share for a folder.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var scrollingRows: some View {
        if isSnapshot {
            // ImageRenderer does not draw ScrollView content. An overlay takes no room of its own, like a scroll view,
            // so screenshots show the list as if scrolled to the top.
            Color.clear.overlay(alignment: .top) { rows }.clipped()
        } else {
            ScrollView { rows.padding(.trailing, 6) }
        }
    }

    private var rows: some View {
        @Bindable var manager = manager
        return VStack(alignment: .leading, spacing: 18) {
            SettingRow(title: "Start servers at launch",
                       detail: "Servers that were running when you quit start again automatically. Folders marked “Always start at launch” start regardless.",
                       isOn: $manager.startServersAtLaunch)
            Divider().opacity(0.4)
            SettingRow(title: "Serve dotfiles",
                       detail: "Allow files like .env and .git to be served. Applies to every folder; off is safer.",
                       isOn: Binding(get: { manager.serveDotfiles }, set: { manager.setServeDotfiles($0) }))
            Divider().opacity(0.4)
            SettingRow(title: "Launch at login",
                       detail: loginError ?? "Open FolderServe when you sign in to your Mac.",
                       isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            Divider().opacity(0.4)
            browserRow
            #if !APPSTORE
            Divider().opacity(0.4)
            UpdateSettingsRow()
            #endif
            Divider().opacity(0.4)
            SettingRow(title: "Show splash screen",
                       detail: "A short animation when the app opens. Skipped when launched at login.",
                       isOn: Binding(get: { showSplash }, set: { showSplash = $0; SplashSettings.enabled = $0 }))
            Button("Preview splash screen") { SplashController.shared.show() }
                .controlSize(.small)
        }
    }

    /// Which browser the Open buttons use. A browser that was uninstalled since falls back to the system default.
    private var browserRow: some View {
        let chosen = browsers.contains { $0.id == browserID } ? browserID : ""
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open pages in").font(.system(size: 15, weight: .semibold))
                Text("The browser used by Open, Recent folders and files opened with FolderServe. “System default” follows your Mac's setting.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isSnapshot {
                Text(browsers.first { $0.id == chosen }?.name ?? "System default").font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.1)))
            } else {
                Picker("Open pages in", selection: Binding(get: { chosen }, set: { browserID = $0 })) {
                    Text("System default").tag("")
                    ForEach(browsers) { Text($0.name).tag($0.id) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct SettingRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(GlowToggleStyle())
        }
    }
}

#if DEBUG
#Preview { SettingsView().environment(PreviewData.manager(populated: false)) }
#endif

/// Settings: the on/off switch, "Check now" and what the last check found.
private struct UpdateSettingsRow: View {
    @Environment(\.updates) private var updates
    @AppStorage(UpdateChecker.enabledKey) private var enabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingRow(title: "Check for updates",
                       detail: "Once a day FolderServe asks GitHub whether a newer release exists. Nothing about you or your folders is sent, and nothing is installed for you.",
                       isOn: $enabled)
            if let updates {
                HStack(spacing: 10) {
                    Button("Check now") { Task { await updates.checkNow() } }
                        .controlSize(.small).disabled(updates.state == .checking)
                    Text(UpdateStatusText.make(updates.state, current: updates.currentVersion)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

}
