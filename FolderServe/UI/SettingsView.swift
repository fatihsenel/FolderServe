import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(ServerManager.self) private var manager
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var showSplash = SplashSettings.enabled

    var body: some View {
        @Bindable var manager = manager
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 30, weight: .bold, design: .rounded))
            VStack(alignment: .leading, spacing: 18) {
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
                SettingRow(title: "Show splash screen",
                           detail: "A short animation when the app opens. Skipped when launched at login.",
                           isOn: Binding(get: { showSplash }, set: { showSplash = $0; SplashSettings.enabled = $0 }))
                Button("Preview splash screen") { SplashController.shared.show() }
                    .controlSize(.small)
            }
            .card()
            Text("Servers listen on 127.0.0.1 only, so other devices cannot reach them — unless you turn on Share for a folder.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(GlowToggleStyle())
        }
    }
}

#if DEBUG
#Preview { SettingsView().environment(PreviewData.manager(populated: false)) }
#endif
