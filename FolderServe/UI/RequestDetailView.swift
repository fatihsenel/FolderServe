import SwiftUI
import AppKit
import CoreText
import FolderServeCore

/// What is shown for the response of one logged request.
struct LoadedContent: Equatable {
    var data: Data?
    var totalSize: Int64?
    var truncated = false
    /// Why there is nothing (or something different) to show.
    var note: String?
}

enum DetailTab: String, CaseIterable, Identifiable {
    case headers = "Headers", payload = "Payload", preview = "Preview", response = "Response"
    var id: String { rawValue }
}

/// Side panel with the details of one request, in the style of browser dev tools.
struct RequestDetailView: View {
    @Environment(ServerManager.self) private var manager
    @Environment(\.isSnapshotRendering) private var isSnapshot
    let line: LogLine
    var initialTab: DetailTab = .headers
    var preloaded: LoadedContent?
    let onClose: () -> Void

    @State private var tab: DetailTab
    @State private var content: LoadedContent?

    init(line: LogLine, initialTab: DetailTab = .headers, preloaded: LoadedContent? = nil, onClose: @escaping () -> Void) {
        self.line = line
        self.initialTab = initialTab
        self.preloaded = preloaded
        self.onClose = onClose
        _tab = State(initialValue: initialTab)
        _content = State(initialValue: preloaded)
    }

