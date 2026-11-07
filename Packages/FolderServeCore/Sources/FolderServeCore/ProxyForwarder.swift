import Foundation
import Network

/// Forwards one request to a proxy rule's target and streams the answer back to the client connection.
/// Uses one ephemeral URLSession: no cookie jar or cache of its own, redirects are passed through to the
/// browser, and self-signed certificates are accepted for loopback targets only (e.g. ASP.NET's dev cert).
final class ProxyForwarder: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maxRequestBody = 32 * 1024 * 1024

    private let timeout: TimeInterval
    private var session: URLSession!
    private let delegateQueue: OperationQueue
    private let lock = NSLock()
    private var exchanges: [Int: Exchange] = [:]

    private final class Exchange {
        let conn: NWConnection
        let rule: ProxyRule
        let req: HTTPRequest
        let extraHeaders: [String: String]
        let log: (RequestLogEntry) -> Void
        let isHead: Bool
        var started = false
        var bodyless = false
        var bytes: Int64 = 0
        var status = 0
        init(conn: NWConnection, rule: ProxyRule, req: HTTPRequest, extra: [String: String], log: @escaping (RequestLogEntry) -> Void) {
            self.conn = conn; self.rule = rule; self.req = req; self.extraHeaders = extra; self.log = log
            self.isHead = req.method == "HEAD"
        }
    }

    init(timeout: TimeInterval) {
        self.timeout = timeout
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        super.init()
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = 0
        cfg.waitsForConnectivity = false
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: delegateQueue)
    }

    deinit { session.invalidateAndCancel() }

    // MARK: Entry point

    func forward(conn: NWConnection, req: HTTPRequest, body: Data, rule: ProxyRule, extraHeaders: [String: String],
                 log: @escaping (RequestLogEntry) -> Void, fail: @escaping (Int, String) -> Void) {
        guard let url = rule.upstreamURL(path: req.path, rawQuery: req.rawQuery) else {
            fail(502, "Invalid proxy rule for \(rule.normalizedPrefix)"); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = req.method
        request.timeoutInterval = timeout
        let origin = rule.targetOrigin
        let hop: Set<String> = ["host", "connection", "keep-alive", "proxy-authorization", "proxy-connection", "te",
                                "trailer", "upgrade", "transfer-encoding", "content-length", "accept-encoding"]
        for (name, value) in req.headers where !hop.contains(name) {
            switch name {
            case "origin": if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
            case "referer": if let origin { request.setValue(origin + "/", forHTTPHeaderField: "Referer") }
            default: request.setValue(value, forHTTPHeaderField: name)
            }
        }
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if !body.isEmpty { request.httpBody = body }

        let task = session.dataTask(with: request)
        let ex = Exchange(conn: conn, rule: rule, req: req, extra: extraHeaders, log: log)
        lock.lock(); exchanges[task.taskIdentifier] = ex; lock.unlock()
        task.resume()
    }

    private func exchange(_ task: URLSessionTask) -> Exchange? {
        lock.lock(); defer { lock.unlock() }
        return exchanges[task.taskIdentifier]
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust,
           Self.isLoopback(challenge.protectionSpace.host) {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Never follow redirects: the browser gets the 3xx and decides.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let ex = exchange(dataTask), let http = response as? HTTPURLResponse else { completionHandler(.cancel); return }
        ex.started = true
        ex.status = http.statusCode
        ex.bodyless = ex.isHead || http.statusCode == 204 || http.statusCode == 304 || http.statusCode < 200
        let head = Data(Self.responseHead(http, ex: ex).utf8)
        ex.conn.send(content: head, completion: .contentProcessed { [weak self] err in
            if err != nil { dataTask.cancel(); return }
            if ex.bodyless { self?.finish(dataTask) }
        })
        completionHandler(ex.bodyless ? .cancel : .allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let ex = exchange(dataTask), !data.isEmpty else { return }
        ex.bytes += Int64(data.count)
        var chunk = Data(String(data.count, radix: 16).utf8)
        chunk.append(Data("\r\n".utf8)); chunk.append(data); chunk.append(Data("\r\n".utf8))
        ex.conn.send(content: chunk, completion: .contentProcessed { err in if err != nil { dataTask.cancel() } })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let ex = exchange(task) else { return }
        if ex.bodyless && ex.started { return }   // already finished in didReceive response
        if let error, !ex.started {
            let (status, message) = Self.describe(error, rule: ex.rule)
            lock.lock(); exchanges[task.taskIdentifier] = nil; lock.unlock()
            let html = ErrorPage.html(status: status, message: message)
            var head = "HTTP/1.1 \(status) \(status == 504 ? "Gateway Timeout" : "Bad Gateway")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\n"
            for (k, v) in ex.extraHeaders { head += "\(k): \(v)\r\n" }
            head += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            ex.log(RequestLogEntry(method: ex.req.method, path: ex.req.path, status: status, bytes: Int64(html.utf8.count),
                                   note: "→ \(ex.rule.target) failed",
                                   category: .classify(path: ex.req.path, secFetchDest: ex.req.headers["sec-fetch-dest"], proxied: true)))
            ex.conn.send(content: Data((head + (ex.isHead ? "" : html)).utf8), contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { _ in ex.conn.cancel() })
            return
        }
        finish(task)
    }

    private func finish(_ task: URLSessionTask) {
        lock.lock(); let ex = exchanges.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let ex else { return }
        ex.log(RequestLogEntry(method: ex.req.method, path: ex.req.path, status: ex.status, bytes: ex.bytes,
                               note: "→ \(ex.rule.target)",
                               category: .classify(path: ex.req.path, secFetchDest: ex.req.headers["sec-fetch-dest"], proxied: true)))
        let tail: Data? = ex.bodyless ? nil : Data("0\r\n\r\n".utf8)
        ex.conn.send(content: tail, contentContext: .finalMessage, isComplete: true,
                     completion: .contentProcessed { _ in ex.conn.cancel() })
    }

    // MARK: Helpers

    private static func responseHead(_ http: HTTPURLResponse, ex: Exchange) -> String {
        let status = http.statusCode
        var s = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status).capitalized)\r\n"
        let drop: Set<String> = ["connection", "keep-alive", "proxy-authenticate", "proxy-connection", "te", "trailer",
                                 "transfer-encoding", "upgrade", "content-encoding", "strict-transport-security"]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String, let value = value as? String else { continue }
            let lower = name.lowercased()
            if drop.contains(lower) || lower.hasPrefix("access-control-") { continue }
            if lower == "content-length" && !ex.bodyless { continue }
            if lower == "set-cookie" {
                for cookie in ProxyRule.splitSetCookie(value) { s += "Set-Cookie: \(ProxyRule.rewriteSetCookie(cookie))\r\n" }
            } else if lower == "location" {
                s += "Location: \(ex.rule.rewriteLocation(value))\r\n"
            } else {
                s += "\(name): \(value)\r\n"
            }
        }
        for (k, v) in ex.extraHeaders { s += "\(k): \(v)\r\n" }
        if !ex.bodyless { s += "Transfer-Encoding: chunked\r\n" }
        s += "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        return s
    }

    private static func describe(_ error: Error, rule: ProxyRule) -> (Int, String) {
        let target = rule.targetOrigin ?? rule.target
        switch (error as? URLError)?.code {
        case .timedOut: return (504, "\(target) did not answer in time")
        case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed:
            return (502, "Cannot reach \(target). Is the API running?")
        case .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .serverCertificateHasBadDate,
             .secureConnectionFailed, .clientCertificateRequired:
            return (502, "Could not make a secure connection to \(target). Its certificate is not trusted (self-signed certificates are accepted only for localhost).")
        default: return (502, "Proxy error talking to \(target): \(error.localizedDescription)")
        }
    }

    static func isLoopback(_ host: String) -> Bool {
        let h = host.lowercased()
        return h == "localhost" || h.hasSuffix(".localhost") || h == "::1" || h == "[::1]" || h.hasPrefix("127.")
    }
}
