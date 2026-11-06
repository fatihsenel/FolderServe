import XCTest
import Darwin
@testable import FolderServeCore

final class StaticServerIntegrationTests: XCTestCase {
    var root: URL!
    var server: StaticServer!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("ss-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        server?.stop()
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func write(_ rel: String, _ body: String) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func start(_ options: ServeOptions = ServeOptions()) async throws -> UInt16 {
        server = StaticServer(root: root, port: 0, options: options)
        return try await server.start()
    }

    func testServesFileWithMIMEAndLength() async throws {
        try write("a.css", "body{}")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/a.css"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.headers["content-type"], "text/css; charset=utf-8")
        XCTAssertEqual(r.headers["content-length"], "6")
        XCTAssertEqual(r.text, "body{}")
    }

    func testHEADHasHeadersNoBody() async throws {
        try write("a.txt", "hello")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/a.txt", method: "HEAD"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.headers["content-length"], "5")
        XCTAssertEqual(r.body.count, 0)
    }

    func testIndexFallback() async throws {
        try write("sub/index.html", "<h1>hi</h1>")
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/sub/")?.text, "<h1>hi</h1>")
    }

    func testListing() async throws {
        try write("docs/a.txt", "x")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/docs/"))
        XCTAssertEqual(r.status, 200)
        XCTAssertTrue(r.text.contains("href=\"a.txt\""))
    }

    func testRedirectToTrailingSlash() async throws {
        try write("sub/a.txt", "x")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/sub?x=1"))
        XCTAssertEqual(r.status, 301)
        XCTAssertEqual(r.headers["location"], "/sub/?x=1")
    }

    func testTraversalReturns403() async throws {
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/../etc/passwd")?.status, 403)
        XCTAssertEqual(RawHTTP.get(port: port, "/%2e%2e/etc/passwd")?.status, 403)
        XCTAssertEqual(RawHTTP.get(port: port, "/a/%2E%2E/%2e%2e/x")?.status, 403)
    }

    func testMissingReturns404Page() async throws {
        let port = try await start(ServeOptions(spaMode: false))
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/nope.txt"))
        XCTAssertEqual(r.status, 404)
        XCTAssertTrue(r.text.contains("404"))
    }

    func testQueryStringIgnoredForLookup() async throws {
        try write("app.js", "1")
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/app.js?v=3")?.status, 200)
    }

    func testUnicodeFilename() async throws {
        try write("my file ü.html", "ok")
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/my%20file%20%C3%BC.html")?.text, "ok")
    }

    func testRange206PartialSuffixOpenEnded() async throws {
        try write("r.txt", "0123456789")
        let port = try await start()
        let a = try XCTUnwrap(RawHTTP.get(port: port, "/r.txt", headers: "Range: bytes=2-4\r\n"))
        XCTAssertEqual(a.status, 206)
        XCTAssertEqual(a.text, "234")
        XCTAssertEqual(a.headers["content-range"], "bytes 2-4/10")
        XCTAssertEqual(a.headers["content-length"], "3")
        XCTAssertEqual(RawHTTP.get(port: port, "/r.txt", headers: "Range: bytes=-3\r\n")?.text, "789")
        XCTAssertEqual(RawHTTP.get(port: port, "/r.txt", headers: "Range: bytes=7-\r\n")?.text, "789")
    }

    func testRangeBeyondEOF416WithContentRange() async throws {
        try write("r.txt", "0123456789")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/r.txt", headers: "Range: bytes=50-\r\n"))
        XCTAssertEqual(r.status, 416)
        XCTAssertEqual(r.headers["content-range"], "bytes */10")
    }

    func testHEADWithRange() async throws {
        try write("r.txt", "0123456789")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/r.txt", headers: "Range: bytes=2-4\r\n", method: "HEAD"))
        XCTAssertEqual(r.status, 206)
        XCTAssertEqual(r.headers["content-length"], "3")
        XCTAssertEqual(r.body.count, 0)
    }

    func testSPADeepLinkReturnsIndex200() async throws {
        try write("index.html", "<app/>")
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/users/42", headers: "Accept: text/html,application/xhtml+xml\r\n"))
        XCTAssertEqual(r.status, 200)
        XCTAssertEqual(r.text, "<app/>")
    }

    func testSPAMissingAssetReturns404() async throws {
        try write("index.html", "<app/>")
        let port = try await start()
        XCTAssertEqual(RawHTTP.get(port: port, "/missing.js", headers: "Accept: text/html\r\n")?.status, 404)
    }

    func testNonGETMethodReturns405() async throws {
        let port = try await start()
        let r = try XCTUnwrap(RawHTTP.get(port: port, "/", method: "POST"))
        XCTAssertEqual(r.status, 405)
        XCTAssertEqual(r.headers["allow"], "GET, HEAD")
    }

    func testMalformedRequestReturns400AndServerSurvives() async throws {
        try write("a.txt", "ok")
        let port = try await start()
        XCTAssertEqual(RawHTTP.request(port: port, "GARBAGE\r\n\r\n")?.status, 400)
        XCTAssertEqual(RawHTTP.get(port: port, "/a.txt")?.text, "ok")
    }

    func testBindsOnlyToLoopback() async throws {
        let port = try await start()
        var ifap: UnsafeMutablePointer<ifaddrs>?
        getifaddrs(&ifap)
        defer { freeifaddrs(ifap) }
        var lanIP: String?
        var p = ifap
        while let cur = p {
            let ifa = cur.pointee
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0, (ifa.ifa_flags & UInt32(IFF_UP)) != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                lanIP = String(cString: host)
                break
            }
            p = ifa.ifa_next
        }
        guard let ip = lanIP else { throw XCTSkip("no non-loopback IPv4 interface") }
        XCTAssertEqual(RawHTTP.openSocket(host: ip, port: port), -1, "server must not accept connections on \(ip)")
    }

