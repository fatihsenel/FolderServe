import Foundation

/// One line a served page wrote to its console (or an error nobody caught), forwarded by the injected script.
public struct ConsoleMessage: Sendable, Equatable, Identifiable {
    public enum Level: String, Sendable, CaseIterable {
        case error, warn, uncaught
        public var label: String {
            switch self {
            case .error: "error"
            case .warn: "warning"
            case .uncaught: "uncaught"
            }
        }
    }

    public var id = UUID()
    public var date: Date
    public var level: Level
    public var text: String
    /// Path of the page that logged it, e.g. "/orders/7".
    public var page: String

    public init(date: Date = Date(), level: Level, text: String, page: String) {
        self.date = date
        self.level = level
        self.text = text
        self.page = page
    }

    /// The endpoint the injected script posts to.
    public static let path = "/__console"
    public static let maxPostBytes = 64 * 1024
    public static let maxPerPost = 50
    public static let maxTextLength = 8_000

    /// Reads what the script posts: a JSON array of `{"l": level, "m": text, "u": page path}`. Anything else is dropped,
    /// and counts and lengths are capped, because any page (or device on the network, with Share on) can post here.
    public static func parse(_ data: Data, now: Date = Date()) -> [ConsoleMessage] {
        guard data.count <= maxPostBytes, let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.prefix(maxPerPost).compactMap { item in
            guard let level = (item["l"] as? String).flatMap(Level.init(rawValue:)), let text = item["m"] as? String, !text.isEmpty else { return nil }
            let page = String(((item["u"] as? String) ?? "").prefix(300))
            return ConsoleMessage(date: now, level: level, text: String(text.prefix(maxTextLength)), page: page)
        }
    }

    /// Wraps `console.error` / `console.warn` (the originals still run) and listens for uncaught errors and rejected promises, then posts
    /// them in small batches. It never throws into the page.
    static let script = "(function(){var q=[],t;function s(l,a){try{var m=[].map.call(a,function(x){if(x instanceof Error)return x.stack||x.message;"
        + "if(x&&typeof x==='object'){try{return JSON.stringify(x)}catch(e){}}return String(x)}).join(' ').slice(0,8000);"
        + "q.push({l:l,m:m,u:location.pathname});if(q.length>50)q.shift();clearTimeout(t);t=setTimeout(f,200)}catch(e){}}"
        + "function f(){var b=JSON.stringify(q);q=[];try{fetch('/__console',{method:'POST',body:b,keepalive:true,headers:{'Content-Type':'text/plain'}}).catch(function(){})}catch(e){}}"
        + "['error','warn'].forEach(function(l){var o=console[l];console[l]=function(){s(l,arguments);return o.apply(console,arguments)}});"
        + "addEventListener('error',function(e){if(!e.message)return;s('uncaught',[e.message+(e.filename?' ('+e.filename.replace(location.origin,'')+':'+e.lineno+')':'')])});"
        + "addEventListener('unhandledrejection',function(e){var r=e.reason;s('uncaught',['Unhandled promise rejection: '+(r&&(r.stack||r.message)||r)])})})();"
    static let tag = Data("<script>\(script)</script>".utf8)

    /// Inserts the console script right after the opening `<head>` tag, so it also sees errors from the page's own scripts
    /// while they load. Pages without a `<head>` get it at the very end.
    public static func inject(into html: Data) -> Data {
        let bytes = [UInt8](html)
        let needle = Array("<head".utf8)
        var insertAt = bytes.count
        var i = 0
        search: while i + needle.count < bytes.count {
            var match = true
            for j in 0..<needle.count where bytes[i + j] | 0x20 != needle[j] && bytes[i + j] != needle[j] { match = false; break }
            let next = bytes[i + needle.count]
            if match, next == UInt8(ascii: ">") || next == UInt8(ascii: " ") || next == 0x0A || next == 0x0D || next == 0x09 {
                var k = i + needle.count
                while k < bytes.count, bytes[k] != UInt8(ascii: ">") { k += 1 }
                if k < bytes.count { insertAt = k + 1 }
                break search
            }
            i += 1
        }
        var out = Data(bytes[0..<insertAt])
        out.append(tag)
        out.append(contentsOf: bytes[insertAt...])
        return out
    }
}
