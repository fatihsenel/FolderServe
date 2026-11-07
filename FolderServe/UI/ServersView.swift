import SwiftUI

struct ServersView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var isTargeted: Bool
    @State private var bursts: [DropBurst] = []

    private struct DropBurst: Identifiable { let id = UUID(); let point: CGPoint }

    init(initiallyTargeted: Bool = false) { _isTargeted = State(initialValue: initiallyTargeted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Servers").font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Button { addFolders() } label: { Label("Add Folder…", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.large)
            }
            if manager.entries.isEmpty {
                DropZoneView(isTargeted: isTargeted, addFolder: addFolders)
            } else {
                if isSnapshot {
                    cardList  // ImageRenderer cannot draw ScrollView content
                } else {
                    ScrollViewReader { proxy in
                        ScrollView { cardList }
                            .onChange(of: manager.lastHighlightedID) { _, id in
                                guard let id else { return }
                                withAnimation(.smooth(duration: 0.5)) { proxy.scrollTo(id, anchor: .center) }
                            }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .overlay {
            // The fade is scoped to the overlay, so showing it does not animate the card list underneath.
            ZStack {
                if isTargeted { DropOverlayView().transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.18), value: isTargeted)
        }
        .overlay { ForEach(bursts) { DropBurstView(point: $0.point) } }
        .modifier(FolderDropModifier(enabled: !isSnapshot, isTargeted: $isTargeted) { location in
            let burst = DropBurst(point: location)
            bursts.append(burst)
            DropFeedback.tap()
            Task { try? await Task.sleep(for: .seconds(1.1)); bursts.removeAll { $0.id == burst.id } }
        })
    }

    private var cardList: some View {
        VStack(spacing: 16) {
            ForEach(manager.entries) { entry in
                ServerCardView(entryID: entry.id)
                    .id(entry.id)
                    .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: -18)),
                                            removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
            Text("Drop more folders anywhere in this window")
                .font(.footnote).foregroundStyle(.secondary).padding(.top, 4)
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: manager.entries.map(\.id))
    }

    private func addFolders() {
        for url in FolderPicker.pickFolders(allowsMultiple: true) { manager.add(folder: url) }
    }
}

private struct FolderDropModifier: ViewModifier {
    @Environment(ServerManager.self) private var manager
    let enabled: Bool
    @Binding var isTargeted: Bool
    let onDrop: (CGPoint) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.dropDestination(for: URL.self) { urls, location in
                for url in urls { _ = manager.addDropped(url: url) }
                if !urls.isEmpty { onDrop(location) }
                return !urls.isEmpty
            } isTargeted: { isTargeted = $0 }
        } else {
            content
        }
    }
}