    func testPortInUseThrows() async throws {
        let port = try await start()
        let second = StaticServer(root: root, port: port, options: ServeOptions())
        do {
            _ = try await second.start()
            second.stop()
            XCTFail("expected portInUse")
        } catch let StaticServerError.portInUse(p) {
            XCTAssertEqual(p, port)
        }
    }

    func testLargeFileStreamedWithoutMemorySpike() async throws {
        let big = root.appendingPathComponent("big.bin")
        fm.createFile(atPath: big.path, contents: nil)
        let fh = try FileHandle(forWritingTo: big)
        try fh.truncate(atOffset: 600 * 1024 * 1024)
        try fh.close()
        let port = try await start()

        let partial = try XCTUnwrap(RawHTTP.get(port: port, "/big.bin", headers: "Range: bytes=0-1048575\r\n"))
        XCTAssertEqual(partial.status, 206)
        XCTAssertEqual(partial.body.count, 1_048_576)

        let before = Self.footprint()
        _ = RawHTTP.request(port: port, "GET /big.bin HTTP/1.1\r\nHost: x\r\n\r\n", readLimit: 64 * 1024)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertLessThan(Self.footprint(), before + 150 * 1024 * 1024, "file must be streamed, not loaded")

        try write("ok.txt", "still alive")
        XCTAssertEqual(RawHTTP.get(port: port, "/ok.txt")?.text, "still alive")
    }

    func testOnRequestCallbackReportsStatusAndBytes() async throws {
        try write("a.txt", "hello")
        let exp = expectation(description: "logged")
        let box = LockedBox<RequestLogEntry?>(nil)
        server = StaticServer(root: root, port: 0, options: ServeOptions())
        server.onRequest = { entry in box.value = entry; exp.fulfill() }
        let port = try await server.start()
        _ = RawHTTP.get(port: port, "/a.txt")
        await fulfillment(of: [exp], timeout: 3)
        XCTAssertEqual(box.value?.method, "GET")
        XCTAssertEqual(box.value?.path, "/a.txt")
        XCTAssertEqual(box.value?.status, 200)
        XCTAssertEqual(box.value?.bytes, 5)
    }

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