    private var entry: RequestLogEntry { line.entry }
    private var hasRequestBody: Bool { entry.requestBody != nil || ["POST", "PUT", "PATCH", "DELETE"].contains(entry.method) }
    private var tabs: [DetailTab] { hasRequestBody ? DetailTab.allCases : DetailTab.allCases.filter { $0 != .payload } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("", selection: $tab) { ForEach(tabs) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden()
            Group {
                if isSnapshot { tabBody } else { ScrollView { tabBody.frame(maxWidth: .infinity, alignment: .leading) } }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .onExitCommand(perform: onClose)
        .task(id: line.id) { if preloaded == nil { content = await loadContent() } }
        .onChange(of: line.id) { _, _ in tab = initialTab; if tab == .payload && !hasRequestBody { tab = .headers } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                HStack(spacing: 8) {
                    Text(String(entry.status)).font(.system(size: 13, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(statusColor.opacity(0.2))).foregroundStyle(statusColor)
                    Text(entry.method).font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Text(entry.category.label).font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.1)))
                }
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help("Close (Esc)").keyboardShortcut(.cancelAction)
            }
            Text(entry.url.isEmpty ? entry.path : entry.url)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .lineLimit(3).truncationMode(.middle)
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case 200..<300: Theme.running
        case 300..<400: Theme.accent
        case 400..<500: Theme.warning
        default: Theme.failed
        }
    }

    // MARK: Tabs

    @ViewBuilder private var tabBody: some View {
        switch tab {
        case .headers: headersTab
        case .payload: payloadTab
        case .preview: previewTab
        case .response: responseTab
        }
    }

    private var headersTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            section("General", rows: general)
            section("Response headers (\(entry.responseHeaders.count))", rows: entry.responseHeaders.map { ($0.name, $0.value) })
            section("Request headers (\(entry.requestHeaders.count))", rows: entry.requestHeaders.map { ($0.name, $0.value) })
        }
    }

    private var general: [(String, String)] {
        var rows: [(String, String)] = [
            ("Request URL", entry.url.isEmpty ? entry.path : entry.url),
            ("Method", entry.method),
            ("Status", "\(entry.status) \(HTTPStatus.reason(entry.status))".trimmingCharacters(in: .whitespaces)),
            ("Size", ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)),
        ]
        rows.append(("Started", entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))))
        if let ms = entry.durationMs { rows.append(("Took", ms < 1 ? "< 1 ms" : "\(ms) ms")) }
        if let up = entry.upstreamURL { rows.append(("Forwarded to", up)) }
        if let file = entry.servedFile { rows.append(("Served from", file)) }
        if entry.rewritten { rows.append(("Note", "The proxy address was replaced in this file when it was served.")) }
        return rows
    }

    private func section(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if rows.count > 1 { copyButton(rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n")) }
            }
            if rows.isEmpty { Text("None").font(.callout).foregroundStyle(.secondary) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.0).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Text(row.1).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var payloadTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let body = entry.requestBody {
                let type = entry.requestHeaders.first { $0.name == "content-type" }?.value
                bodyText(Self.displayText(body, contentType: type), truncated: entry.requestBodyTruncated, copyable: true)
            } else if entry.bodiesDropped {
                info("The body was dropped to keep memory use low.")
            } else {
                info("This request has no body.")
            }
        }
    }

    private var responseTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let content, let data = content.data {
                if Self.isText(data, contentType: entry.responseContentType) {
                    bodyText(String(decoding: data, as: UTF8.self), truncated: content.truncated, copyable: true,
                             total: content.totalSize)
                } else {
                    info("Binary content, \(ByteCountFormatter.string(fromByteCount: content.totalSize ?? Int64(data.count), countStyle: .file)). See Preview.")
                }
            } else {
                info(content?.note ?? "Loading…")
            }
        }
    }

    @ViewBuilder private var previewTab: some View {
        if let content, let data = content.data {
            let type = entry.responseContentType
            if entry.category == .img, !content.truncated, let image = NSImage(data: data) {
                imagePreview(image, bytes: Int64(data.count))
            } else if entry.category == .font, let font = Self.sampleFont(from: data) {
                fontPreview(font)
            } else if Self.isText(data, contentType: type) {
                bodyText(Self.displayText(data, contentType: type), truncated: content.truncated, copyable: false, total: content.totalSize)
            } else if entry.category == .media {
                info("Audio and video preview is not available yet. \(ByteCountFormatter.string(fromByteCount: content.totalSize ?? Int64(data.count), countStyle: .file)), \(type ?? "unknown type").")
            } else if content.truncated, entry.category == .img {
                info("This image is too large to preview.")
            } else {
                info("No preview for \(type ?? "this type").")
            }
        } else {
            info(content?.note ?? "Loading…")
        }
    }

    // MARK: Pieces

    private func imagePreview(_ image: NSImage, bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 320)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.18)))
            let size = image.representations.first.map { "\($0.pixelsWide) × \($0.pixelsHigh)" } ?? "\(Int(image.size.width)) × \(Int(image.size.height))"
            Text("\(size) px · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            if let note = content?.note { info(note) }
        }
    }

    private func fontPreview(_ font: Font) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aa Bb Cc Dd Ee 0123456789").font(font)
            Text("The quick brown fox jumps over the lazy dog").font(font)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.18)))
    }

    private func bodyText(_ text: String, truncated: Bool, copyable: Bool, total: Int64? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if copyable { HStack { Spacer(); copyButton(text) } }
            Text(text.isEmpty ? "(empty)" : text)
                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.18)))
            if truncated {
                info(total.map { "Showing the start of \(ByteCountFormatter.string(fromByteCount: $0, countStyle: .file))." } ?? "Showing the start only.")
            }
            if let note = content?.note { info(note) }
        }
    }

    private func info(_ text: String) -> some View {
        Label(text, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: { Label("Copy", systemImage: "doc.on.doc") }
            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Loading

    /// Served files are read from disk; proxied responses come from the captured body.
    private func loadContent() async -> LoadedContent {
        if let file = entry.servedFile, let folder = manager.folderPath(for: line.serverID) {
            let limit = entry.category == .img || entry.category == .font ? 25 * 1024 * 1024 : 512 * 1024
            let result = await Task.detached { ServerManager.readServedFile(path: file, folderPath: folder, limit: limit) }.value
            guard let result else {
                return LoadedContent(data: nil, note: "The file can't be read now (the folder is not accessible while its server is stopped, or the file was removed).")
            }
            return LoadedContent(data: result.data, totalSize: result.totalSize,
                                 truncated: Int64(result.data.count) < result.totalSize,
                                 note: entry.rewritten ? "Showing the file on disk. The proxy address in it was replaced when it was served." : nil)
        }
        if let body = entry.responseBody {
            return LoadedContent(data: body, totalSize: entry.bytes, truncated: entry.responseBodyTruncated)
        }
        if entry.bodiesDropped { return LoadedContent(data: nil, note: "The body was dropped to keep memory use low.") }
        if entry.method == "HEAD" || entry.bytes == 0 { return LoadedContent(data: nil, note: "This response has no body.") }
        return LoadedContent(data: nil, note: "No body was kept for this response.")
    }

    // MARK: Helpers (static so they are easy to test)

    static func isText(_ data: Data, contentType: String?) -> Bool {
        let type = (contentType ?? "").lowercased()
        if type.hasPrefix("text/") || type.contains("json") || type.contains("xml") || type.contains("javascript")
            || type.contains("x-www-form-urlencoded") || type.contains("svg") { return true }
        if type.hasPrefix("image/") || type.hasPrefix("font/") || type.hasPrefix("audio/") || type.hasPrefix("video/")
            || type.contains("octet-stream") || type.contains("pdf") || type.contains("zip") { return false }
        // Unknown type: text if the start decodes as UTF-8 without control characters.
        let sample = data.prefix(2048)
        guard let s = String(data: sample, encoding: .utf8) ?? String(data: sample.dropLast(), encoding: .utf8) else { return false }
        return !s.unicodeScalars.contains { $0.value < 9 || ($0.value > 13 && $0.value < 32) }
    }

    /// Pretty-prints JSON, decodes form bodies, otherwise shows the text as is.
    static func displayText(_ data: Data, contentType: String?) -> String {
        let type = (contentType ?? "").lowercased()
        let raw = String(decoding: data, as: UTF8.self)
        let looksJSON = type.contains("json") || raw.drop(while: \.isWhitespace).first.map { $0 == "{" || $0 == "[" } == true
        if looksJSON, let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            return String(decoding: pretty, as: UTF8.self)
        }
        if type.contains("x-www-form-urlencoded") {
            return raw.split(separator: "&").map { pair in
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let k = String(kv[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(kv[0])
                let v = kv.count > 1 ? (String(kv[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(kv[1])) : ""
                return "\(k): \(v)"
            }.joined(separator: "\n")
        }
        return raw
    }

    /// A SwiftUI font made from font file data, for a sample line.
    static func sampleFont(from data: Data) -> Font? {
        guard let descriptor = CTFontManagerCreateFontDescriptorFromData(data as CFData) else { return nil }
        return Font(CTFontCreateWithFontDescriptor(descriptor, 26, nil))
    }
}
