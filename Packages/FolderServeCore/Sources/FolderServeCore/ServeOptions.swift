import Foundation

public struct ServeOptions: Codable, Equatable, Sendable {
    public var spaMode = true
    public var liveReload = true
    public var serveDotfiles = false
    /// Send CORS headers (and answer preflight requests) so pages from other origins can read the files.
    /// Off by default: with it on, any website open in your browser can read what is served.
    public var cors = false
    /// Requests under a rule's prefix are forwarded to its target instead of being served from the folder.
    public var proxyRules: [ProxyRule] = []
    /// Let the browser keep files and re-check them with an ETag (answered 304 when unchanged) instead of
    /// downloading everything on every reload. Off by default: every response is `no-store`.
    public var caching = false
    /// Serve over HTTPS with a self-signed localhost certificate (secure-context APIs, cookies, service workers).
    public var https = false
    /// Listen on the local network too (phones, other computers). Off by default: the folder, and any proxy
    /// rule, is then reachable by everyone on the same network.
    public var shareOnNetwork = false
    /// Show and open the folder as `name.localhost` instead of `127.0.0.1` (the server accepts both either way).
    public var friendlyHost = false
    /// Page the Open button (and "recent folders") opens, as a path with an optional query (`/docs/index.html`). Empty: the site root.
    public var openPath = ""
    /// Saved answers for exact paths; a matching request gets one instead of the folder or a proxy target.
    public var mocks: [MockRule] = []
    /// Forward the pages' console errors, warnings and uncaught errors to the app (a script is added to HTML pages). Off by default.
    public var captureConsole = false
    /// Wait this long before answering every request, to see loading states (0: off). Live reload's own connection is not delayed.
    public var responseDelayMs = 0
    public static let delayChoices = [0, 200, 500, 1000, 2000, 5000]
    public static let maxDelayMs = 10_000
    /// The delay actually applied: never negative, never more than ten seconds.
    public var effectiveDelayMs: Int { min(max(responseDelayMs, 0), Self.maxDelayMs) }

    public init(spaMode: Bool = true, liveReload: Bool = true, serveDotfiles: Bool = false, cors: Bool = false,
                proxyRules: [ProxyRule] = [], caching: Bool = false, https: Bool = false, shareOnNetwork: Bool = false,
                friendlyHost: Bool = false, openPath: String = "", mocks: [MockRule] = [], captureConsole: Bool = false, responseDelayMs: Int = 0) {
        self.spaMode = spaMode
        self.liveReload = liveReload
        self.serveDotfiles = serveDotfiles
        self.cors = cors
        self.proxyRules = proxyRules
        self.caching = caching
        self.https = https
        self.shareOnNetwork = shareOnNetwork
        self.friendlyHost = friendlyHost
        self.openPath = openPath
        self.mocks = mocks
        self.captureConsole = captureConsole
        self.responseDelayMs = responseDelayMs
    }

    // Older saved settings lack newer keys; they default to off (or on, for the original switches).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spaMode = try c.decodeIfPresent(Bool.self, forKey: .spaMode) ?? true
        liveReload = try c.decodeIfPresent(Bool.self, forKey: .liveReload) ?? true
        serveDotfiles = try c.decodeIfPresent(Bool.self, forKey: .serveDotfiles) ?? false
        cors = try c.decodeIfPresent(Bool.self, forKey: .cors) ?? false
        proxyRules = try c.decodeIfPresent([ProxyRule].self, forKey: .proxyRules) ?? []
        caching = try c.decodeIfPresent(Bool.self, forKey: .caching) ?? false
        https = try c.decodeIfPresent(Bool.self, forKey: .https) ?? false
        shareOnNetwork = try c.decodeIfPresent(Bool.self, forKey: .shareOnNetwork) ?? false
        friendlyHost = try c.decodeIfPresent(Bool.self, forKey: .friendlyHost) ?? false
        openPath = try c.decodeIfPresent(String.self, forKey: .openPath) ?? ""
        mocks = try c.decodeIfPresent([MockRule].self, forKey: .mocks) ?? []
        captureConsole = try c.decodeIfPresent(Bool.self, forKey: .captureConsole) ?? false
        responseDelayMs = try c.decodeIfPresent(Int.self, forKey: .responseDelayMs) ?? 0
    }
}
