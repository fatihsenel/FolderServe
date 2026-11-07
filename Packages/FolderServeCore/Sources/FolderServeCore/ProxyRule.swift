import Foundation

/// Forward requests under `prefix` to another server, so the browser sees a single origin (no CORS).
public struct ProxyRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Path prefix such as "/api". Matches "/api" and "/api/...", not "/apix".
    public var prefix: String
    /// Full target URL such as "http://localhost:3000" or "https://localhost:5003".
    public var target: String
    /// false: "/api/users" -> "<target>/api/users"; true: -> "<target>/users".
    public var stripPrefix: Bool
    /// Replace the target's address in the text files served from the folder (config.json, JS bundles, HTML)
    /// with this server's own address, so an app that hard-codes "https://localhost:5003" calls the proxy instead.
    public var rewriteAddress: Bool

    public init(id: UUID = UUID(), prefix: String, target: String, stripPrefix: Bool = false, rewriteAddress: Bool = true) {
        self.id = id
        self.prefix = prefix
        self.target = target
        self.stripPrefix = stripPrefix
        self.rewriteAddress = rewriteAddress
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        prefix = try c.decode(String.self, forKey: .prefix)
        target = try c.decode(String.self, forKey: .target)
        stripPrefix = try c.decodeIfPresent(Bool.self, forKey: .stripPrefix) ?? false
        rewriteAddress = try c.decodeIfPresent(Bool.self, forKey: .rewriteAddress) ?? true
    }

    // MARK: Validation

    /// The prefix with a leading "/" and no trailing "/".
    public var normalizedPrefix: String {
        var p = prefix.trimmingCharacters(in: .whitespaces)
        if !p.hasPrefix("/") { p = "/" + p }
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    public var targetURL: URL? {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// nil when the rule is usable; otherwise a short message for the user.
    public var problem: String? {
        let p = normalizedPrefix
        if p == "/" || p.contains("?") || p.contains("#") || p.contains(" ") { return "Prefix must be a path such as /api" }
        if p == "/__reload" { return "This prefix is reserved" }
        if targetURL == nil { return "Target must be a full URL such as http://localhost:3000" }
        return nil
    }

    // MARK: Matching and URL building

    public func matches(path: String) -> Bool {
        let p = normalizedPrefix
        return path == p || path.hasPrefix(p + "/")
    }

    /// The URL the request is forwarded to, or nil for an unusable rule.
    public func upstreamURL(path: String, rawQuery: String?) -> URL? {
        guard problem == nil, let base = targetURL,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        var basePath = comps.percentEncodedPath
        while basePath.hasSuffix("/") { basePath.removeLast() }
        var rest = path
        if stripPrefix { rest = String(path.dropFirst(normalizedPrefix.count)) }
        if rest.isEmpty { rest = "/" }
        let encoded = rest.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rest
        comps.percentEncodedPath = basePath + encoded
        comps.percentEncodedQuery = (rawQuery?.isEmpty == false) ? rawQuery : nil
        comps.fragment = nil
        return comps.url
    }

    /// "https://localhost:5003" for the target, used to rewrite Origin/Referer/Location.
    public var targetOrigin: String? {
        guard let url = targetURL, let scheme = url.scheme, let host = url.host else { return nil }
        let hostPart = host.contains(":") ? "[\(host)]" : host
        return "\(scheme.lowercased())://\(hostPart)" + (url.port.map { ":\($0)" } ?? "")
    }

    /// A redirect to the target's own origin is turned into a local path so the browser stays on this origin.
    public func rewriteLocation(_ location: String) -> String {
        guard let origin = targetOrigin, location.lowercased().hasPrefix(origin.lowercased()) else { return location }
        var rest = String(location.dropFirst(origin.count))
        if rest.isEmpty { rest = "/" }
        guard rest.hasPrefix("/") else { return location }
        if stripPrefix { rest = normalizedPrefix + rest }
        return rest
    }

    // MARK: Address rewriting in served files

    /// File types whose contents are scanned for the target's address.
    public static let rewritableExtensions: Set<String> = ["json", "js", "mjs", "html", "htm"]
    public static let maxRewritableBytes = 10 * 1024 * 1024

    /// Replaces every whole-address occurrence of `origins` (e.g. "https://localhost:5003", also the JSON-escaped
    /// form "https:\/\/localhost:5003") in text with `local` (e.g. "http://127.0.0.1:8080").
    /// Returns nil when nothing needed changing or the data is not UTF-8 text.
    public static func rewriteAddresses(in data: Data, origins: [String], with local: String) -> Data? {
        guard !origins.isEmpty, var text = String(data: data, encoding: .utf8) else { return nil }
        var changed = false
        for origin in Set(origins) {
            for (from, to) in [(origin, local), (origin.replacingOccurrences(of: "/", with: "\\/"), local.replacingOccurrences(of: "/", with: "\\/"))] {
                guard text.range(of: from, options: .caseInsensitive) != nil else { continue }
                // Whole addresses only: not "…:50031", not "localhost.example.com".
                let pattern = NSRegularExpression.escapedPattern(for: from) + "(?![A-Za-z0-9\\-]|\\.[A-Za-z0-9])"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                let range = NSRange(text.startIndex..., in: text)
                let replaced = regex.stringByReplacingMatches(in: text, options: [], range: range,
                                                              withTemplate: NSRegularExpression.escapedTemplate(for: to))
                if replaced != text { text = replaced; changed = true }
            }
        }
        return changed ? Data(text.utf8) : nil
    }

    // MARK: Cookies

    /// The browser reaches the proxy over plain http on 127.0.0.1, so cookies from an https API
    /// would be refused: drop Secure and Domain, and turn SameSite=None (which requires Secure) into Lax.
    public static func rewriteSetCookie(_ cookie: String) -> String {
        let parts = cookie.components(separatedBy: ";")
        var out: [String] = []
        for (i, raw) in parts.enumerated() {
            let part = raw.trimmingCharacters(in: .whitespaces)
            if i == 0 { out.append(part); continue }
            let lower = part.lowercased()
            if lower == "secure" || lower == "partitioned" || lower.hasPrefix("domain=") { continue }
            if lower == "samesite=none" { out.append("SameSite=Lax"); continue }
            out.append(part)
        }
        return out.joined(separator: "; ")
    }

    /// URLSession folds repeated Set-Cookie headers into one comma-separated value; split them again
    /// without breaking dates such as "Expires=Wed, 21 Oct 2026 ...".
    public static func splitSetCookie(_ combined: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(combined)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == ",", i + 1 < chars.count, chars[i + 1] == " " {
                // A new cookie starts when the text up to the next ";" or "," looks like "name=".
                var j = i + 2
                var sawEquals = false
                while j < chars.count, chars[j] != ";", chars[j] != ",", chars[j] != " " {
                    if chars[j] == "=" { sawEquals = true; break }
                    j += 1
                }
                if sawEquals { result.append(current); current = ""; i += 2; continue }
            }
            current.append(c)
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Cross-site guard

    /// A web page on another origin must not be able to drive your backend through this proxy.
    /// Allows requests without Origin (curl, same-origin GETs) and requests whose Origin is this very server.
    public static func isSameOriginRequest(headers: [String: String]) -> Bool {
        if let site = headers["sec-fetch-site"]?.lowercased(), site == "cross-site" || site == "same-site" { return false }
        guard let origin = headers["origin"] else { return true }
        guard let host = headers["host"]?.lowercased(), origin.lowercased() == "http://" + host else { return false }
        return true
    }
}
