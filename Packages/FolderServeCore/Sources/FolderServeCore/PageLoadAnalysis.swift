import Foundation

/// A page and the files it pulled in, with how long the whole load took.
public struct PageLoad: Equatable, Sendable {
    public var page: RequestLogEntry
    /// Everything the page loaded (scripts, styles, images, fetch calls, …), in log order. Never includes `page`.
    public var files: [RequestLogEntry]
    /// From the page request starting to the last of its files finishing.
    public var totalMs: Int
    /// The request that took longest to answer (the page itself counts), nil when no time was recorded.
    public var slowest: RequestLogEntry?
    /// Files that answered 400 or above.
    public var failed: Int
    /// Bytes of the page and its files.
    public var bytes: Int64
}

public enum PageLoadAnalysis {
    /// A request that starts later than this after everything so far finished is not part of the load
    /// (a poll or a click an hour in must not stretch "page load").
    public static let quietGapMs = 2000

    /// `log`: the requests of one server, oldest first (the page may be anywhere in it).
    /// Returns nil unless `page` is a document request that has at least one file.
    ///
    /// A file belongs to the page when its `Referer` is the page's URL, or the URL of a file already in the page
    /// (a stylesheet that loads an image, for example), and it started before the load went quiet. The load stops
    /// at the next request for the same document (a reload).
    public static func analyze(_ page: RequestLogEntry, in log: [RequestLogEntry]) -> PageLoad? {
        guard page.category == .doc, page.method == "GET", !page.url.isEmpty,
              let index = log.firstIndex(where: { $0.id == page.id }) else { return nil }
        let pageKey = key(page.url)
        var urls: Set<String> = [pageKey]
        var files: [RequestLogEntry] = []
        var lastEnd = end(of: page)
        for candidate in log[(index + 1)...] {
            if candidate.category == .doc {
                if key(candidate.url) == pageKey { break }   // the page was loaded again
                continue                                     // a link followed from the page: another page
            }
            guard let referer = referer(of: candidate), urls.contains(key(referer)) else { continue }
            if start(of: candidate).timeIntervalSince(lastEnd) * 1000 > Double(quietGapMs) { break }
            files.append(candidate)
            urls.insert(key(candidate.url))
            lastEnd = max(lastEnd, end(of: candidate))
        }
        guard !files.isEmpty else { return nil }
        let all = [page] + files
        let slowest = all.filter { $0.durationMs != nil }.max { ($0.durationMs ?? 0) < ($1.durationMs ?? 0) }
        return PageLoad(page: page, files: files,
                        totalMs: max(0, Int((lastEnd.timeIntervalSince(start(of: page)) * 1000).rounded())),
                        slowest: slowest,
                        failed: files.filter { $0.status >= 400 }.count,
                        bytes: all.reduce(0) { $0 + $1.bytes })
    }

    // The entry's date is when it was logged, which is when the answer was sent.
    private static func end(of e: RequestLogEntry) -> Date { e.date }
    private static func start(of e: RequestLogEntry) -> Date { e.date.addingTimeInterval(-Double(e.durationMs ?? 0) / 1000) }

    private static func referer(of e: RequestLogEntry) -> String? {
        e.requestHeaders.first { $0.name.lowercased() == "referer" }?.value
    }

    /// A URL without its fragment (browsers never send it in a Referer).
    private static func key(_ url: String) -> String {
        url.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? url
    }
}
