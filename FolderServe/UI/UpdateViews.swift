import SwiftUI
import AppKit

// The update checker is optional in the environment (previews and tests need not provide one).
private struct UpdateCheckerKey: EnvironmentKey { static let defaultValue: UpdateChecker? = nil }

extension EnvironmentValues {
    var updates: UpdateChecker? {
        get { self[UpdateCheckerKey.self] }
        set { self[UpdateCheckerKey.self] = newValue }
    }
}

/// "FolderServe 0.2.0 is available" with a Download button and the Homebrew command.
struct UpdateBanner: View {
    let release: LatestRelease
    let current: AppVersion
    var onDownload: () -> Void = {}
    var onCopyBrew: () -> Void = {}
    var onClose: () -> Void = {}
    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 18))
            VStack(alignment: .leading, spacing: 1) {
                Text("FolderServe \(release.version) is available").font(.system(size: 13, weight: .semibold))
                Text("You have \(current) · Homebrew: \(UpdateChecker.brewCommand)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Copy brew command") { onCopyBrew(); copied = true }
                .buttonStyle(.plain).font(.caption).foregroundStyle(copied ? Theme.running : .secondary)
            Button("Download") { onDownload() }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide until a newer version appears")
                .accessibilityLabel("Hide this update notice")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// The banner wired to the checker: opens the release page and copies the brew command.
struct UpdateBannerHost: View {
    @Environment(\.updates) private var updates

    var body: some View {
        if let updates, let release = updates.bannerRelease {
            UpdateBanner(release: release, current: updates.currentVersion,
                         onDownload: { NSWorkspace.shared.open(release.url) },
                         onCopyBrew: {
                             NSPasteboard.general.clearContents()
                             NSPasteboard.general.setString(UpdateChecker.brewCommand, forType: .string)
                         },
                         onClose: { updates.dismissBanner() })
        }
    }
}

/// The result of "Check for Updates…" in the app menu, as an alert.
@MainActor
enum UpdatePrompt {
    static func checkAndShow(_ updates: UpdateChecker) async {
        let state = await updates.checkNow()
        let alert = NSAlert()
        switch state {
        case .available(let release):
            alert.messageText = "FolderServe \(release.version) is available"
            alert.informativeText = "You have \(updates.currentVersion). Download it from GitHub, or run \(UpdateChecker.brewCommand) if you installed with Homebrew."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) }
            return
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = "Could not check for updates"
            alert.informativeText = message
        default:
            alert.messageText = "FolderServe is up to date"
            alert.informativeText = "You have version \(updates.currentVersion), the latest release."
        }
        alert.runModal()
    }
}
