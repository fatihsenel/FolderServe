import Foundation

public enum MIMEType {
    private static let table: [String: String] = [
        "html": "text/html; charset=utf-8", "htm": "text/html; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8", "mjs": "text/javascript; charset=utf-8",
        "json": "application/json; charset=utf-8", "map": "application/json; charset=utf-8",
        "txt": "text/plain; charset=utf-8", "xml": "application/xml; charset=utf-8",
        "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "ico": "image/x-icon",
        "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf",
        "wasm": "application/wasm", "pdf": "application/pdf",
        "mp4": "video/mp4", "webm": "video/webm", "mp3": "audio/mpeg",
    ]

    public static func forExtension(_ ext: String) -> String {
        table[ext.lowercased()] ?? "application/octet-stream"
    }
}
