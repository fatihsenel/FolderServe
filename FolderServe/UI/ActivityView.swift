import SwiftUI
import FolderServeCore

struct ActivityView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var filter: UUID?
    @State private var category: RequestCategory?

    /// Lines of the chosen server (the category chips count these).
    private var serverLines: [LogLine] { manager.logLines(for: filter) }
    /// What is listed: the chosen server and category.
    private var lines: [LogLine] {
        guard let category else { return serverLines }
        return serverLines.filter { $0.entry.category == category }
    }
    private func count(_ c: RequestCategory?) -> Int {
        guard let c else { return serverLines.count }
        return serverLines.filter { $0.entry.category == c }.count
    }

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
                Button { manager.clearLog(for: filter) } label: { Label("Clear", systemImage: "trash") }
                    .disabled(serverLines.isEmpty)
                    .help(filter == nil ? "Clear the activity of all servers" : "Clear this server's activity")
            }
            categoryChips
            Group {
                if lines.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg").font(.system(size: 34, weight: .light))
                        Text(serverLines.isEmpty ? "Requests will appear here as pages load."
                                                 : "No \(category?.label ?? "") requests yet.")
                            .foregroundStyle(.secondary)
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

    private var categoryChips: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            chip("All", nil)
            ForEach(RequestCategory.allCases, id: \.self) { chip($0.label, $0) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ title: String, _ value: RequestCategory?) -> some View {
        let selected = category == value
        let n = count(value)
        return Button { category = value } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(n)").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(selected ? 0.25 : 0.1)))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .fixedSize()
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(n == 0 ? 0.4 : 0.85))
            .background(Capsule().fill(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.quaternary.opacity(0.6))))
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.35 : 0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: selected)
        .accessibilityLabel("\(title), \(n) requests")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var rows: some View {
        LazyVStack(spacing: 0) {
            ForEach(lines.prefix(200)) { line in
                HStack(spacing: 12) {
                    Text(line.entry.date, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                    Text(line.entry.category.label).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.1)))
                        .frame(width: 70, alignment: .leading)
                    Text(line.entry.method).frame(width: 48, alignment: .leading)
                    Text(String(line.entry.status))
                        .foregroundStyle(color(for: line.entry.status)).frame(width: 40, alignment: .leading)
                    Text(line.entry.path).lineLimit(1).truncationMode(.middle)
                    if let note = line.entry.note {
                        Text(note).foregroundStyle(Theme.accent).lineLimit(1).truncationMode(.middle)
                    }
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
