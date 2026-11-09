import SwiftUI
import AppKit
import FolderServeCore

/// What served pages wrote to their console (errors, warnings, uncaught errors), newest first. Shown under Activity ▸ Console.
struct ConsoleView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    /// nil: all servers.
    let serverID: UUID?

    private var lines: [ConsoleLine] { manager.consoleLines(for: serverID) }
    /// Servers (of the ones listed) that have the option on.
    private var capturing: Bool {
        manager.entries.contains { (serverID == nil || $0.id == serverID) && $0.options.captureConsole }
    }

    var body: some View {
        Group {
            if lines.isEmpty {
                empty
            } else if isSnapshot {
                rows   // ImageRenderer does not draw ScrollView content
            } else {
                ScrollView { rows }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal").font(.system(size: 34, weight: .light))
            Text(capturing ? "Nothing in the console yet" : "Page console is off").font(.headline)
            Text(capturing
                 ? "Errors, warnings and uncaught errors from the pages of this server appear here. Reload the page once after switching the option on."
                 : "Turn on Options ▸ Page console on a server's card to see its pages' console errors, warnings and uncaught errors here, also from a phone.")
                .font(.callout).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(20)
    }

    private var rows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Self.timeText(line.message.date)).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Text(line.message.level.label).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .foregroundStyle(Self.color(line.message.level))
                        .background(Capsule().fill(Self.color(line.message.level).opacity(0.16)))
                        .frame(width: 74, alignment: .leading)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.message.text).lineLimit(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Text(Self.origin(of: line, serverName: serverName(line.serverID), showServer: serverID == nil))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Button { copy(line.message.text) } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Copy this message")
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider().opacity(0.4)
            }
        }
    }

    private func serverName(_ id: UUID) -> String { manager.entries.first { $0.id == id }?.displayName ?? "removed server" }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func color(_ level: ConsoleMessage.Level) -> Color { level == .warn ? Theme.warning : Theme.failed }

    /// "portfolio-site · /orders/7", or only the page when one server is listed.
    static func origin(of line: ConsoleLine, serverName: String, showServer: Bool) -> String {
        let page = line.message.page.isEmpty ? "/" : line.message.page
        return showServer ? "\(serverName) · \(page)" : page
    }

    static func timeText(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
