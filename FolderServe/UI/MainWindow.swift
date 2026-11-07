import SwiftUI

struct MainWindow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var selection: SidebarItem

    init(initialSelection: SidebarItem = .servers) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)
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
        .background(Theme.background(scheme).ignoresSafeArea())
        .frame(minWidth: 860, minHeight: 560)
        .background { if !isSnapshot { WindowReader { SplashGate.shared.hideIfNeeded($0) } } }
    }
}
