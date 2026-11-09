import Foundation
import Network
import Security

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
    /// When set, the listener speaks TLS with this identity.
    private let identity: SecIdentity?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// Extra response headers (CORS) for the request currently being answered on a connection.
    private var connHeaders: [ObjectIdentifier: [String: String]] = [:]
    /// The request being answered on a connection (and when it began), for the request log.
    private var connRequest: [ObjectIdentifier: (req: HTTPRequest, began: Date)] = [:]
    /// Open WebSocket tunnels, kept alive until either side hangs up.
    private var tunnels: [ObjectIdentifier: WebSocketTunnel] = [:]
    private var _onRequest: (@Sendable (RequestLogEntry) -> Void)?
    private let hub = ReloadHub()
    /// Seconds to wait for a proxied API before answering 504 (tests lower this).
    var proxyTimeout: TimeInterval = 60
    private lazy var forwarder = ProxyForwarder(timeout: proxyTimeout)
    private var watcher: FolderWatcher?
    private var pingTimer: DispatchSourceTimer?

    public var onRequest: (@Sendable (RequestLogEntry) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onRequest }
        set { lock.lock(); defer { lock.unlock() }; _onRequest = newValue }
    }

    public init(root: URL, port: UInt16, options: ServeOptions, identity: SecIdentity? = nil) {
        self.identity = identity
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
        let params: NWParameters
        if let identity, let secIdentity = sec_identity_create(identity) {
            let tls = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
            sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
            params = NWParameters(tls: tls)
        } else {
            params = .tcp
        }
        let port: NWEndpoint.Port = requestedPort == 0 ? .any : NWEndpoint.Port(rawValue: requestedPort)!
        params.requiredLocalEndpoint = .hostPort(host: currentOptions.shareOnNetwork ? .ipv4(.any) : .ipv4(.loopback), port: port)
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
            startLiveReload()
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
        watcher?.stop()
        watcher = nil
        queue.async { [self] in
            pingTimer?.cancel()
            pingTimer = nil
            hub.removeAll()
            for t in tunnels.values { t.close() }
            tunnels.removeAll()
            for c in connections.values { c.cancel() }
            connections.removeAll()
        }
    }

    // MARK: - Live reload

    private func startLiveReload() {
        let w = FolderWatcher(root: root, debounce: 0.1) { [weak self] (paths: [String]) in
            guard let self else { return }
            let kind = ReloadKind.classify(paths: paths)
            self.queue.async { if self.currentOptions.liveReload { self.hub.broadcast(kind) } }
        }
        w.start()
        watcher = w
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in self?.hub.ping() }
        timer.resume()
        pingTimer = timer
    }

    private func handleReloadStream(_ conn: NWConnection) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n: connected\n\n"
        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] err in
            if err != nil { conn.cancel(); return }
            self?.hub.add(conn)
        })
    }

    // MARK: - Connections

    private func accept(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed: self?.queue.async { self?.connections[id] = nil; self?.connHeaders[id] = nil; self?.connRequest[id] = nil }
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
            case .request(let req, let consumed):
                self.respond(conn, req, buffered: buf.dropFirst(consumed))
            }
        }
    }

    // MARK: - Responses

    private func respond(_ conn: NWConnection, _ parsed: HTTPRequest, buffered: Data = Data()) {
        var req = parsed
        req.secure = identity != nil
        connRequest[ObjectIdentifier(conn)] = (req, Date())
        guard HostPolicy.isAllowed(req.headers["host"], allowLAN: currentOptions.shareOnNetwork) else {
            sendPage(conn, status: 403, message: "Host not allowed", method: req.method, path: req.path, head: req.method == "HEAD")
            return
        }
        if req.method == "GET", req.path == "/__reload" {
            handleReloadStream(conn)
            return
        }
        let corsOn = currentOptions.cors
        if corsOn {
            connHeaders[ObjectIdentifier(conn)] = Self.corsHeaders(for: req)
            if req.method == "OPTIONS" {
                sendBody(conn, status: 204, contentType: "text/plain", body: Data(), method: req.method, path: req.path,
                         head: true, extra: Self.preflightHeaders(for: req))
                return
            }
        }
        if let mock = currentOptions.mocks.first(where: { $0.matches(method: req.method, path: req.path) }) {
            answerMock(conn, req, mock: mock, buffered: Data(buffered))
            return
        }
        if let rule = currentOptions.proxyRules.first(where: { $0.problem == nil && $0.matches(path: req.path) }) {
            proxy(conn, req, rule: rule, buffered: Data(buffered), corsOn: corsOn)
            return
        }
        guard req.method == "GET" || req.method == "HEAD" else {
            sendPage(conn, status: 405, message: "Method not allowed", method: req.method, path: req.path,
                     head: false, extra: ["Allow": corsOn ? "GET, HEAD, OPTIONS" : "GET, HEAD"])
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
            let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? location
            let target = encoded + (req.rawQuery.map { "?" + $0 } ?? "")
            sendPage(conn, status: 301, message: "Moved", method: req.method, path: req.path, head: isHead,
                     extra: ["Location": target])
        case .directoryListing(let dir):
            let html = DirectoryListing.html(directory: dir, urlPath: req.path, showDotfiles: opts.serveDotfiles)
            let page = opts.liveReload ? ReloadScript.inject(into: Data(html.utf8)) : Data(html.utf8)
            sendBody(conn, status: 200, contentType: "text/html; charset=utf-8", body: page,
                     method: req.method, path: req.path, head: isHead)
        case .file(let url):
            sendFile(conn, url: url, req: req, head: isHead, liveReload: opts.liveReload)
        }
    }

    // MARK: - Mocks

    /// Sends a saved answer. A request body is read first (up to a limit) so the client is not cut off while still sending.
    private func answerMock(_ conn: NWConnection, _ req: HTTPRequest, mock: MockRule, buffered: Data) {
        let send = { [weak self] in
            guard let self else { return }
            self.sendBody(conn, status: mock.status, contentType: mock.contentType.trimmingCharacters(in: .whitespaces),
                          body: Data(mock.body.utf8), method: req.method, path: req.path, head: req.method == "HEAD",
                          extra: [MockRule.header: "1"], note: MockRule.note, logBody: true)
        }
        guard let length = req.headers["content-length"].flatMap({ Int($0) }), length > buffered.count, length <= ProxyForwarder.maxRequestBody else {
            send()
            return
        }
        if expectsContinue(req) { sendContinue(conn) }
        readBody(conn, have: buffered, need: length) { body in if body != nil { send() } }
    }

    // MARK: - Proxy

    private func proxy(_ conn: NWConnection, _ req: HTTPRequest, rule: ProxyRule, buffered: Data, corsOn: Bool) {
        let isHead = req.method == "HEAD"
        if !corsOn && !ProxyRule.isSameOriginRequest(headers: req.headers, secure: req.secure) {
            sendPage(conn, status: 403, message: "Cross-origin request blocked. Turn on CORS for this folder if another origin needs the API.",
                     method: req.method, path: req.path, head: isHead)
            return
        }
        if WebSocketTunnel.isUpgrade(req) {
            let id = ObjectIdentifier(conn)
            guard let tunnel = WebSocketTunnel(client: conn, req: req, rule: rule, queue: queue,
                                               log: { [weak self] in self?.lockedLog($0) },
                                               onClose: { [weak self] in self?.queue.async { self?.tunnels[id] = nil } }) else {
                sendPage(conn, status: 502, message: "Invalid proxy rule for \(rule.normalizedPrefix)",
                         method: req.method, path: req.path, head: false)
                return
            }
            tunnels[id] = tunnel
            tunnel.start(buffered: buffered) { [weak self] status, message in
                self?.sendPage(conn, status: status, message: message, method: req.method, path: req.path, head: false)
            }
            return
        }
        let extra = connHeaders[ObjectIdentifier(conn)] ?? [:]
        let fail: (Int, String) -> Void = { [weak self] status, message in
            self?.sendPage(conn, status: status, message: message, method: req.method, path: req.path, head: isHead)
        }
        let forward: (Data) -> Void = { [weak self] body in
            guard let self else { return }
            self.forwarder.forward(conn: conn, req: req, body: body, rule: rule, extraHeaders: extra,
                                   log: { [weak self] in self?.lockedLog($0) }, fail: fail)
        }
        if let te = req.headers["transfer-encoding"]?.lowercased(), te != "identity" {
            guard te == "chunked" else {
                sendPage(conn, status: 501, message: "Unsupported Transfer-Encoding for the proxy: \(te)",
                         method: req.method, path: req.path, head: isHead)
                return
            }
            readChunkedBody(conn, have: buffered, expectContinue: expectsContinue(req), sentContinue: false) { result in
                switch result {
                case .complete(let body, _): forward(body)
                case .tooLarge: fail(413, "Request body too large for the proxy (limit 32 MB)")
                case .malformed: fail(400, "Malformed chunked request body")
                case .needMore: break   // the connection closed first; nothing to answer
                }
            }
            return
        }
        let need = Int(req.headers["content-length"] ?? "") ?? 0
        guard need >= 0, need <= ProxyForwarder.maxRequestBody else {
            fail(413, "Request body too large for the proxy (limit 32 MB)")
            return
        }
        if need > buffered.count, expectsContinue(req) { sendContinue(conn) }
        readBody(conn, have: buffered, need: need) { body in
            guard let body else { return }
            forward(body)
        }
    }

    private func expectsContinue(_ req: HTTPRequest) -> Bool {
        req.headers["expect"]?.lowercased().contains("100-continue") == true
    }

    /// Clients that sent `Expect: 100-continue` wait for this before sending the body (curl waits a second without it).
    private func sendContinue(_ conn: NWConnection) {
        conn.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
    }

    private func readChunkedBody(_ conn: NWConnection, have: Data, expectContinue: Bool, sentContinue: Bool,
                                 then: @escaping (ChunkedBody.Result) -> Void) {
        let result = ChunkedBody.decode(have, maxSize: ProxyForwarder.maxRequestBody)
        guard case .needMore = result else { then(result); return }
        if expectContinue && !sentContinue { sendContinue(conn) }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if error != nil || (data == nil && isComplete) { conn.cancel(); then(.needMore); return }
            self?.readChunkedBody(conn, have: have + (data ?? Data()), expectContinue: expectContinue, sentContinue: true, then: then)
        }
    }

    private func readBody(_ conn: NWConnection, have: Data, need: Int, then: @escaping (Data?) -> Void) {
        if have.count >= need { then(Data(have.prefix(need))); return }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            if error != nil || (data == nil && isComplete) { conn.cancel(); then(nil); return }
            self?.readBody(conn, have: have + (data ?? Data()), need: need, then: then)
        }
    }

    private func sendFile(_ conn: NWConnection, url: URL, req: HTTPRequest, head: Bool, liveReload: Bool) {
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
        var localOrigin = ""
        var length = size
        switch RangeHeader.parse(req.headers["range"], fileSize: size) {
        case .none:
            let ext = url.pathExtension.lowercased()
            let isHTML = ext == "html" || ext == "htm"
            // Addresses of proxy targets that should be pointed at this server instead.
            var origins: [String] = []
            if let host = req.headers["host"], ProxyRule.rewritableExtensions.contains(ext), size <= Int64(ProxyRule.maxRewritableBytes) {
                origins = currentOptions.proxyRules.filter { $0.problem == nil && $0.rewriteAddress }.compactMap(\.targetOrigin)
                localOrigin = (identity != nil ? "https://" : "http://") + host
            }
            if ((liveReload && isHTML) || !origins.isEmpty), size <= Self.maxInjectableBytes,
               let original = try? Data(contentsOf: url) {
                let rewritten = ProxyRule.rewriteAddresses(in: original, origins: origins, with: localOrigin)
                let injectable = liveReload && isHTML
                if rewritten != nil || injectable {
                    let base = rewritten ?? original
                    sendBody(conn, status: 200, contentType: MIMEType.forExtension(ext),
                             body: injectable ? ReloadScript.inject(into: base) : base, method: req.method, path: req.path,
                             head: head, extra: ["Accept-Ranges": "bytes"], servedFile: url.path, rewritten: rewritten != nil)
                    return
                }
            }
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
        if status == 200, currentOptions.caching, let etag = Self.etag(for: url, size: size) {
            headers["ETag"] = etag
            headers["Cache-Control"] = "no-cache"   // keep it, but ask us first: stays correct while you edit
            if Self.etagMatches(req.headers["if-none-match"], etag) {
                sendBody(conn, status: 304, contentType: headers["Content-Type"] ?? "application/octet-stream", body: Data(),
                         method: req.method, path: req.path, head: true,
                         extra: ["ETag": etag, "Cache-Control": "no-cache"], servedFile: url.path)
                return
            }
        }
        headers["Content-Length"] = String(length)
        lockedLog(makeEntry(conn, method: req.method, path: req.path, status: status, bytes: length,
                            responseHeaders: headers, servedFile: url.path))
        let headData = Data(responseHead(conn, status: status, headers: headers).utf8)

        if head || length == 0 {
            sendFinal(conn, headData)
            return
        }
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            sendFinal(conn, Data(responseHead(conn, status: 500, headers: ["Content-Length": "0"]).utf8))
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
                          method: String, path: String, head: Bool, extra: [String: String] = [:],
                          servedFile: String? = nil, rewritten: Bool = false, note: String? = nil, logBody: Bool = false) {
        var headers = extra
        headers["Content-Type"] = contentType
        headers["Content-Length"] = String(body.count)
        var entry = makeEntry(conn, method: method, path: path, status: status, bytes: Int64(body.count),
                              responseHeaders: headers, servedFile: servedFile, rewritten: rewritten)
        entry.note = note
        if logBody {
            entry.responseBody = Data(body.prefix(RequestLogEntry.maxResponseBodyCapture))
            entry.responseBodyTruncated = body.count > RequestLogEntry.maxResponseBodyCapture
        }
        lockedLog(entry)
        var out = Data(responseHead(conn, status: status, headers: headers).utf8)
        if !head { out.append(body) }
        sendFinal(conn, out)
    }

    private func sendFinal(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, contentContext: .finalMessage, isComplete: true,
                  completion: .contentProcessed { _ in conn.cancel() })
    }

    /// Builds a log entry with everything known about the request on this connection.
    private func makeEntry(_ conn: NWConnection, method: String, path: String, status: Int, bytes: Int64,
                           responseHeaders: [String: String], servedFile: String? = nil, rewritten: Bool = false) -> RequestLogEntry {
        let stored = connRequest[ObjectIdentifier(conn)]
        var e = RequestLogEntry(method: method, path: path, status: status, bytes: bytes,
                                category: .classify(path: path, secFetchDest: stored?.req.headers["sec-fetch-dest"], proxied: false))
        if let stored {
            e.url = stored.req.displayURL
            e.requestHeaders = HTTPHeaderField.sorted(stored.req.headers)
            e.durationMs = Int(Date().timeIntervalSince(stored.began) * 1000)
        }
        e.responseHeaders = HTTPHeaderField.sorted(finalHeaders(conn, responseHeaders))
        e.servedFile = servedFile
        e.rewritten = rewritten
        return e
    }

    private func lockedLog(_ entry: RequestLogEntry) {
        onRequest?(entry)
    }

    private static let maxInjectableBytes: Int64 = 20 * 1024 * 1024

    /// Headers added to every response when CORS is on.
    static func corsHeaders(for req: HTTPRequest) -> [String: String] {
        ["Access-Control-Allow-Origin": "*",
         "Access-Control-Expose-Headers": "Content-Length, Content-Range, Accept-Ranges, Content-Type"]
    }

    /// Extra headers for an OPTIONS preflight answer.
    static func preflightHeaders(for req: HTTPRequest) -> [String: String] {
        var h = ["Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
                 "Access-Control-Max-Age": "600",
                 "Content-Length": "0"]
        h["Access-Control-Allow-Headers"] = req.headers["access-control-request-headers"] ?? "*"
        // Chrome's Private Network Access: a public page asking to reach localhost.
        if req.headers["access-control-request-private-network"] == "true" { h["Access-Control-Allow-Private-Network"] = "true" }
        return h
    }

    /// Everything that is sent back: the response's own headers plus CORS headers and the ones every response carries.
    private func finalHeaders(_ conn: NWConnection, _ headers: [String: String]) -> [String: String] {
        var merged = headers
        for (k, v) in connHeaders[ObjectIdentifier(conn)] ?? [:] { merged[k] = v }
        if merged["Cache-Control"] == nil { merged["Cache-Control"] = "no-store" }
        merged["Connection"] = "close"
        return merged
    }

    private func responseHead(_ conn: NWConnection, status: Int, headers: [String: String]) -> String {
        var merged = headers
        for (k, v) in connHeaders[ObjectIdentifier(conn)] ?? [:] { merged[k] = v }
        return Self.head(status: status, headers: merged)
    }

    private static func head(status: Int, headers: [String: String]) -> String {
        var s = "HTTP/1.1 \(status) \(reason(status))\r\n"
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) { s += "\(k): \(v)\r\n" }
        if headers["Cache-Control"] == nil { s += "Cache-Control: no-store\r\n" }
        s += "Connection: close\r\n\r\n"
        return s
    }

    /// A weak validator from size and modification time (changes whenever the file is saved).
    static func etag(for url: URL, size: Int64) -> String? {
        guard let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { return nil }
        return "W/\"\(String(size, radix: 16))-\(String(Int64(mtime.timeIntervalSince1970 * 1000), radix: 16))\""
    }

    /// True when `If-None-Match` lists `etag` (weak comparison) or is `*`.
    static func etagMatches(_ header: String?, _ etag: String) -> Bool {
        guard let header else { return false }
        func strip(_ t: String) -> String { t.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "W/", with: "") }
        let mine = strip(etag)
        return header.split(separator: ",").contains { strip(String($0)) == "*" || strip(String($0)) == mine }
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 304: return "Not Modified"
        case 413: return "Payload Too Large"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 504: return "Gateway Timeout"
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
