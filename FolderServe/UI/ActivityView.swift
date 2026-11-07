import SwiftUI
import FolderServeCore

struct ActivityView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var filter: UUID?
    @State private var category: RequestCategory?
    @State private var selectedID: UUID?
    /// Requests that no page made (DevTools or an extension re-fetching a file) are hidden unless switched on.
    @AppStorage("activityShowDetached") private var showDetached = false

    init(initialSelection: UUID? = nil) { _selectedID = State(initialValue: initialSelection) }

    /// Everything logged for the chosen server.
    private var allServerLines: [LogLine] { manager.logLines(for: filter) }
    private var detachedCount: Int { allServerLines.filter { $0.entry.isDetached }.count }
    /// Lines of the chosen server that are not hidden (the category chips count these).
    private var serverLines: [LogLine] { showDetached ? allServerLines : allServerLines.filter { !$0.entry.isDetached } }
    /// What is listed: the chosen server and category.
    private var lines: [LogLine] {
        guard let category else { return serverLines }
        return serverLines.filter { $0.entry.category == category }
    }
    private var selectedLine: LogLine? {
        guard let selectedID else { return nil }
        return manager.logLines(for: nil).first { $0.id == selectedID }
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
                Button { manager.clearLog(for: filter); selectedID = nil } label: { Label("Clear", systemImage: "trash") }
                    .disabled(allServerLines.isEmpty)
                    .help(filter == nil ? "Clear the activity of all servers" : "Clear this server's activity")
            }
            categoryChips
            GeometryReader { geo in
                let selected = selectedLine
                if geo.size.width >= 760 {
                    HStack(alignment: .top, spacing: 16) {
                        listCard.frame(minWidth: 340, maxHeight: .infinity, alignment: .top)
                        if let selected {
                            detail(selected).frame(width: min(480, geo.size.width * 0.46))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                } else {
                    ZStack(alignment: .topLeading) {
                        listCard.frame(maxHeight: .infinity, alignment: .top)
                        if let selected { detail(selected).transition(.opacity) }
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: selectedID)
        }
        // The details belong to the list that was on screen: close them when the list changes.
        .onChange(of: category) { _, _ in selectedID = nil }
        .onChange(of: filter) { _, _ in selectedID = nil }
        .padding(28)
    }

    private var listCard: some View {
        Group {
            if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 34, weight: .light))
                    Text(allServerLines.isEmpty ? "Requests will appear here as pages load."
                         : serverLines.isEmpty ? "Only requests from DevTools or extensions so far (hidden)."
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
    }

    private func detail(_ line: LogLine) -> some View {
        RequestDetailView(line: line) { selectedID = nil }
    }

    private var categoryChips: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            chip("All", nil)
            ForEach(RequestCategory.allCases, id: \.self) { chip($0.label, $0) }
            if detachedCount > 0 { detachedToggle }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Switches the DevTools / extension requests on or off in the list.
    private var detachedToggle: some View {
        Button { showDetached.toggle(); selectedID = nil } label: {
            HStack(spacing: 6) {
                Image(systemName: showDetached ? "eye" : "eye.slash").font(.system(size: 11, weight: .semibold))
                Text(showDetached ? "Showing DevTools & extension requests" : "\(detachedCount) hidden: DevTools & extensions")
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6).fixedSize()
            .foregroundStyle(.secondary)
            .overlay(Capsule().strokeBorder(.white.opacity(0.2), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3])))
        }
        .buttonStyle(.plain)
        .help("Requests with no page behind them (no referer, Sec-Fetch-Site: none), such as DevTools re-fetching a file")
        .accessibilityLabel(showDetached ? "Hide DevTools and extension requests" : "Show \(detachedCount) hidden DevTools and extension requests")
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
                let isSelected = line.id == selectedID
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
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.35) : .clear))
                .contentShape(Rectangle())
                .onTapGesture { selectedID = isSelected ? nil : line.id }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(line.entry.method) \(line.entry.path), status \(line.entry.status)")
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
