import Foundation

public enum ReloadScript {
    /// "css": swap the page's linked same-origin stylesheets for fresh copies (the new one is added first and the old one removed once it
    /// has loaded, so nothing flashes); anything else: reload the page. Older pages that still run the one-line script reload on both.
    static let source = "new EventSource('/__reload').onmessage=e=>{if(e.data!=='css')return location.reload();"
        + "document.querySelectorAll('link[rel~=stylesheet]').forEach(l=>{var u=new URL(l.href,location.href);if(u.origin!==location.origin)return;"
        + "u.searchParams.set('_fs',Date.now());var n=l.cloneNode();n.href=u.href;n.onload=()=>l.remove();n.onerror=()=>n.remove();l.after(n)})}"
    static let tag = Data("<script>\(source)</script>".utf8)
    private static let closingBody = Array("</body>".utf8)

    /// The scripts an HTML page gets for these options: live reload before `</body>`, the console forwarder after `<head>`.
    public static func decorate(_ html: Data, options: ServeOptions) -> Data {
        var page = html
        if options.liveReload { page = inject(into: page) }
        if options.captureConsole { page = ConsoleMessage.inject(into: page) }
        return page
    }

    /// Inserts the reload script before the last (case-insensitive) `</body>`, or appends it.
    public static func inject(into html: Data) -> Data {
        let bytes = [UInt8](html)
        let n = closingBody.count
        var insertAt = bytes.count
        if bytes.count >= n {
            var i = bytes.count - n
            while i >= 0 {
                var match = true
                for j in 0..<n where bytes[i + j] | 0x20 != closingBody[j] && bytes[i + j] != closingBody[j] {
                    match = false
                    break
                }
                if match { insertAt = i; break }
                i -= 1
            }
        }
        var out = Data(bytes[0..<insertAt])
        out.append(tag)
        out.append(contentsOf: bytes[insertAt...])
        return out
    }
}
