import Foundation
import FolderServeCore

/// A captured request that the user may change before sending it again (Edit & Replay in the detail panel).
/// Only the path, query, method, headers and body can be changed: the host is always the server's current address.
struct EditableRequest: Equatable {
    struct Header: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var value: String
    }

    enum Problem: Error, Equatable {
        case notRunning
        case badTarget
        case badMethod(String)
        case badHeaderName(String)
        case badHeaderValue(String)
        case reservedHeader(String)

        var message: String {
            switch self {
            case .notRunning: "Start the server to send this request."
            case .badTarget: "The address must be a path such as /api/users?page=2."
            case .badMethod(let m): "“\(m)” is not a method this can send."
            case .badHeaderName(let n): "“\(n)” is not a valid header name."
            case .badHeaderValue(let n): "The value of “\(n)” has a line break or other control character."
            case .reservedHeader(let n): "“\(n)” is set by FolderServe or the HTTP client and can't be changed."
            }
        }
    }

    static let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    static let bodyMethods: Set<String> = ["POST", "PUT", "PATCH", "DELETE"]

    var method: String
    /// Path and query, percent-encoded as logged (the host stays the server's).
    var target: String
    var headers: [Header]
    var body: String
    /// The original body when it is not text: it is sent unchanged unless a text body is typed.
    var binaryBody: Data?
    /// Why the original body is not shown (cut off, dropped, binary).
    var bodyNote: String?

    init(method: String, target: String, headers: [Header] = [], body: String = "", binaryBody: Data? = nil, bodyNote: String? = nil) {
        self.method = method; self.target = target; self.headers = headers
        self.body = body; self.binaryBody = binaryBody; self.bodyNote = bodyNote
    }

    var hasBody: Bool { Self.bodyMethods.contains(method.uppercased()) }

    /// Starts from what was logged.
    init(entry: RequestLogEntry) {
        method = entry.method.uppercased()
        let logged = URLComponents(string: entry.url.isEmpty ? entry.path : entry.url)
        var t = logged?.percentEncodedPath ?? entry.path
        if t.isEmpty { t = "/" }
        if let q = logged?.percentEncodedQuery { t += "?" + q }
        target = t
        headers = entry.requestHeaders
            .filter { !RequestReplay.skippedHeaders.contains($0.name.lowercased()) && !$0.name.hasPrefix(":") }
            .map { Header(name: $0.name, value: $0.value) }
        body = ""
        if let data = entry.requestBody {
            if let text = String(data: data, encoding: .utf8) {
                body = text
            } else {
                binaryBody = data
                bodyNote = "The body is not text (\(data.count) bytes). It is sent unchanged unless you type a new one."
            }
        }
        if entry.requestBodyTruncated {
            bodyNote = "The body was cut off when it was captured. Type the body to send."
            body = ""; binaryBody = nil
        } else if entry.bodiesDropped && entry.requestBody == nil && Self.bodyMethods.contains(method) {
            bodyNote = "The body was dropped to keep memory use low. Type the body to send."
        }
    }

    /// Checks the edits and builds the request for the server listening at `base`.
    func urlRequest(base: URL?) -> Result<URLRequest, Problem> {
        guard let base, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return .failure(.notRunning) }
        let m = method.uppercased()
        guard Self.methods.contains(m) else { return .failure(.badMethod(method)) }

        let trimmed = target.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/"), !trimmed.hasPrefix("//"), !Self.hasControl(trimmed),
              let typed = URLComponents(string: trimmed), typed.scheme == nil, typed.host == nil else { return .failure(.badTarget) }
        parts.percentEncodedPath = typed.percentEncodedPath
        parts.percentEncodedQuery = typed.percentEncodedQuery
        guard let url = parts.url else { return .failure(.badTarget) }

        var request = URLRequest(url: url)
        request.httpMethod = m
        request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        for h in headers {
            let name = h.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty && h.value.isEmpty { continue }          // an empty row the user left behind
            guard Self.isToken(name) else { return .failure(.badHeaderName(name)) }
            guard !RequestReplay.skippedHeaders.contains(name.lowercased()) else { return .failure(.reservedHeader(name)) }
            guard !Self.hasControl(h.value) else { return .failure(.badHeaderValue(name)) }
            request.addValue(h.value.trimmingCharacters(in: .whitespaces), forHTTPHeaderField: name)
        }
        request.setValue("1", forHTTPHeaderField: RequestLogEntry.replayHeader)

        if hasBody {
            if !body.isEmpty { request.httpBody = Data(body.utf8) } else { request.httpBody = binaryBody }
        }
        return .success(request)
    }

    /// RFC 7230 token characters (what a header name may consist of).
    static func isToken(_ s: String) -> Bool {
        !s.isEmpty && s.unicodeScalars.allSatisfy { u in
            (u.value < 128) && (CharacterSet.alphanumerics.contains(u) || "!#$%&'*+-.^_`|~".unicodeScalars.contains(u))
        }
    }

    /// Swift treats "\r\n" as one Character, so look at the scalars (see CLAUDE.md).
    static func hasControl(_ s: String) -> Bool {
        s.unicodeScalars.contains { $0.value < 0x20 && $0 != "\t" || $0.value == 0x7F }
    }
}
