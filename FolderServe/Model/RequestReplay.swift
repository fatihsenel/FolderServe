import Foundation
import FolderServeCore

/// Sends a captured request again to the server that answered it (the Replay button in the detail panel).
/// The new request shows up in Activity like any other, marked with the `X-FolderServe-Replay` header.
enum RequestReplay {
    enum Failure: Error, Equatable {
        case notRunning, bodyCutOff, bodyDropped, badURL

        var message: String {
            switch self {
            case .notRunning: "Start the server to replay this request."
            case .bodyCutOff: "The body was cut off when it was captured, so it can't be replayed."
            case .bodyDropped: "The body was dropped to keep memory use low, so it can't be replayed."
            case .badURL: "This request has no address to replay."
            }
        }
    }

    /// Headers the HTTP client sets itself.
    static let skippedHeaders: Set<String> = ["host", "content-length", "connection", "keep-alive", RequestLogEntry.replayHeader]

    /// The request to send. `base`: where the server is listening now (its port may differ from when the request was
    /// logged). Method, path, query, headers and, when it was captured whole, the body are kept.
    static func urlRequest(for entry: RequestLogEntry, base: URL?) -> Result<URLRequest, Failure> {
        guard let base, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return .failure(.notRunning) }
        let logged = URLComponents(string: entry.url.isEmpty ? entry.path : entry.url)
        guard let logged else { return .failure(.badURL) }
        parts.percentEncodedPath = logged.percentEncodedPath.isEmpty ? "/" : logged.percentEncodedPath
        parts.percentEncodedQuery = logged.percentEncodedQuery
        guard let url = parts.url else { return .failure(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = entry.method
        request.httpShouldHandleCookies = false           // send exactly the Cookie header that was logged
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        for h in entry.requestHeaders where !skippedHeaders.contains(h.name.lowercased()) && !h.name.hasPrefix(":") {
            request.setValue(h.value, forHTTPHeaderField: h.name)
        }
        request.setValue("1", forHTTPHeaderField: RequestLogEntry.replayHeader)

        let hasBodyMethod = !["GET", "HEAD", "OPTIONS"].contains(entry.method.uppercased())
        if hasBodyMethod {
            if entry.requestBodyTruncated { return .failure(.bodyCutOff) }
            if entry.bodiesDropped && entry.requestBody == nil { return .failure(.bodyDropped) }
            request.httpBody = entry.requestBody
        }
        return .success(request)
    }

    /// Sends the request once. Returns the status code, or a message when it could not be sent.
    /// Redirects are not followed (the status of the first answer is what was logged), and the self-signed
    /// certificate of FolderServe's own HTTPS is accepted for loopback only.
    static func send(_ request: URLRequest) async -> Result<Int, ReplayError> {
        let session = URLSession(configuration: .ephemeral, delegate: Delegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request)
            return .success((response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            return .failure(ReplayError(message: error.localizedDescription))
        }
    }

    struct ReplayError: Error, Equatable { var message: String }

    private final class Delegate: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }

        func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            let host = challenge.protectionSpace.host
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               host == "127.0.0.1" || host == "localhost" || host == "::1", let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}
