import SwiftUI
import FolderServeCore

/// Sheet to change a captured request (method, address, headers, body) and send it to the server again.
/// The new request is logged in Activity like any other and carries the `X-FolderServe-Replay` header.
struct EditReplayView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSnapshotRendering) private var isSnapshot
    let line: LogLine
    /// Selects the request that was just sent in Activity.
    var onShow: ((UUID) -> Void)?

    enum SendState: Equatable {
        case idle, sending
        case done(status: Int, ms: Int, newID: UUID?)
        case failed(String)
    }

    @State private var draft: EditableRequest
    @State private var state: SendState

    init(line: LogLine, onShow: ((UUID) -> Void)? = nil, initialState: SendState = .idle) {
        self.line = line
        self.onShow = onShow
        _draft = State(initialValue: EditableRequest(entry: line.entry))
        _state = State(initialValue: initialState)
    }

    private var base: URL? { manager.url(for: line.serverID) }
    private var mono: Font { .system(size: 12, design: .monospaced) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Edit & Replay").font(.system(size: 20, weight: .bold, design: .rounded))
            requestLine
            headersSection
            if draft.hasBody { bodySection }
            statusLine
            HStack {
                Text(base == nil ? "Start the server to send." : "Sent to \(base?.absoluteString ?? "")")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button { send() } label: { Text(state == .sending ? "Sending…" : "Send") }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(base == nil || state == .sending)
                    .help("Send the edited request (⌘↩)")
            }
        }
        .padding(22)
        .frame(width: 600)
    }

    // MARK: Method and address

    private var requestLine: some View {
        HStack(spacing: 8) {
            if isSnapshot {
                standIn(draft.method, width: 96)
                standIn(draft.target, fill: true)
            } else {
                Picker("Method", selection: $draft.method) {
                    ForEach(EditableRequest.methods, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 96)
                .accessibilityLabel("Method")
                TextField("/path?query", text: $draft.target).font(mono).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Path and query")
            }
        }
    }

    // MARK: Headers

    private var headersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Headers").font(.system(size: 13, weight: .semibold))
                Text("(Host and Content-Length are set for you)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { draft.headers.append(.init(name: "", value: "")) } label: { Label("Add header", systemImage: "plus") }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent).handCursor()
            }
            if isSnapshot {
                VStack(spacing: 4) { ForEach(draft.headers) { h in headerRow(h) } }
            } else {
                ScrollView {
                    VStack(spacing: 4) { ForEach($draft.headers) { $h in headerRow($h) } }
                }
                .frame(minHeight: 60, maxHeight: 190)
            }
        }
    }

    /// Editable row (live) …
    private func headerRow(_ h: Binding<EditableRequest.Header>) -> some View {
        HStack(spacing: 6) {
            TextField("Name", text: h.name).font(mono).textFieldStyle(.roundedBorder).frame(width: 170)
            TextField("Value", text: h.value).font(mono).textFieldStyle(.roundedBorder)
            Button { draft.headers.removeAll { $0.id == h.wrappedValue.id } } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove this header").accessibilityLabel("Remove header")
        }
    }

    /// … and the drawn stand-in used for screenshots (ImageRenderer cannot draw text fields).
    private func headerRow(_ h: EditableRequest.Header) -> some View {
        HStack(spacing: 6) {
            standIn(h.name, width: 170)
            standIn(h.value, fill: true)
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
        }
    }

    // MARK: Body

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body").font(.system(size: 13, weight: .semibold))
            if let note = draft.bodyNote {
                Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warning)
            }
            if isSnapshot {
                standIn(draft.body, fill: true, height: 120, alignTop: true)
            } else {
                TextEditor(text: $draft.body).font(mono).frame(height: 120)
                    .scrollContentBackground(.hidden).padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25)))
                    .accessibilityLabel("Request body")
            }
        }
    }

    // MARK: Result

    @ViewBuilder private var statusLine: some View {
        switch state {
        case .idle: EmptyView()
        case .sending: Label("Sending…", systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning)
        case .done(let status, let ms, let newID):
            HStack(spacing: 10) {
                Label("Answered \(status) in \(ActivityView.durationText(ms))", systemImage: "checkmark")
                    .font(.caption).foregroundStyle(status >= 400 ? Theme.failed : Theme.running)
                if let newID, let onShow {
                    Button("Show in Activity") { onShow(newID); dismiss() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent).handCursor()
                }
            }
        }
    }

    // MARK: Sending

    private func send() {
        switch draft.urlRequest(base: base) {
        case .failure(let problem):
            state = .failed(problem.message)
        case .success(let request):
            state = .sending
            let known = Set(manager.log.map(\.id)), serverID = line.serverID, started = Date()
            Task {
                switch await RequestReplay.send(request) {
                case .success(let status):
                    let ms = Int(Date().timeIntervalSince(started) * 1000)
                    // The server logs the request on its own queue; give it a moment to show up.
                    var newID: UUID?
                    for _ in 0..<10 where newID == nil {
                        newID = manager.log.last { !known.contains($0.id) && $0.serverID == serverID && $0.entry.isReplay }?.id
                        if newID == nil { try? await Task.sleep(for: .milliseconds(100)) }
                    }
                    state = .done(status: status, ms: ms, newID: newID)
                case .failure(let error):
                    state = .failed("Could not send it: \(error.message)")
                }
            }
        }
    }

    private func standIn(_ text: String, width: CGFloat? = nil, fill: Bool = false, height: CGFloat? = nil, alignTop: Bool = false) -> some View {
        Text(text).font(mono).lineLimit(alignTop ? 6 : 1).truncationMode(.tail)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(width: width, height: height, alignment: alignTop ? .topLeading : .leading)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.25)))
    }
}
