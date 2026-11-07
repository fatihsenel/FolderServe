import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case servers = "Servers", activity = "Activity", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .servers: return "server.rack"
        case .activity: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }
}

struct SidebarView: View {
    @Environment(ServerManager.self) private var manager
    @Binding var selection: SidebarItem

    private var runningCount: Int {
        manager.statuses.values.filter { if case .running = $0 { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage()).resizable().frame(width: 38, height: 38)
                Text("FolderServe").font(.system(size: 16, weight: .semibold, design: .rounded))
            }
            .padding(.bottom, 18)
            ForEach(SidebarItem.allCases) { item in
                Button { selection = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(selection == item ? Color.white.opacity(0.16) : .clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(runningCount > 0 ? Theme.running : Theme.stopped).frame(width: 8, height: 8)
                Text(runningCount == 0 ? "Nothing running" : "\(runningCount) running")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 44)
        .padding(.bottom, 20)
        .frame(width: 210)
        .background(.ultraThinMaterial)
    }
}
