import SwiftUI
import AppKit
import UniformTypeIdentifiers
import FolderServeCore

struct ActivityView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    @State private var filter: UUID?
    @State private var category: RequestCategory?
    /// Only requests whose status falls in this family (success, redirect, error).
    @State private var statusFilter: StatusFilter
    @State private var selectedID: UUID?
    /// Requests that no page made (DevTools or an extension re-fetching a file) are hidden unless switched on.
    @AppStorage("activityShowDetached") private var showDetached = false

    /// The hint that rows can be opened is shown until the user opens one (or dismisses it).
    @AppStorage("activityDetailHintSeen") private var hintSeen = false
    @State private var hoveredID: UUID?
    /// List the slowest requests first instead of the newest.
    @State private var slowestFirst: Bool
    @FocusState private var listFocused: Bool

    /// Text typed in the search field; every word must match a request for it to be listed.
    @State private var query: String

    init(initialSelection: UUID? = nil, initiallyHovered: UUID? = nil, initialQuery: String = "", initiallySlowestFirst: Bool = false,
         initialStatus: StatusFilter = .any) {
        _statusFilter = State(initialValue: initialStatus)
        _selectedID = State(initialValue: initialSelection)
        _hoveredID = State(initialValue: initiallyHovered)
        _query = State(initialValue: initialQuery)
        _slowestFirst = State(initialValue: initiallySlowestFirst)
    }

    /// Everything logged for the chosen server.
    private var allServerLines: [LogLine] { manager.logLines(for: filter) }
    private var detachedCount: Int { allServerLines.filter { $0.entry.isDetached }.count }
    /// Lines of the chosen server that are not hidden (the category chips count these).
    private var serverLines: [LogLine] { showDetached ? allServerLines : allServerLines.filter { !$0.entry.isDetached } }
    /// Lines of the chosen server that match the search (the category chips count these).
    private var searchedLines: [LogLine] { serverLines.filter { Self.matches($0.entry, query: query) } }
    /// What is listed: the chosen server, the search, the status family and the category.
    private var lines: [LogLine] {
        let listed = category.map { c in withStatus.filter { $0.entry.category == c } } ?? withStatus
        return Self.ordered(listed, slowestFirst: slowestFirst)
    }
    /// Search matches that also have the chosen status (the category chips count these).
    private var withStatus: [LogLine] { searchedLines.filter { statusFilter.matches(status: $0.entry.status) } }
    /// Search matches in the chosen category (the status chips count these).
    private var inCategory: [LogLine] { category.map { c in searchedLines.filter { $0.entry.category == c } } ?? searchedLines }
    /// The request that took longest in this list, when it is slow enough to deserve a marker.
    private var slowestID: UUID? { Self.slowestID(in: lines) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var selectedLine: LogLine? {
        guard let selectedID else { return nil }
        return manager.logLines(for: nil).first { $0.id == selectedID }
    }
    private func count(_ c: RequestCategory?) -> Int {
        guard let c else { return withStatus.count }
        return withStatus.filter { $0.entry.category == c }.count
    }
    private func count(_ f: StatusFilter) -> Int { inCategory.filter { f.matches(status: $0.entry.status) }.count }

    /// Title and controls. When the window is narrow the controls drop to their own row and shrink (icon-only buttons).
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { title; Spacer(minLength: 12); controls(compact: false) }
            VStack(alignment: .leading, spacing: 10) {
                title
                HStack(spacing: 10) { controls(compact: false) }
            }
            VStack(alignment: .leading, spacing: 10) {
                title
                HStack(spacing: 10) { controls(compact: true) }
            }
        }
    }

    private var title: some View {
        Text("Activity").font(.system(size: 30, weight: .bold, design: .rounded)).lineLimit(1).fixedSize()
    }

    @ViewBuilder private func controls(compact: Bool) -> some View {
        searchField(width: compact ? 150 : 220)
        sortMenu
        Picker("Server", selection: $filter) {
            Text("All servers").tag(UUID?.none)
            ForEach(manager.entries) { Text($0.displayName).tag(UUID?.some($0.id)) }
        }
        .frame(width: compact ? 150 : 200)
        Button { exportHAR() } label: { Label("Export", systemImage: "square.and.arrow.up") }
            .labelStyle(CompactLabelStyle(iconOnly: compact))
            .disabled(lines.isEmpty)
            .help("Save the listed requests, with their bodies where known, as a HAR file that browser DevTools can open")
        Button { manager.clearLog(for: filter); selectedID = nil } label: { Label("Clear", systemImage: "trash") }
            .labelStyle(CompactLabelStyle(iconOnly: compact))
            .disabled(allServerLines.isEmpty)
            .help(filter == nil ? "Clear the activity of all servers" : "Clear this server's activity")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            VStack(alignment: .leading, spacing: 8) {
                categoryChips
                statusChips
            }
            GeometryReader { geo in
                let selected = selectedLine
                if geo.size.width >= 760 {
                    let listWidth = selected == nil ? geo.size.width : geo.size.width - 16 - min(480, geo.size.width * 0.46)
                    HStack(alignment: .top, spacing: 16) {
                        listCard(width: listWidth).frame(minWidth: 340, maxHeight: .infinity, alignment: .top)
                        if let selected {
                            detail(selected).frame(width: min(480, geo.size.width * 0.46))
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                } else {
                    ZStack(alignment: .topLeading) {
                        listCard(width: geo.size.width).frame(maxHeight: .infinity, alignment: .top)
                        if let selected { detail(selected).transition(.opacity) }
                    }
                }
            }
            .animation(.smooth(duration: 0.25), value: selectedID)
        }
        .defaultFocus($listFocused, true)
        // The details belong to the list that was on screen: close them when the list changes.
        .onChange(of: category) { _, _ in selectedID = nil }
        .onChange(of: statusFilter) { _, _ in selectedID = nil }
        .onChange(of: filter) { _, _ in selectedID = nil }
        .onChange(of: query) { _, _ in selectedID = nil }
        .padding(28)
    }

    private func listCard(width: CGFloat) -> some View {
        Group {
            if lines.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 34, weight: .light))
                    Text(allServerLines.isEmpty ? "Requests will appear here as pages load."
                         : serverLines.isEmpty ? "Only requests from DevTools or extensions so far (hidden)."
                         : isSearching ? "No requests match “\(query.trimmingCharacters(in: .whitespaces))”."
                                             : "No \(category?.label ?? "") requests yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                VStack(spacing: 8) {
                    if !hintSeen { detailHint }
                    if isSnapshot {
                        rows(width: width)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView { rows(width: width) }
                                .onChange(of: selectedID) { _, id in
                                    if let id { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) } }
                                }
                        }
                    }
                }
            }
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow]) { press in
            move(press.key == .downArrow ? 1 : -1)
            return .handled
        }
        .card()
    }

    /// Selects the next (+1) or previous (-1) request in the list and shows its details.
    private func move(_ step: Int) {
        guard let id = Self.neighbor(of: selectedID, in: lines, step: step) else { return }
        selectedID = id
        hintSeen = true
    }

    /// The request `step` places after (or before) `id` in `lines`, stopping at the ends. With nothing selected, a step
    /// down gives the first request and a step up the last. Nil when the list is empty.
    static func neighbor(of id: UUID?, in lines: [LogLine], step: Int) -> UUID? {
        guard !lines.isEmpty else { return nil }
        guard let id, let index = lines.firstIndex(where: { $0.id == id }) else {
            return (step >= 0 ? lines.first : lines.last)?.id
        }
        return lines[min(max(index + step, 0), lines.count - 1)].id
    }

    /// Tells new users that a request can be opened; goes away for good once one is opened or it is dismissed.
    private var detailHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.click.2").foregroundStyle(Theme.accent)
            Text("Click a request, or use ↑ ↓, to see its headers, payload and response.").font(.callout)
            Spacer(minLength: 8)
            Button { hintSeen = true } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide this tip")
                .accessibilityLabel("Hide this tip")
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent.opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 0.5))
    }

    private func detail(_ line: LogLine) -> some View {
        RequestDetailView(line: line) { selectedID = nil }
    }

    /// Newest first (the default) or slowest first.
    @ViewBuilder private var sortMenu: some View {
        if isSnapshot {
            Label(slowestFirst ? "Slowest" : "Newest", systemImage: "arrow.up.arrow.down")   // ImageRenderer cannot draw a Menu
        } else {
            sortMenuControl
        }
    }

    private var sortMenuControl: some View {
        Menu {
            Picker("Sort by", selection: $slowestFirst) {
                Label("Newest first", systemImage: "clock").tag(false)
                Label("Slowest first", systemImage: "tortoise").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Label(slowestFirst ? "Slowest" : "Newest", systemImage: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help("Choose the order of the list")
    }

    /// Slowest first puts requests with a known time in front, longest first; the rest keep their order. Otherwise the order is unchanged.
    static func ordered(_ lines: [LogLine], slowestFirst: Bool) -> [LogLine] {
        guard slowestFirst else { return lines }
        return lines.enumerated().sorted { a, b in
            let (x, y) = (a.element.entry.durationMs ?? -1, b.element.entry.durationMs ?? -1)
            return x != y ? x > y : a.offset < b.offset
        }.map(\.element)
    }

    /// The longest request in `lines`, but only from `slowThreshold` up, and only when there is something to compare it with.
    static let slowThresholdMs = 300
    static func slowestID(in lines: [LogLine]) -> UUID? {
        guard lines.count > 1,
              let slowest = lines.max(by: { ($0.entry.durationMs ?? -1) < ($1.entry.durationMs ?? -1) }),
              let ms = slowest.entry.durationMs, ms >= slowThresholdMs else { return nil }
        return slowest.id
    }

    /// Asks where to save, then writes the listed requests (respecting the server, status, category and search) as a HAR file.
    private func exportHAR() {
        let listed = lines
        let paths = Dictionary(manager.entries.map { ($0.id, $0.folderPath) }, uniquingKeysWith: { first, _ in first })
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "har") ?? .json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "FolderServe-activity-\(Self.fileStamp(Date())).har"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Task.detached {
            do {
                let bodies = HARExport.gatherBodies(for: listed, folderPath: { paths[$0] })
                try HARExport.make(lines: listed, bodies: bodies, appVersion: version).write(to: url, options: .atomic)
                await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } catch {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "The HAR file could not be saved"
                    alert.informativeText = error.localizedDescription
                    alert.runModal()
                }
            }
        }
    }

    static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    /// Filters the list by method, path, status, note or type. Esc or × clears it.
    private func searchField(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if isSnapshot {
                Text(query.isEmpty ? "Search requests" : query).foregroundStyle(query.isEmpty ? .secondary : .primary)   // ImageRenderer cannot draw a TextField
                Spacer(minLength: 0)
            } else {
            TextField("Search requests", text: $query)
                .textFieldStyle(.plain)
                .onExitCommand { query = "" }
                .onKeyPress(.downArrow) {
                    listFocused = true
                    move(1)
                    return .handled
                }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Clear the search")
                    .accessibilityLabel("Clear the search")
            }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .help("Type words such as “post login 200”: a request is listed when each word matches its method, path, status, note or type")
    }

    /// True when every word of the query appears (any case) in the request's method, path, status, note or type.
    static func matches(_ entry: RequestLogEntry, query: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = "\(entry.method) \(entry.path) \(entry.status) \(entry.note ?? "") \(entry.category.label)".lowercased()
        return words.allSatisfy { haystack.contains($0) }
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
        pill(title, count: count(value), selected: category == value) { category = value }
    }

    /// Status families: All / Success / Redirects / Errors. They combine with the category chips and the search.
    private var statusChips: some View {
        FlowLayout(spacing: 8, rowSpacing: 8) {
            ForEach(StatusFilter.allCases, id: \.self) { f in
                pill(f.label, count: count(f), selected: statusFilter == f, tint: f == .errors ? Theme.failed : Theme.accent,
                     help: f.detail) { statusFilter = f }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pill(_ title: String, count n: Int, selected: Bool, tint: Color = Theme.accent, help: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(n)").font(.system(size: 11, weight: .medium, design: .monospaced)).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(selected ? 0.25 : 0.1)))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .fixedSize()
            .foregroundStyle(selected ? Color.white : Color.primary.opacity(n == 0 ? 0.4 : 0.85))
            .background(Capsule().fill(selected ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary.opacity(0.6))))
            .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.35 : 0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help(help ?? "")
        .animation(.smooth(duration: 0.2), value: selected)
        .accessibilityLabel("\(title), \(n) requests")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// What fits in a list of this width: the full row, one without clock time and type badge, or the bare minimum.
    private enum RowDetail { case full, medium, compact }
    private func rowDetail(for width: CGFloat) -> RowDetail {
        let usable = width - 40   // the card's padding
        return usable >= 620 ? .full : usable >= 400 ? .medium : .compact
    }

    private func rows(width: CGFloat) -> some View {
        let detail = rowDetail(for: width)
        return LazyVStack(spacing: 0) {
            ForEach(lines.prefix(200)) { line in
                let isSelected = line.id == selectedID
                HStack(spacing: 12) {
                    if detail == .full {
                        Text(line.entry.date, format: .dateTime.hour().minute().second())
                            .lineLimit(1).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                        Text(line.entry.category.label).font(.system(size: 10, weight: .semibold))
                            .lineLimit(1).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(.white.opacity(0.1)))
                            .frame(width: 70, alignment: .leading)
                    }
                    Text(line.entry.method).frame(width: 48, alignment: .leading)
                    Text(String(line.entry.status))
                        .foregroundStyle(color(for: line.entry.status)).frame(width: 40, alignment: .leading)
                    Text(line.entry.path).lineLimit(1).truncationMode(.middle).frame(minWidth: 60, alignment: .leading)
                    if let note = line.entry.note {
                        Text(note).foregroundStyle(Theme.accent).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if line.id == slowestID {
                        Image(systemName: "tortoise.fill").font(.system(size: 11))
                            .foregroundStyle(Self.durationColor(line.entry.durationMs))
                            .help("The slowest request in this list")
                            .accessibilityLabel("Slowest request")
                    }
                    if detail != .compact {
                        Text(ByteCountFormatter.string(fromByteCount: line.entry.bytes, countStyle: .file))
                            .lineLimit(1).fixedSize().foregroundStyle(.secondary)
                    }
                    Text(Self.durationText(line.entry.durationMs))
                        .lineLimit(1).foregroundStyle(Self.durationColor(line.entry.durationMs)).frame(width: 64, alignment: .trailing)
                        .help("Time the server took to answer")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary).opacity(isSelected || hoveredID == line.id ? 1 : 0.45)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.vertical, 5).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.accent.opacity(0.35) : hoveredID == line.id ? Color.white.opacity(0.08) : .clear))
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hoveredID = line.id } else if hoveredID == line.id { hoveredID = nil }
                }
                .handCursor()
                .help("Show request details")
                .onTapGesture { selectedID = isSelected ? nil : line.id; hintSeen = true; listFocused = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("\(line.entry.method) \(line.entry.path), status \(line.entry.status)")
            }
        }
    }

    /// "< 1 ms", "42 ms", "1.24 s"; a dash when the time is unknown.
    static func durationText(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        if ms < 1 { return "< 1 ms" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.2f s", Double(ms) / 1000)
    }

    /// Quiet when fast, amber from 300 ms, red from 1 s.
    static func durationColor(_ ms: Int?) -> Color {
        guard let ms else { return .secondary }
        if ms >= 1000 { return Theme.failed }
        if ms >= 300 { return Theme.warning }
        return .secondary
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


/// A label that shows only its icon when there is no room (the title stays as the accessibility label and tooltip).
private struct CompactLabelStyle: LabelStyle {
    let iconOnly: Bool
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly { configuration.icon } else { Label(configuration) }
    }
}
