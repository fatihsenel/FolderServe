import SwiftUI
import FolderServeCore

/// The less-used switches of a folder, grouped, each with a line saying what it does.
struct OptionsPopoverView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    let entryID: UUID
    @State private var openAt = ""
    @State private var openAtInvalid = false
    @FocusState private var openAtFocused: Bool

    private var entryName: String { manager.entries.first { $0.id == entryID }?.displayName ?? "folder" }
    private var options: ServeOptions { manager.entries.first { $0.id == entryID }?.options ?? ServeOptions() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            group("Serving")
            row("SPA mode", "Serve index.html for unknown paths so client-side routers work.", \.spaMode)
            row("Cache", "The browser re-checks files with an ETag for faster reloads. Live-reload pages are never cached.", \.caching)
            row("Name address", "Show and open this folder as \(HostSlug.make(entryName)).localhost instead of 127.0.0.1. Browsers and curl send *.localhost to this Mac.", \.friendlyHost)
            openAtRow
            group("Debugging").padding(.top, 8)
            delayRow
            row("Page console", "Show the pages' console errors, warnings and uncaught errors under Activity ▸ Console, also from a phone. Adds a small script to HTML pages.", \.captureConsole)
            group("Security").padding(.top, 8)
            row("HTTPS", "Serve over https:// with a self-signed localhost certificate. Your browser warns once.", \.https)
            row("CORS", "Lets pages from other origins read these files.", \.cors,
                warning: "Any website open in your browser can read the files served here.")
        }
        .padding(16)
        .frame(width: 340)
    }

    /// The page the Open button opens (the site root when empty).
    private var openAtRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Open at").font(.callout.weight(.medium))
            Text("The page the Open button and Recent folders open, such as /docs/index.html or /app?tab=2. Empty opens the site root.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if isSnapshot {
                Text(options.openPath.isEmpty ? "/" : options.openPath).font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25)))
            } else {
                TextField("/", text: $openAt).font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                    .focused($openAtFocused)
                    .onSubmit(commitOpenAt)
                    .onChange(of: openAtFocused) { _, focused in if !focused { commitOpenAt() } }
                    .onAppear { openAt = options.openPath }
                    .accessibilityLabel("Open at")
            }
            if openAtInvalid {
                Text("That is not a path on this server. Use something like /docs/index.html.")
                    .font(.caption).foregroundStyle(Theme.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }

    /// Slow network: hold every answer back by a chosen time. Drawn as buttons (ImageRenderer cannot draw a Picker).
    private var delayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text("Delay").font(.callout.weight(.medium))
                if options.effectiveDelayMs > 0 {
                    Image(systemName: "tortoise.fill").font(.system(size: 11)).foregroundStyle(Theme.warning).accessibilityLabel("Delay is on")
                }
            }
            Text("Wait before answering every request, to see spinners and loading states. Remember to switch it off.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                ForEach(ServeOptions.delayChoices, id: \.self) { ms in
                    let selected = options.effectiveDelayMs == ms
                    Button { var o = options; o.responseDelayMs = ms; manager.setOptions(entryID, o) } label: {
                        Text(ServeOptions.delayLabel(ms)).font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                            .background(Capsule().fill(selected ? AnyShapeStyle(ms == 0 ? Theme.accent : Theme.warning.opacity(0.85)) : AnyShapeStyle(.quaternary.opacity(0.6))))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delay \(ServeOptions.delayLabel(ms))")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func commitOpenAt() {
        guard let clean = BrowserOpener.normalizedPath(openAt) else { openAtInvalid = true; return }
        openAtInvalid = false
        openAt = clean
        guard clean != options.openPath else { return }
        var o = options; o.openPath = clean; manager.setOptions(entryID, o)
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
