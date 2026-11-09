import SwiftUI

struct MainWindow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @Environment(ServerManager.self) private var manager
    @State private var selection: SidebarItem

    init(initialSelection: SidebarItem = .servers) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
            VStack(spacing: 0) {
                UpdateBannerHost().padding(.horizontal, 28).padding(.top, 12)
                Group {
                    switch selection {
                    case .servers: ServersView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 12)
            }
        }
        .background(Theme.background(scheme).ignoresSafeArea())
        .frame(minWidth: 860, minHeight: 560)
        .overlay {
            ZStack {
                if let id = manager.pendingRemoval, let entry = manager.entries.first(where: { $0.id == id }) {
                    RemoveConfirmationView(entry: entry, status: manager.statuses[id] ?? .stopped, kind: manager.projectKinds[id],
                                           onCancel: { manager.cancelRemoval() }, onConfirm: { manager.confirmRemoval() })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: manager.pendingRemoval)
        }
        .onAppear { if manager.activityRequest != nil { selection = .activity } }
        .onChange(of: manager.activityRequest) { if manager.activityRequest != nil { selection = .activity } }
        .background { if !isSnapshot { WindowReader { SplashGate.shared.hideIfNeeded($0) } } }
    }
}
