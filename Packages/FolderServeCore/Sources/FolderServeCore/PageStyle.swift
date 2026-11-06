import Foundation

enum PageStyle {
    static let css = """
    :root{color-scheme:light dark;--bg:#f5f5f7;--fg:#1d1d1f;--muted:#6e6e73;--card:#fff;--line:#e5e5ea;--accent:#0a84ff}
    @media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#f5f5f7;--muted:#98989d;--card:#232326;--line:#38383a}}
    body{margin:0;padding:40px 20px;background:var(--bg);color:var(--fg);font:15px -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif}
    main{max-width:760px;margin:0 auto;background:var(--card);border:1px solid var(--line);border-radius:16px;padding:24px 28px}
    h1{font-size:20px;margin:0 0 16px;word-break:break-all}
    ul{list-style:none;margin:0;padding:0}li a{display:block;padding:8px 4px;color:var(--fg);text-decoration:none;border-bottom:1px solid var(--line)}
    li a:hover{color:var(--accent)}p{color:var(--muted)}
    """

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
