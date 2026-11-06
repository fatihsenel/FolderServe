import SwiftUI

struct ActivityView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var filter: UUID?

    private var lines: [LogLine] { manager.logLines(for: filter) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Activity").font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                Picker("Server", selection: $filter) {
                    Text("All servers").tag(UUID?.none)
                    ForEach(manager.entries) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                .frame(width: 200)
            }
            Group {
                if lines.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 34, weight: .light))
                        Text("Requests will appear here as pages load.").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if isSnapshot {
                    rows
                } else {
                    ScrollView { rows }
                }
            }
            .card()
            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(lines.prefix(200)) { line in
                HStack(spacing: 12) {
                    Text(line.entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                    Text(line.entry.method).frame(width: 48, alignment: .leading)
                    Text(String(line.entry.status))
                        .foregroundStyle(color(for: line.entry.status)).frame(width: 40, alignment: .leading)
                    Text(line.entry.path).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(ByteCountFormatter.string(fromByteCount: line.entry.bytes, countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 5)
            }
        }
    }

    private func color(for status: Int) -> Color {
        switch status {
        case 200..<300: return Theme.running
        case 300..<400: return Theme.accent
        case 400..<500: return Theme.warning
        default: return Theme.failed
        }
    }
}
