import SwiftUI
import FolderServeCore

/// The less-used switches of a folder, grouped, each with a line saying what it does.
struct OptionsPopoverView: View {
    @Environment(ServerManager.self) private var manager
    let entryID: UUID

    private var options: ServeOptions { manager.entries.first { $0.id == entryID }?.options ?? ServeOptions() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            group("Serving")
            row("SPA mode", "Serve index.html for unknown paths so client-side routers work.", \.spaMode)
            row("Cache", "The browser re-checks files with an ETag for faster reloads. Live-reload pages are never cached.", \.caching)
            group("Security").padding(.top, 8)
            row("HTTPS", "Serve over https:// with a self-signed localhost certificate. Your browser warns once.", \.https)
            row("CORS", "Lets pages from other origins read these files.", \.cors,
                warning: "Any website open in your browser can read the files served here.")
        }
        .padding(16)
        .frame(width: 340)
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func row(_ title: String, _ detail: String, _ keyPath: WritableKeyPath<ServeOptions, Bool>,
                     warning: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.callout.weight(.medium))
                    if warning != nil, options[keyPath: keyPath] {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                            .accessibilityLabel("Warning")
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let warning, options[keyPath: keyPath] {
                    Text(warning).font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(isOn: Binding(
                get: { options[keyPath: keyPath] },
                set: { value in var o = options; o[keyPath: keyPath] = value; manager.setOptions(entryID, o) })) { EmptyView() }
                .toggleStyle(GlowToggleStyle()).fixedSize()
                .accessibilityLabel(title)
        }
        .padding(.vertical, 6)
    }
}

/// Small pill shown next to a folder's name for an option worth seeing at a glance.
struct OptionBadge: View {
    let text: String
    var warning = false
    var body: some View {
        Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(warning ? Theme.warning : .secondary)
            .background(Capsule().fill((warning ? Theme.warning : Color.white).opacity(0.14)))
            .accessibilityLabel(text)
    }
}
