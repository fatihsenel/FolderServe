import Foundation
import Network

/// Carries a WebSocket (or any HTTP "Upgrade") through a proxy rule: opens a TCP/TLS connection to the target,
/// replays the browser's upgrade request with the address fields pointed at the target, then copies bytes both ways.
/// Frames are never parsed, so any subprotocol works (Vite/Angular HMR, SignalR, socket.io, ...).
final class WebSocketTunnel: @unchecked Sendable {
    private let client: NWConnection
    private let upstream: NWConnection
    private let req: HTTPRequest
    private let rule: ProxyRule
    private let queue: DispatchQueue
    private let log: (RequestLogEntry) -> Void
    private let began = Date()
    private let target: URL
    private var closed = false
    private var logged = false
    private var responseHead = Data()
    private var bytesUp: Int64 = 0
    private var bytesDown: Int64 = 0
    private let onClose: () -> Void

    static func isUpgrade(_ req: HTTPRequest) -> Bool {
        req.headers["upgrade"]?.lowercased() == "websocket"
            && (req.headers["connection"]?.lowercased().contains("upgrade") ?? false)
    }

    /// nil when the rule's target cannot be reached by URL (caller answers 502).
    init?(client: NWConnection, req: HTTPRequest, rule: ProxyRule, queue: DispatchQueue,
          log: @escaping (RequestLogEntry) -> Void, onClose: @escaping () -> Void) {
        guard let url = rule.upstreamURL(path: req.path, rawQuery: req.rawQuery), let host = url.host else { return nil }
        let secure = url.scheme?.lowercased() == "https"
        let port = UInt16(url.port ?? (secure ? 443 : 80))
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let params: NWParameters
        if secure {
            let tls = NWProtocolTLS.Options()
            if ProxyForwarder.isLoopback(host) {   // dev certificates are self-signed
                sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, _, done in done(true) }, queue)
            }
            params = NWParameters(tls: tls)
        } else {
            params = .tcp
        }
        self.client = client; self.req = req; self.rule = rule; self.queue = queue; self.log = log
        self.onClose = onClose; self.target = url
        self.upstream = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
    }

    func start(buffered: Data, fail: @escaping (Int, String) -> Void) {
        upstream.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.upstream.stateUpdateHandler = { [weak self] s in
                    if case .failed = s { self?.close() }
                    if case .cancelled = s { self?.close() }
                }
                var out = self.upgradeRequest()
                out.append(buffered)
                self.upstream.send(content: out, completion: .contentProcessed { [weak self] err in
                    if err != nil { self?.close(); return }
                    self?.pumpDown()
                    self?.pumpUp()
                })
            case .failed, .waiting:
                self.upstream.stateUpdateHandler = nil
                self.upstream.cancel()
                if !self.logged {
                    self.logged = true
                    self.log(self.entry(status: 502, note: "→ \(self.rule.target) failed"))
                    fail(502, "Cannot reach \(self.rule.targetOrigin ?? self.rule.target). Is the server running?")
                    self.onClose()
                }
            default: break
            }
        }
        upstream.start(queue: queue)
    }

    func close() {
        guard !closed else { return }
        closed = true
        upstream.cancel()
        client.cancel()
        onClose()
    }

    // MARK: Request

    private func upgradeRequest() -> Data {
        let comps = URLComponents(url: target, resolvingAgainstBaseURL: false)
        var pathAndQuery = comps?.percentEncodedPath ?? "/"
        if pathAndQuery.isEmpty { pathAndQuery = "/" }
        if let q = comps?.percentEncodedQuery { pathAndQuery += "?" + q }
        var s = "\(req.method) \(pathAndQuery) HTTP/1.1\r\n"
        let origin = rule.targetOrigin
        var hostHeader = target.host ?? ""
        if let p = target.port { hostHeader += ":\(p)" }
        s += "Host: \(hostHeader)\r\n"
        for (name, value) in req.headers.sorted(by: { $0.key < $1.key }) {
            switch name {
            case "host", "content-length": continue
            case "origin": if let origin { s += "Origin: \(origin)\r\n" }
            case "referer": if let origin { s += "Referer: \(origin)/\r\n" }
            default: s += "\(name): \(value)\r\n"
            }
        }
        s += "\r\n"
        return Data(s.utf8)
    }

    // MARK: Pumping bytes

    private func pumpDown() {   // upstream → browser
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.bytesDown += Int64(data.count)
                self.noteResponse(data)
                self.client.send(content: data, completion: .contentProcessed { [weak self] err in
                    if err != nil { self?.close() } else if !isComplete { self?.pumpDown() }
                })
                if isComplete { self.close() }
            } else if isComplete || error != nil {
                self.noteClosedBeforeAnswer()
                self.close()
            } else {
                self.pumpDown()
            }
        }
    }

    private func pumpUp() {     // browser → upstream
        client.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty {
                self.bytesUp += Int64(data.count)
                self.upstream.send(content: data, completion: .contentProcessed { [weak self] err in
                    if err != nil { self?.close() } else if !isComplete { self?.pumpUp() }
                })
                if isComplete { self.close() }
            } else if isComplete || error != nil {
                self.close()
            } else {
                self.pumpUp()
            }
        }
    }

    // MARK: Logging

    /// Logs the upstream's status line once the head has arrived (101 when the upgrade worked).
    private func noteResponse(_ data: Data) {
        guard !logged else { return }
        responseHead.append(data)
        guard let end = responseHead.range(of: Data("\r\n\r\n".utf8)) else {
            if responseHead.count > 16 * 1024 { logged = true }
            return
        }
        logged = true
        let head = String(decoding: responseHead[responseHead.startIndex..<end.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let status = Int(lines.removeFirst().split(separator: " ").dropFirst().first ?? "") ?? 0
        var fields: [HTTPHeaderField] = []
        for l in lines {
            if let c = l.firstIndex(of: ":") {
                fields.append(HTTPHeaderField(name: String(l[..<c]), value: l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        var e = entry(status: status, note: status == 101 ? "WebSocket → \(rule.target)" : "→ \(rule.target)")
        e.responseHeaders = fields
        log(e)
    }

    private func noteClosedBeforeAnswer() {
        guard !logged else { return }
        logged = true
        log(entry(status: 502, note: "→ \(rule.target) closed the connection"))
    }

    private func entry(status: Int, note: String) -> RequestLogEntry {
        var e = RequestLogEntry(method: req.method, path: req.path, status: status, bytes: 0, note: note, category: .other)
        e.url = req.displayURL
        e.requestHeaders = HTTPHeaderField.sorted(req.headers)
        e.durationMs = Int(Date().timeIntervalSince(began) * 1000)
        e.upstreamURL = target.absoluteString
        return e
    }
}
