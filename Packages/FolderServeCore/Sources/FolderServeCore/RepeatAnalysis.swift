import Foundation

/// Explains why the same URL shows up more than once in the Activity log, by comparing a request with the
/// closest earlier one for the same method and URL.
public struct RepeatInfo: Equatable, Sendable {
    public struct Difference: Equatable, Sendable {
        public var header: String
        public var earlier: String?
        public var this: String?
    }
    public var earlier: RequestLogEntry
    /// Milliseconds between the two requests.
    public var gapMs: Int
    /// How many times this URL was requested up to and including this request.
    public var count: Int
    public var differences: [Difference]
    /// One sentence on the likely cause.
    public var headline: String
}

public enum RepeatAnalysis {
    /// Headers worth comparing: they say who asked, why, and how the cache was involved.
    static let compared = ["sec-fetch-dest", "sec-fetch-mode", "sec-fetch-site", "sec-purpose", "purpose", "referer",
                           "cache-control", "pragma", "if-none-match", "if-modified-since", "accept", "range", "user-agent"]

    /// `earlier`: the requests logged before `entry` (oldest first). Nil when the URL was not requested before.
    public static func analyze(_ entry: RequestLogEntry, earlier: [RequestLogEntry]) -> RepeatInfo? {
        let key = identity(entry)
        let same = earlier.filter { identity($0) == key && $0.id != entry.id }
        guard let previous = same.last else { return nil }
        let gap = max(0, Int((entry.date.timeIntervalSince(previous.date) * 1000).rounded()))
        let a = headers(previous), b = headers(entry)
        let diffs = compared.compactMap { name -> RepeatInfo.Difference? in
            a[name] == b[name] ? nil : .init(header: name, earlier: a[name], this: b[name])
        }
        return RepeatInfo(earlier: previous, gapMs: gap, count: same.count + 1, differences: diffs,
                          headline: headline(gap: gap, a: a, b: b, diffs: diffs))
    }

    private static func identity(_ e: RequestLogEntry) -> String { e.method + " " + (e.url.isEmpty ? e.path : e.url) }

    private static func headers(_ e: RequestLogEntry) -> [String: String] {
        Dictionary(e.requestHeaders.map { ($0.name.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    private static func headline(gap: Int, a: [String: String], b: [String: String], diffs: [RepeatInfo.Difference]) -> String {
        if a[RequestLogEntry.replayHeader] != nil || b[RequestLogEntry.replayHeader] != nil {
            return "One of the two was replayed from the detail panel (Replay), so the repeat is expected."
        }
        let purposes = [a["sec-purpose"], a["purpose"], b["sec-purpose"], b["purpose"]].compactMap { $0?.lowercased() }
        if purposes.contains(where: { $0.contains("prefetch") || $0.contains("prerender") }) {
            return "One of the two is a browser prefetch or prerender; the other is the real load."
        }
        let revalidating = [a, b].contains { h in
            let cc = h["cache-control"]?.lowercased() ?? ""
            return cc.contains("no-cache") || cc.contains("max-age=0") || h["pragma"]?.lowercased() == "no-cache"
        }
        // A request with no page behind it (no referer, "none" site, empty destination) next to a normal one.
        func detached(_ h: [String: String]) -> Bool {
            h["sec-fetch-site"] == "none" && h["sec-fetch-dest"] == "empty" && h["referer"] == nil
        }
        if detached(a) != detached(b) {
            return "One of the two was not made by the page (no referer, sec-fetch-site: none). That is how browser DevTools or an extension re-fetches a file to show it, which it has to do when the response is no-store. Turn on Cache in Options to let it read from its cache instead."
        }
        if gap > 2_000 {
            return revalidating
                ? "The page was loaded or reloaded again, and the browser skipped its cache (DevTools “Disable cache” or a hard reload)."
                : "The page (or this script) was loaded again about \(gap / 1000) s later, so these are two separate page loads."
        }
        if let d = diffs.first(where: { $0.header == "sec-fetch-dest" || $0.header == "sec-fetch-mode" }) {
            return "The browser asked for it twice in different ways (\(d.header): \(d.earlier ?? "none") → \(d.this ?? "none")), for example a preload and then the actual import."
        }
        if revalidating {
            return "Sent twice within \(gap) ms with the browser cache bypassed (DevTools “Disable cache” does this)."
        }
        if diffs.isEmpty {
            return "Sent twice within \(gap) ms with identical headers. The browser (or an extension) made the request twice; FolderServe logged exactly what arrived."
        }
        return "Sent twice within \(gap) ms; only the headers listed below differ."
    }
}
