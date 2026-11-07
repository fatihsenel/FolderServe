import Foundation
import FolderServeCore

/// A response body to put in a HAR file, and whether it is all of it.
struct HARBody: Equatable {
    var data: Data
    var complete: Bool
}

/// Turns logged requests into a HAR 1.2 document (the format Chrome DevTools, Firefox and many tools open).
enum HARExport {
    /// `lines` in any order (they are written oldest first); `bodies` holds the response bodies that are available, by line id.
    static func make(lines: [LogLine], bodies: [UUID: HARBody], appVersion: String) throws -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let entries = lines.sorted { $0.entry.date < $1.entry.date }.map { entry(for: $0, body: bodies[$0.id], iso: iso) }
        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "FolderServe", "version": appVersion],
                "entries": entries,
            ] as [String: Any],
        ]
        return try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .withoutEscapingSlashes])
    }

    static func entry(for line: LogLine, body: HARBody?, iso: ISO8601DateFormatter) -> [String: Any] {
        let e = line.entry
        let url = e.url.isEmpty ? "http://127.0.0.1" + e.path : e.url
        let wait = max(e.durationMs ?? 0, 0)
        return [
            "startedDateTime": iso.string(from: e.date),
            "time": wait,
            "request": request(e, url: url),
            "response": response(e, body: body),
            "cache": [String: Any](),
            "timings": ["send": 0, "wait": wait, "receive": 0],
        ]
    }

    private static func headers(_ fields: [HTTPHeaderField]) -> [[String: String]] {
        fields.map { ["name": $0.name, "value": $0.value] }
    }

    private static func request(_ e: RequestLogEntry, url: String) -> [String: Any] {
        let query = (URLComponents(string: url)?.queryItems ?? []).map { ["name": $0.name, "value": $0.value ?? ""] }
        var r: [String: Any] = [
            "method": e.method,
            "url": url,
            "httpVersion": "HTTP/1.1",
            "cookies": [Any](),
            "headers": headers(e.requestHeaders),
            "queryString": query,
            "headersSize": -1,
            "bodySize": e.requestBody?.count ?? 0,
        ]
        if let body = e.requestBody {
            let type = e.requestHeaders.first { $0.name.lowercased() == "content-type" }?.value ?? ""
            var post: [String: Any] = ["mimeType": type]
            if let text = String(data: body, encoding: .utf8) {
                post["text"] = text
                if e.requestBodyTruncated { post["comment"] = "Only the start of the request body was captured." }
            } else {
                post["text"] = ""
                post["comment"] = "The request body is binary and is not included."
            }
            r["postData"] = post
        }
        return r
    }

    private static func response(_ e: RequestLogEntry, body: HARBody?) -> [String: Any] {
        let type = e.responseContentType ?? ""
        var content: [String: Any] = ["size": e.bytes, "mimeType": type]
        if let body {
            if RequestDetailView.isText(body.data, contentType: type), let text = String(data: body.data, encoding: .utf8) {
                content["text"] = text
            } else {
                content["text"] = body.data.base64EncodedString()
                content["encoding"] = "base64"
            }
            if !body.complete { content["comment"] = "Only the start of the response body was captured." }
        }
        let location = e.responseHeaders.first { $0.name.lowercased() == "location" }?.value ?? ""
        return [
            "status": e.status,
            "statusText": HTTPStatus.reason(e.status),
            "httpVersion": "HTTP/1.1",
            "cookies": [Any](),
            "headers": headers(e.responseHeaders),
            "content": content,
            "redirectURL": location,
            "headersSize": -1,
            "bodySize": e.bytes,
        ]
    }

    /// The response bodies available for `lines`: captured ones (proxied calls) and served files read from disk
    /// (only when the whole file is read, up to `fileLimit` bytes). Call off the main thread.
    nonisolated static func gatherBodies(for lines: [LogLine], folderPath: (UUID) -> String?, fileLimit: Int = 2 * 1024 * 1024) -> [UUID: HARBody] {
        var result: [UUID: HARBody] = [:]
        for line in lines {
            let e = line.entry
            if let file = e.servedFile, let folder = folderPath(line.serverID),
               let read = ServerManager.readServedFile(path: file, folderPath: folder, limit: fileLimit),
               Int64(read.data.count) == read.totalSize {
                result[line.id] = HARBody(data: read.data, complete: true)
            } else if let body = e.responseBody {
                result[line.id] = HARBody(data: body, complete: !e.responseBodyTruncated)
            }
        }
        return result
    }
}
