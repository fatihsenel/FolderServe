import Foundation

/// How a rule's path is written: an exact path (`/api/me`), a prefix ending in `*` (`/api/*`), or `*` for everything.
public enum PathPattern {
    public static func matches(_ pattern: String, path: String) -> Bool {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        if p == "*" || p == "/*" { return true }
        if p.hasSuffix("*") { return path.hasPrefix(String(p.dropLast())) }
        return path == p || (p.count > 1 && path == p + "/")
    }

    /// Why a pattern cannot be used, or nil.
    public static func problem(_ pattern: String) -> String? {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        if p == "*" { return nil }
        if !p.hasPrefix("/") { return "The path must start with /" }
        if p.dropLast().contains("*") { return "* is only allowed at the end" }
        return nil
    }
}

/// Answers matching requests with a fixed response instead of serving a file or forwarding to a proxy target,
/// so a page can be tried without its backend.
public struct MockRule: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var enabled = true
    /// An HTTP method, or empty for any.
    public var method = ""
    public var path = "/api/example"
    public var status = 200
    public var contentType = "application/json"
    public var body = "{}"
    /// Wait this long before answering (slow-backend testing).
    public var delayMs = 0

    public static let maxDelayMs = 30_000

    public init(id: UUID = UUID(), enabled: Bool = true, method: String = "", path: String = "/api/example", status: Int = 200,
                contentType: String = "application/json", body: String = "{}", delayMs: Int = 0) {
        self.id = id; self.enabled = enabled; self.method = method; self.path = path
        self.status = status; self.contentType = contentType; self.body = body; self.delayMs = delayMs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        method = try c.decodeIfPresent(String.self, forKey: .method) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "/"
        status = try c.decodeIfPresent(Int.self, forKey: .status) ?? 200
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? "application/json"
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
    }

    /// CR or LF anywhere (compared as scalars: Swift treats "\r\n" as a single Character, which `contains("\r")` would miss).
    static func hasLineBreak(_ s: String) -> Bool { s.unicodeScalars.contains { $0 == "\r" || $0 == "\n" } }

    public func matches(method requestMethod: String, path requestPath: String) -> Bool {
        guard enabled else { return false }
        let m = method.trimmingCharacters(in: .whitespaces)
        if !m.isEmpty && m.uppercased() != requestMethod.uppercased() { return false }
        return PathPattern.matches(path, path: requestPath)
    }

    public var problem: String? {
        if let p = PathPattern.problem(path) { return p }
        if !(200...599).contains(status) { return "The status must be between 200 and 599" }
        if !(0...Self.maxDelayMs).contains(delayMs) { return "The delay must be between 0 and \(Self.maxDelayMs) ms" }
        if Self.hasLineBreak(contentType) { return "Invalid content type" }
        return nil
    }
}

/// Adds (or replaces) a response header on every answer whose path matches, whether it comes from a file,
/// a proxy target or a mock rule.
public struct HeaderRule: Codable, Equatable, Identifiable, Sendable {
    public var id = UUID()
    public var enabled = true
    public var path = "*"
    public var name = ""
    public var value = ""

    /// Headers that describe the message framing; changing them would break the response.
    static let forbidden: Set<String> = ["content-length", "transfer-encoding", "connection", "host", "upgrade", "keep-alive"]

    public init(id: UUID = UUID(), enabled: Bool = true, path: String = "*", name: String = "", value: String = "") {
        self.id = id; self.enabled = enabled; self.path = path; self.name = name; self.value = value
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? "*"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    }

    public var problem: String? {
        if let p = PathPattern.problem(path) { return p }
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "The header needs a name" }
        let token = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        if n.unicodeScalars.contains(where: { !token.contains($0) }) { return "“\(n)” is not a valid header name" }
        if Self.forbidden.contains(n.lowercased()) { return "\(n) cannot be changed" }
        if MockRule.hasLineBreak(value) { return "The value must be on one line" }
        return nil
    }

    /// The headers to add for a request path (later rules win over earlier ones with the same name).
    public static func headers(for path: String, in rules: [HeaderRule]) -> [String: String] {
        var out: [String: String] = [:]
        for r in rules where r.enabled && r.problem == nil && PathPattern.matches(r.path, path: path) {
            out[r.name.trimmingCharacters(in: .whitespaces)] = r.value
        }
        return out
    }
}
