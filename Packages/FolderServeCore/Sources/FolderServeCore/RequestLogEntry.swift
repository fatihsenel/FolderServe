import Foundation

public struct HTTPHeaderField: Sendable, Equatable, Hashable {
    public var name: String
    public var value: String
    public init(name: String, value: String) { self.name = name; self.value = value }

    /// Header dictionary as a list sorted by name (case-insensitive).
    public static func sorted(_ headers: [String: String]) -> [HTTPHeaderField] {
        headers.map { HTTPHeaderField(name: $0.key, value: $0.value) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}

public struct RequestLogEntry: Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var method: String
    public var path: String
    public var status: Int
    public var bytes: Int64
    /// e.g. "→ https://localhost:5003" for proxied requests.
    public var note: String?
    public var category: RequestCategory

    // MARK: Details (kept in memory only)

    /// Full URL as the browser requested it, e.g. http://127.0.0.1:8080/api/users?id=1
    public var url: String = ""
    public var requestHeaders: [HTTPHeaderField] = []
    /// The headers actually sent back (including the ones FolderServe adds).
    public var responseHeaders: [HTTPHeaderField] = []
    public var durationMs: Int?
    /// Absolute path of the file that answered a static request (the app reads it to preview it).
    public var servedFile: String?
    /// The served file had the proxy target's address replaced, so what is on disk differs from what was sent.
    public var rewritten = false
    /// Where a proxied request was forwarded.
    public var upstreamURL: String?
    /// Proxied calls only: the start of the request / response bodies, capped (see `capture limits`).
    public var requestBody: Data?
    public var requestBodyTruncated = false
    public var responseBody: Data?
    public var responseBodyTruncated = false
    /// Set when the app dropped the bodies to stay within its memory budget.
    public var bodiesDropped = false

    /// Added by the app's Replay button so a replayed request can be told apart (and is not passed on to a proxy target).
    public static let replayHeader = "x-folderserve-replay"

    /// Sent again from the detail panel (Replay) rather than by a browser.
    public var isReplay: Bool { requestHeaders.contains { $0.name.lowercased() == Self.replayHeader } }

    public static let maxRequestBodyCapture = 32 * 1024
    public static let maxResponseBodyCapture = 128 * 1024

    public init(date: Date = Date(), method: String, path: String, status: Int, bytes: Int64, note: String? = nil,
                category: RequestCategory = .other) {
        self.date = date
        self.method = method
        self.path = path
        self.status = status
        self.bytes = bytes
        self.note = note
        self.category = category
    }

    /// Bytes of captured bodies held by this entry.
    public var capturedBodyBytes: Int { (requestBody?.count ?? 0) + (responseBody?.count ?? 0) }

    /// Not made by a page: no referer, `Sec-Fetch-Site: none` and an empty destination. That is how browser DevTools
    /// (re-fetching a file to show it) or an extension asks. Typed addresses are not included (their destination is "document").
    public var isDetached: Bool {
        func value(_ name: String) -> String? { requestHeaders.first { $0.name.lowercased() == name }?.value.lowercased() }
        return value("sec-fetch-site") == "none" && value("sec-fetch-dest") == "empty" && value("referer") == nil
    }

    public var responseContentType: String? {
        responseHeaders.first { $0.name.lowercased() == "content-type" }?.value
    }
}
