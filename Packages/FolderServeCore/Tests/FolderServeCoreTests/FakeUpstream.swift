import Foundation
import Darwin

/// A tiny blocking HTTP/1.1 server on 127.0.0.1 used as the "API" behind the proxy in tests.
final class FakeUpstream: @unchecked Sendable {
    struct Seen { var method = ""; var target = ""; var headers: [String: String] = [:]; var body = Data() }

    private(set) var port: UInt16 = 0
    private var fd: Int32 = -1
    private let lock = NSLock()
    private var _seen: [Seen] = []
    var seen: [Seen] { lock.lock(); defer { lock.unlock() }; return _seen }
    var last: Seen? { seen.last }

    func start() {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 16)
        var bound = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = UInt16(bigEndian: bound.sin_port)
        let listenFD = fd
        Thread.detachNewThread { [weak self] in
            while true {
                let c = accept(listenFD, nil, nil)
                if c < 0 { return }
                Thread.detachNewThread { self?.handle(c) }
            }
        }
    }

    func stop() { if fd >= 0 { shutdown(fd, SHUT_RDWR); close(fd); fd = -1 } }

    private func readAll(_ c: Int32) -> Seen? {
        var buf = Data(); var tmp = [UInt8](repeating: 0, count: 8192)
        let sep = Data("\r\n\r\n".utf8)
        while buf.range(of: sep) == nil {
            let n = read(c, &tmp, tmp.count); if n <= 0 { return nil }
            buf.append(tmp, count: n)
        }
        let r = buf.range(of: sep)!
        let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let parts = head[0].split(separator: " ")
        var seen = Seen(method: String(parts[0]), target: String(parts[1]))
        for l in head.dropFirst() { if let i = l.firstIndex(of: ":") { seen.headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
        var body = Data(buf[r.upperBound...])
        let need = Int(seen.headers["content-length"] ?? "") ?? 0
        while body.count < need { let n = read(c, &tmp, tmp.count); if n <= 0 { break }; body.append(tmp, count: n) }
        seen.body = body
        return seen
    }

    private func send(_ c: Int32, _ s: String) { let d = Array(s.utf8); _ = write(c, d, d.count) }

    private func handle(_ c: Int32) {
        defer { close(c) }
        guard let req = readAll(c) else { return }
        lock.lock(); _seen.append(req); lock.unlock()
        var path = req.target.split(separator: "?").first.map(String.init) ?? req.target
        if path.hasPrefix("/api/") { path = String(path.dropFirst(4)) }   // the proxy keeps the /api prefix
        func respond(_ status: String, _ headers: [String], _ body: String) {
            send(c, "HTTP/1.1 \(status)\r\n" + headers.map { $0 + "\r\n" }.joined() + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body)
        }
        switch path {
        case "/slow": sleep(3); respond("200 OK", [], "late")
        case "/redirect": respond("302 Found", ["Location: http://127.0.0.1:\(port)/landing"], "")
        case "/cookie":
            respond("200 OK", ["Set-Cookie: a=1; Path=/; Secure; SameSite=None; Domain=example.com",
                               "Set-Cookie: b=2; Expires=Wed, 21 Oct 2026 07:28:00 GMT; HttpOnly"], "ok")
        case "/stream":
            send(c, "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n")
            for part in ["one", "two", "three"] { send(c, "\(String(part.utf8.count, radix: 16))\r\n\(part)\r\n"); usleep(150_000) }
            send(c, "0\r\n\r\n")
        case "/empty": respond("204 No Content", [], "")
        case "/missing": respond("404 Not Found", ["Content-Type: application/json"], "{\"error\":\"nope\"}")
        default:
            respond("200 OK", ["Content-Type: text/plain", "Access-Control-Allow-Origin: https://upstream.example"],
                    "\(req.method) \(req.target) body=\(String(decoding: req.body, as: UTF8.self))")
        }
    }
}
