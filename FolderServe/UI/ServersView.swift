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
                AddFolderButton(action: addFolders)
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


/// The main screen's "Add Folder…" button: on hover it grows a little, glows and turns its plus; on press it dips.
struct AddFolderButton: View {
    let action: () -> Void
    @State private var hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(action: @escaping () -> Void, initiallyHovering: Bool = false) {
        self.action = action
        _hovering = State(initialValue: initiallyHovering)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                    .rotationEffect(.degrees(hovering && !reduceMotion ? 90 : 0))
                Text("Add Folder…").font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                LinearGradient(colors: [Theme.accent.opacity(hovering ? 1 : 0.88), Theme.accent.opacity(hovering ? 0.82 : 0.70)],
                               startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(hovering ? 0.5 : 0.2), lineWidth: 1))
            .shadow(color: Theme.accent.opacity(hovering ? 0.65 : 0), radius: 14, y: 4)
        }
        .buttonStyle(AddFolderButtonStyle(hovering: hovering, reduceMotion: reduceMotion))
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .animation(reduceMotion ? .none : .spring(response: 0.3, dampingFraction: 0.62), value: hovering)
        .accessibilityLabel("Add folder")
    }
}

private struct AddFolderButtonStyle: ButtonStyle {
    let hovering: Bool
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : configuration.isPressed ? 0.96 : hovering ? 1.06 : 1)
            .animation(reduceMotion ? .none : .snappy(duration: 0.16), value: configuration.isPressed)
    }
}
