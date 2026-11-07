import Foundation
import Darwin

struct RawResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
    var text: String { String(decoding: body, as: UTF8.self) }
}

enum RawHTTP {
    /// Opens a TCP connection; returns -1 when the connection fails.
    static func openSocket(host: String, port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        // Non-blocking connect with a 1 s timeout: a listening socket answers immediately,
        // while a closed or filtered port must not stall the test for the OS-level timeout.
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if rc != 0 {
            guard errno == EINPROGRESS else { close(fd); return -1 }
            var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            guard poll(&pfd, 1, 1000) == 1 else { close(fd); return -1 }
            var err: Int32 = 0
            var len = socklen_t(MemoryLayout<Int32>.size)
            getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
            if err != 0 { close(fd); return -1 }
        }
        _ = fcntl(fd, F_SETFL, flags)
        return fd
    }

    /// Sends `request` verbatim and reads until EOF (or `readLimit` bytes, then hangs up).
    static func request(port: UInt16, _ request: String, readLimit: Int? = nil, host: String = "127.0.0.1") -> RawResponse? {
        let fd = openSocket(host: host, port: port)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let bytes = Array(request.utf8)
        _ = send(fd, bytes, bytes.count, 0)
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65536)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            data.append(buf, count: n)
            if let limit = readLimit, data.count >= limit { break }
        }
        return parse(data)
    }

    static func parse(_ data: Data) -> RawResponse? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[data.startIndex..<split.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let statusParts = lines.removeFirst().split(separator: " ")
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else { return nil }
        var headers: [String: String] = [:]
        for l in lines {
            if let c = l.firstIndex(of: ":") {
                headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
            }
        }
        var body = Data(data[split.upperBound...])
        if headers["transfer-encoding"]?.lowercased() == "chunked" { body = dechunk(body) }
        return RawResponse(status: status, headers: headers, body: body)
    }

    /// Decodes an HTTP/1.1 chunked body.
    static func dechunk(_ data: Data) -> Data {
        var out = Data(); var i = data.startIndex
        let crlf = Data("\r\n".utf8)
        while i < data.endIndex, let eol = data.range(of: crlf, in: i..<data.endIndex) {
            let sizeText = String(decoding: data[i..<eol.lowerBound], as: UTF8.self)
            guard let size = Int(sizeText.split(separator: ";").first ?? "", radix: 16), size > 0 else { break }
            let start = eol.upperBound, end = start + size
            guard end <= data.endIndex else { out.append(data[start...]); break }
            out.append(data[start..<end])
            i = min(end + 2, data.endIndex)
        }
        return out
    }

    /// The whole response as text (status line, every header line, body).
    static func rawText(port: UInt16, _ request: String) -> String? {
        let fd = openSocket(host: "127.0.0.1", port: port)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        let bytes = Array(request.utf8)
        _ = send(fd, bytes, bytes.count, 0)
        var data = Data(); var buf = [UInt8](repeating: 0, count: 65536)
        while true { let n = recv(fd, &buf, buf.count, 0); if n <= 0 { break }; data.append(buf, count: n) }
        return String(decoding: data, as: UTF8.self)
    }

    static func get(port: UInt16, _ path: String, headers: String = "", method: String = "GET") -> RawResponse? {
        request(port: port, "\(method) \(path) HTTP/1.1\r\nHost: localhost\r\n\(headers)\r\n")
    }
}
