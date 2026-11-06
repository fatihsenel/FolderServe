import Foundation

/// Rejects requests whose `Host` header is not a loopback name. A page on another origin can use
/// DNS rebinding to make a browser send requests to 127.0.0.1 with its own hostname in `Host`;
/// refusing those keeps served files unreadable from the web.
public enum HostPolicy {
    public static func isAllowed(_ hostHeader: String?) -> Bool {
        guard let raw = hostHeader else { return true }   // HTTP/1.0 clients may omit Host
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return false }

        let name: String
        if value.hasPrefix("[") {
            guard let close = value.firstIndex(of: "]") else { return false }
            name = String(value[value.index(after: value.startIndex)..<close])
            let rest = value[value.index(after: close)...]
            guard rest.isEmpty || isPortSuffix(rest) else { return false }
        } else if let colon = value.lastIndex(of: ":") {
            guard isPortSuffix(value[colon...]) else { return false }
            name = String(value[..<colon])
        } else {
            name = value
        }
        return isLoopbackName(name)
    }

    private static func isPortSuffix(_ s: Substring) -> Bool {
        guard s.first == ":" else { return false }
        let digits = s.dropFirst()
        return !digits.isEmpty && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber)
    }

    private static func isLoopbackName(_ name: String) -> Bool {
        if name == "localhost" || name == "::1" { return true }
        if name.hasSuffix(".localhost") {
            return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
        }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let octets = parts.compactMap { part -> Int? in
            part.allSatisfy(\.isNumber) && !part.isEmpty ? Int(part) : nil
        }
        return octets.count == 4 && octets[0] == 127 && octets.allSatisfy { (0...255).contains($0) }
    }
}
