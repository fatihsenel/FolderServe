import Foundation

/// Decodes an HTTP/1.1 `Transfer-Encoding: chunked` request body (RFC 9112 §7.1).
/// The proxy joins the chunks and forwards the body with a `Content-Length`.
public enum ChunkedBody {
    public enum Result: Equatable, Sendable {
        /// The body is not complete yet: read more bytes and call again with everything received so far.
        case needMore
        /// `body`: the joined chunks. `consumed`: how many bytes of the input were used (the last chunk and trailers included).
        case complete(body: Data, consumed: Int)
        case malformed
        case tooLarge
    }

    /// `data`: the bytes after the request head. Chunk extensions (`;name=value`) and trailer fields are accepted and ignored.
    public static func decode(_ data: Data, maxSize: Int) -> Result {
        var body = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)

        while true {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else {
                // No size line yet. A size line is short, so a long run without a line break is not chunked data.
                return data.distance(from: index, to: data.endIndex) > 1024 ? .malformed : .needMore
            }
            let line = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
            let sizeText = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            guard !sizeText.isEmpty, sizeText.count <= 8, let size = Int(sizeText, radix: 16) else { return .malformed }
            index = lineEnd.upperBound

            if size == 0 {
                // Trailer fields, then an empty line.
                while true {
                    guard let end = data.range(of: crlf, in: index..<data.endIndex) else {
                        return data.distance(from: index, to: data.endIndex) > 8 * 1024 ? .malformed : .needMore
                    }
                    let empty = end.lowerBound == index
                    index = end.upperBound
                    if empty { return .complete(body: body, consumed: data.distance(from: data.startIndex, to: index)) }
                }
            }

            if body.count + size > maxSize { return .tooLarge }
            // Chunk data, then its own CRLF.
            guard data.distance(from: index, to: data.endIndex) >= size + 2 else { return .needMore }
            body.append(data[index..<data.index(index, offsetBy: size)])
            index = data.index(index, offsetBy: size)
            guard data[index..<data.index(index, offsetBy: 2)] == crlf else { return .malformed }
            index = data.index(index, offsetBy: 2)
        }
    }
}
