import Foundation

/// Answers a request with a saved response instead of the folder or a proxy target.
public struct MockRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// "GET", "POST", …; empty means any method.
    public var method: String
    /// Exact path such as "/api/users/7" (no query).
    public var path: String
    public var status: Int
    public var contentType: String
    public var body: String
    public var enabled: Bool

    public static let maxBodyBytes = 256 * 1024
    /// Methods the editor offers; "" is "any".
    public static let methods = ["", "GET", "POST", "PUT", "PATCH", "DELETE"]
    /// Response header that marks a mocked answer.
    public static let header = "X-FolderServe-Mock"
    /// The Activity note of a mocked request.
    public static let note = "mock"

    public init(id: UUID = UUID(), method: String = "", path: String, status: Int = 200,
                contentType: String = "application/json", body: String = "", enabled: Bool = true) {
        self.id = id
        self.method = method
        self.path = path
        self.status = status
        self.contentType = contentType
        self.body = body
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? ""
        path = try c.decode(String.self, forKey: .path)
        status = try c.decodeIfPresent(Int.self, forKey: .status) ?? 200
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? "application/json"
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public var normalizedMethod: String { method.trimmingCharacters(in: .whitespaces).uppercased() }

    /// The path with a leading "/" and without a query.
    public var normalizedPath: String {
        var p = path.trimmingCharacters(in: .whitespaces)
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        if !p.hasPrefix("/") { p = "/" + p }
        return p
    }

    private static func hasControl(_ s: String) -> Bool { s.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F } }

    /// nil when the mock is usable; otherwise a short message for the user.
    public var problem: String? {
        let p = normalizedPath
        if path.trimmingCharacters(in: .whitespaces).isEmpty || p.contains("#") || p.contains(" ") || Self.hasControl(p) {
            return "Path must look like /api/users"
        }
        if p == "/__reload" || p == "/__console" { return "This path is reserved" }
        if !(100...599).contains(status) || status < 200 { return "Status must be between 200 and 599" }
        let type = contentType.trimmingCharacters(in: .whitespaces)
        if type.isEmpty || Self.hasControl(type) { return "Content type must look like application/json" }
        if body.utf8.count > Self.maxBodyBytes { return "Body is larger than 256 KB" }
        return nil
    }

    public func matches(method requestMethod: String, path requestPath: String) -> Bool {
        guard enabled, problem == nil, requestPath == normalizedPath else { return false }
        let m = normalizedMethod
        // HEAD is answered by a GET mock, like a file.
        return m.isEmpty || m == requestMethod.uppercased() || (m == "GET" && requestMethod.uppercased() == "HEAD")
    }

    /// A mock that repeats a logged request's answer, or nil when its body was not captured whole as text
    /// (a static file's body is never captured: pass it in `body`).
    public init?(capturing entry: RequestLogEntry, body: Data? = nil) {
        let data = body ?? entry.responseBody
        if body == nil, entry.responseBodyTruncated || entry.bodiesDropped { return nil }
        guard entry.status >= 200, let data, data.count <= Self.maxBodyBytes, let text = String(data: data, encoding: .utf8) else { return nil }
        let type = entry.responseContentType?.trimmingCharacters(in: .whitespaces) ?? ""
        self.init(method: entry.method.uppercased() == "HEAD" ? "GET" : entry.method.uppercased(), path: entry.path, status: entry.status,
                  contentType: type.isEmpty ? "text/plain; charset=utf-8" : type, body: text)
        if problem != nil { return nil }
    }

    /// `rules` with `rule` added; a rule for the same method and path is replaced.
    public static func adding(_ rule: MockRule, to rules: [MockRule]) -> [MockRule] {
        var out = rules.filter { !($0.normalizedMethod == rule.normalizedMethod && $0.normalizedPath == rule.normalizedPath) }
        out.append(rule)
        return out
    }
}
