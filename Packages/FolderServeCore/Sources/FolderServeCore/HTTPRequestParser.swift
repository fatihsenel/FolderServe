import Foundation

public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    /// Percent-decoded path, without query or fragment.
    public var path: String
    public var rawQuery: String?
    /// Header names are lowercased.
    public var headers: [String: String]

    /// The URL as the browser used it (http + Host header + path + query), for display.
    public var displayURL: String {
        let host = headers["host"] ?? "127.0.0.1"
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        return "http://\(host)\(encoded)" + (rawQuery.map { "?" + $0 } ?? "")
    }

    public init(method: String, path: String, rawQuery: String?, headers: [String: String]) {
        self.method = method
        self.path = path
        self.rawQuery = rawQuery
        self.headers = headers
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case needMore
    case request(HTTPRequest, consumed: Int)
    case malformed
}

public enum HTTPRequestParser {
    static let maxHeaderBytes = 16 * 1024

    public static func parse(_ data: Data) -> HTTPParseResult {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeaderBytes ? .malformed : .needMore
        }
        let headBytes = data[data.startIndex..<end.lowerBound]
        if headBytes.count > maxHeaderBytes { return .malformed }
        guard let head = String(data: headBytes, encoding: .utf8) else { return .malformed }

        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3,
              !requestLine[0].isEmpty,
              requestLine[2].hasPrefix("HTTP/1."),
              requestLine[1].hasPrefix("/") else { return .malformed }

        var target = String(requestLine[1])
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        var rawPath = target
        var rawQuery: String?
        if let q = target.firstIndex(of: "?") {
            rawPath = String(target[..<q])
            rawQuery = String(target[target.index(after: q)...])
        }
        guard let path = rawPath.removingPercentEncoding, !path.contains("\0") else { return .malformed }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .malformed }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.isEmpty { return .malformed }
            headers[name] = value
        }

        let request = HTTPRequest(method: String(requestLine[0]), path: path, rawQuery: rawQuery, headers: headers)
        return .request(request, consumed: data.distance(from: data.startIndex, to: end.upperBound))
    }
}
