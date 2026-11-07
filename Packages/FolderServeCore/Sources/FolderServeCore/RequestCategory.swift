import Foundation

/// Browser dev-tools style grouping of requests.
public enum RequestCategory: String, CaseIterable, Sendable, Codable {
    case fetch, doc, js, css, img, media, font, other

    public var label: String {
        switch self {
        case .fetch: "Fetch/XHR"
        case .doc: "Doc"
        case .js: "JS"
        case .css: "CSS"
        case .img: "Img"
        case .media: "Media"
        case .font: "Font"
        case .other: "Other"
        }
    }

    /// Uses the browser's `Sec-Fetch-Dest` header when present (exact), otherwise the file extension.
    /// Proxied API calls count as Fetch/XHR unless the browser says they are something else.
    public static func classify(path: String, secFetchDest: String?, proxied: Bool) -> RequestCategory {
        if let dest = secFetchDest?.lowercased(), !dest.isEmpty {
            switch dest {
            case "empty": return .fetch
            case "document", "iframe", "frame", "fencedframe": return .doc
            case "script", "worker", "sharedworker", "serviceworker", "audioworklet", "paintworklet": return .js
            case "style": return .css
            case "image": return .img
            case "font": return .font
            case "audio", "video", "track": return .media
            default: break
            }
        }
        if proxied { return .fetch }
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "": return path == "-" ? .other : .doc          // routes served by the SPA fallback, directory pages
        case "html", "htm": return .doc
        case "js", "mjs", "cjs", "map": return .js
        case "css": return .css
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "avif", "ico", "bmp", "tif", "tiff", "heic": return .img
        case "woff", "woff2", "ttf", "otf", "eot": return .font
        case "mp4", "m4v", "webm", "mov", "mkv", "mp3", "m4a", "aac", "wav", "ogg", "oga", "ogv", "flac": return .media
        case "json", "xml", "txt", "csv": return .fetch
        default: return .other
        }
    }
}
