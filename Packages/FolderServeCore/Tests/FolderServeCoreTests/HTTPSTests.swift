import XCTest
import Security
@testable import FolderServeCore

private final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust { completionHandler(.useCredential, URLCredential(trust: trust)) }
        else { completionHandler(.performDefaultHandling, nil) }
    }
}

final class HTTPSTests: XCTestCase {
    private var root: URL!
    private var certDir: URL!
    private var server: StaticServer?
    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("https-\(UUID().uuidString)")
        root = base.appendingPathComponent("site"); certDir = base.appendingPathComponent("certs")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "<html><body>secure</body></html>".write(to: root.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
    override func tearDownWithError() throws { server?.stop(); try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    func testCertificateIsCreatedOnceAndReused() throws {
        _ = try LocalCertificate.identity(in: certDir)
        let pem = LocalCertificate.certificateURL(in: certDir)
        let first = try Data(contentsOf: pem)
        _ = try LocalCertificate.identity(in: certDir)
        XCTAssertEqual(try Data(contentsOf: pem), first, "a valid certificate must not be regenerated")
        XCTAssertFalse(FileManager.default.fileExists(atPath: certDir.appendingPathComponent("localhost.key").path), "the loose private key is removed")
    }

    func testServesOverTLSAndMarksRequestsSecure() async throws {
        let identity = try LocalCertificate.identity(in: certDir)
        server = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: false, https: true), identity: identity)
        let port = try await server!.start()
        let logged = LockedBox<[RequestLogEntry]>([])
        server?.onRequest = { logged.value.append($0) }
        let session = URLSession(configuration: .ephemeral, delegate: TrustAll(), delegateQueue: nil)
        let (data, response) = try await session.data(from: URL(string: "https://127.0.0.1:\(port)/")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("secure"))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(logged.value.first?.url, "https://127.0.0.1:\(port)/")
    }

    func testPlainHTTPToATLSServerIsNotServed() async throws {
        let identity = try LocalCertificate.identity(in: certDir)
        server = StaticServer(root: root, port: 0, options: ServeOptions(liveReload: false, https: true), identity: identity)
        let port = try await server!.start()
        XCTAssertNil(RawHTTP.get(port: port, "/")?.status)
    }

    func testSameOriginUsesTheRightScheme() {
        XCTAssertTrue(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8443", "origin": "https://127.0.0.1:8443"], secure: true))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8443", "origin": "http://127.0.0.1:8443"], secure: true))
        XCTAssertFalse(ProxyRule.isSameOriginRequest(headers: ["host": "127.0.0.1:8080", "origin": "https://127.0.0.1:8080"], secure: false))
    }

    func testOldSettingsDecodeWithHTTPSOff() throws {
        XCTAssertFalse(try JSONDecoder().decode(ServeOptions.self, from: Data(#"{"cors":true}"#.utf8)).https)
    }
}
