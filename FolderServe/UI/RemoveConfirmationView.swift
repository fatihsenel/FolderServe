import SwiftUI
import FolderServeCore

/// Window-wide confirmation for removing a folder: dimmed backdrop and a centred card.
struct RemoveConfirmationView: View {
    let entry: ServerEntry
    let status: ServerStatus
    var kind: ProjectKind?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .onTapGesture(perform: onCancel)
            card
                .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                .offset(y: shown || reduceMotion ? 0 : 10)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { shown = true } }
        .onExitCommand(perform: onCancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(RemovalPrompt.title(for: entry))
        .accessibilityHint(RemovalPrompt.message(for: entry, status: status))
    }

    private var card: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.failed.opacity(0.22)).frame(width: 76, height: 76).blur(radius: 6)
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.45, blue: 0.5), Color(red: 0.85, green: 0.22, blue: 0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                Image(systemName: "trash.fill").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            }
            VStack(spacing: 4) {
                Text("Remove this folder?").font(.system(size: 21, weight: .bold, design: .rounded))
                Text("This only removes it from FolderServe.").font(.callout).foregroundStyle(.secondary)
            }
            folderChip
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(RemovalPrompt.consequences(for: entry, status: status).enumerated()), id: \.offset) { _, c in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: c.kind)).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color(for: c.kind)).frame(width: 22, height: 22)
                            .background(Circle().fill(color(for: c.kind).opacity(0.18)))
                        Text(c.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            HStack(spacing: 12) {
                Button(action: onCancel) { Text("Cancel").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).controlSize(.large).keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    Label("Remove", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.failed).controlSize(.large)
            }
        }
        .padding(26)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.17, green: 0.13, blue: 0.34), Color(red: 0.12, green: 0.09, blue: 0.26)],
                                     startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        .environment(\.colorScheme, .dark)
    }

    private var folderChip: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill").font(.system(size: 20)).foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName).font(.system(size: 15, weight: .semibold, design: .rounded)).lineLimit(1)
                    if let kind { ProjectBadge(kind: kind) }
                }
                Text(entry.folderPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }

    private func icon(for kind: RemovalPrompt.Consequence.Kind) -> String {
        switch kind {
        case .stops: "power"
        case .forgets: "gearshape.fill"
        case .safe: "checkmark.shield.fill"
        }
    }

    private func color(for kind: RemovalPrompt.Consequence.Kind) -> Color {
        switch kind {
        case .stops: Theme.failed
        case .forgets: Theme.warning
        case .safe: Theme.running
        }
    }
}
