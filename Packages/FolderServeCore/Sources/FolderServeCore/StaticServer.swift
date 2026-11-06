import Foundation
import Network

public enum StaticServerError: Error, Equatable {
    case portInUse(UInt16)
    case listenerFailed(String)
}

/// Serves one folder over HTTP/1.1 on 127.0.0.1. Every connection is handled on one serial queue;
/// file bodies are streamed in 64 KB chunks.
public final class StaticServer: @unchecked Sendable {
    private let root: URL
    private let requestedPort: UInt16
    private let queue = DispatchQueue(label: "folderserve.static-server")
    private let lock = NSLock()
    private var options: ServeOptions
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var _onRequest: (@Sendable (RequestLogEntry) -> Void)?

    public var onRequest: (@Sendable (RequestLogEntry) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRequest }
        set { lock.lock(); defer { lock.unlock() }; _onRequest = newValue }
    }

    public init(root: URL, port: UInt16, options: ServeOptions) {
        self.root = root
        self.requestedPort = port
        self.options = options
    }

    public func updateOptions(_ o: ServeOptions) {
        lock.lock(); options = o; lock.unlock()
    }

    private var currentOptions: ServeOptions {
        lock.lock(); defer { lock.unlock() }; return options
    }

    /// Starts listening; returns the actual port (useful when `port` was 0).
    public func start() async throws -> UInt16 {
        let params = NWParameters.tcp
        let port: NWEndpoint.Port = requestedPort == 0 ? .any : NWEndpoint.Port(rawValue: requestedPort)!
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: port)
        let listener: NWListener
        do { listener = try NWListener(using: params) } catch {
            throw StaticServerError.listenerFailed("\(error)")
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }

        let result: Result<UInt16, StaticServerError> = await withCheckedContinuation { cont in
            let once = LockedFlag()
            listener.stateUpdateHandler = { [requestedPort] state in
                switch state {
                case .ready:
                    if once.setIfUnset() { cont.resume(returning: .success(listener.port?.rawValue ?? requestedPort)) }
                case .failed(let err), .waiting(let err):
                    if once.setIfUnset() {
                        listener.cancel()
                        if case .posix(let code) = err, code == .EADDRINUSE {
                            cont.resume(returning: .failure(.portInUse(requestedPort)))
                        } else {
                            cont.resume(returning: .failure(.listenerFailed("\(err)")))
                        }
                    }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        switch result {
        case .success(let p):
            lock.lock(); self.listener = listener; lock.unlock()
            return p
        case .failure(let e):
            throw e
        }
    }

    public func stop() {
        lock.lock()
        let l = listener
        listener = nil
        lock.unlock()
        l?.cancel()
        queue.async { [self] in
            for c in connections.values { c.cancel() }
            connections.removeAll()
        }
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.queue.async { self?.connections[id] = nil }
            default: break
            }
        }
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil { conn.cancel(); return }
            switch HTTPRequestParser.parse(buf) {
            case .needMore:
                if isComplete { conn.cancel() } else { self.receive(conn, buffer: buf) }
            case .malformed:
                self.sendPage(conn, status: 400, message: "Bad request", method: "GET", path: "-", head: false)
            case .request(let req, _):
                self.respond(conn, req)
            }
        }
    }

    // MARK: - Responses

    private func respond(_ conn: NWConnection, _ req: HTTPRequest) {
        guard req.method == "GET" || req.method == "HEAD" else {
            sendPage(conn, status: 405, message: "Method not allowed", method: req.method, path: req.path,
                     head: false, extra: ["Allow": "GET, HEAD"])
            return
        }
        let isHead = req.method == "HEAD"
        let opts = currentOptions
        let acceptsHTML = req.headers["accept"]?.contains("text/html") ?? false
        let resolver = PathResolver(root: root, options: opts)

        switch resolver.resolve(path: req.path, acceptsHTML: acceptsHTML) {
        case .forbidden:
            sendPage(conn, status: 403, message: "Forbidden", method: req.method, path: req.path, head: isHead)
        case .notFound:
            sendPage(conn, status: 404, message: "Not found: \(req.path)", method: req.method, path: req.path, head: isHead)
        case .redirect(let location):
            let target = location + (req.rawQuery.map { "?" + $0 } ?? "")
            sendPage(conn, status: 301, message: "Moved", method: req.method, path: req.path, head: isHead,
                     extra: ["Location": target])
        case .directoryListing(let dir):
            let html = DirectoryListing.html(directory: dir, urlPath: req.path, showDotfiles: opts.serveDotfiles)
            sendBody(conn, status: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8),
                     method: req.method, path: req.path, head: isHead)
        case .file(let url):
            sendFile(conn, url: url, req: req, head: isHead)
        }
    }

    private func sendFile(_ conn: NWConnection, url: URL, req: HTTPRequest, head: Bool) {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? -1
        guard size >= 0 else {
            sendPage(conn, status: 404, message: "Not found: \(req.path)", method: req.method, path: req.path, head: head)
            return
        }
        var headers = [
            "Content-Type": MIMEType.forExtension(url.pathExtension),
            "Accept-Ranges": "bytes",
        ]
        var status = 200
        var range: ClosedRange<Int64> = 0...(max(size, 1) - 1)
        var length = size
        switch RangeHeader.parse(req.headers["range"], fileSize: size) {
        case .none:
            break
        case .partial(let r):
            status = 206
            range = r
            length = r.upperBound - r.lowerBound + 1
            headers["Content-Range"] = "bytes \(r.lowerBound)-\(r.upperBound)/\(size)"
        case .unsatisfiable:
            sendPage(conn, status: 416, message: "Range not satisfiable", method: req.method, path: req.path,
                     head: head, extra: ["Content-Range": "bytes */\(size)"])
            return
        }
        headers["Content-Length"] = String(length)
        log(req, status: status, bytes: length)
        let headData = Data(Self.head(status: status, headers: headers).utf8)

        if head || length == 0 {
            sendFinal(conn, headData)
            return
        }
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            sendFinal(conn, Data(Self.head(status: 500, headers: ["Content-Length": "0"]).utf8))
            return
        }
        do { try fh.seek(toOffset: UInt64(range.lowerBound)) } catch { try? fh.close(); conn.cancel(); return }
        conn.send(content: headData, completion: .contentProcessed { [weak self] err in
            if err != nil { try? fh.close(); conn.cancel(); return }
            self?.streamChunks(conn, fh, remaining: length)
        })
    }

    private func streamChunks(_ conn: NWConnection, _ fh: FileHandle, remaining: Int64) {
        guard remaining > 0,
              let chunk = try? fh.read(upToCount: Int(min(65_536, remaining))), !chunk.isEmpty else {
            try? fh.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true,
                      completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] err in
            if err != nil { try? fh.close(); conn.cancel(); return }
            self?.streamChunks(conn, fh, remaining: remaining - Int64(chunk.count))
        })
    }

    private func sendPage(_ conn: NWConnection, status: Int, message: String, method: String, path: String,
                          head: Bool, extra: [String: String] = [:]) {
        let html = ErrorPage.html(status: status, message: message)
        sendBody(conn, status: status, contentType: "text/html; charset=utf-8", body: Data(html.utf8),
                 method: method, path: path, head: head, extra: extra)
    }

    private func sendBody(_ conn: NWConnection, status: Int, contentType: String, body: Data,
                          method: String, path: String, head: Bool, extra: [String: String] = [:]) {
        var headers = extra
        headers["Content-Type"] = contentType
        headers["Content-Length"] = String(body.count)
        lockedLog(RequestLogEntry(method: method, path: path, status: status, bytes: Int64(body.count)))
        var out = Data(Self.head(status: status, headers: headers).utf8)
        if !head { out.append(body) }
        sendFinal(conn, out)
    }

    private func sendFinal(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    private func log(_ req: HTTPRequest, status: Int, bytes: Int64) {
        lockedLog(RequestLogEntry(method: req.method, path: req.path, status: status, bytes: bytes))
    }

    private func lockedLog(_ entry: RequestLogEntry) {
        onRequest?(entry)
    }

    private static func head(status: Int, headers: [String: String]) -> String {
        var s = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) { s += "\(k): \(v)\r\n" }
        s += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return s
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 301: return "Moved Permanently"
        case 400: return "Bad Request"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 416: return "Range Not Satisfiable"
        default: return "Error"
        }
    }
}

final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var set = false
    /// Returns true the first time it is called.
    func setIfUnset() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if set { return false }
        set = true
        return true
    }
}
