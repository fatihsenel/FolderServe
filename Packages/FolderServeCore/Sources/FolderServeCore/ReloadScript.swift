import Foundation

public enum ReloadScript {
    static let tag = Data("<script>new EventSource('/__reload').onmessage=()=>location.reload()</script>".utf8)
    private static let closingBody = Array("</body>".utf8)

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
