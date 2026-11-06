import SwiftUI

struct ServersView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Servers").font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button { addFolders() } label: { Label("Add Folder…", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
            }
            if let notice = manager.notice {
                HStack {
                    Label(notice, systemImage: "info.circle.fill")
                    Spacer()
                    Button { manager.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(12)
                .background(Theme.warning.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if manager.entries.isEmpty {
                DropZoneView(isTargeted: isTargeted, addFolder: addFolders)
            } else {
                if isSnapshot {
                    cardList  // ImageRenderer cannot draw ScrollView content
                } else {
                    ScrollView { cardList }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .overlay {
            if isTargeted && !manager.entries.isEmpty {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 3).padding(10).allowsHitTesting(false)
            }
        }
        .modifier(FolderDropModifier(enabled: !isSnapshot, isTargeted: $isTargeted))
    }

    private var cardList: some View {
        VStack(spacing: 16) {
            ForEach(manager.entries) { ServerCardView(entryID: $0.id) }
            Text("Drop more folders anywhere in this window")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    private func addFolders() {
        for url in FolderPicker.pickFolders(allowsMultiple: true) { manager.add(folder: url) }
    }
}

private struct FolderDropModifier: ViewModifier {
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
