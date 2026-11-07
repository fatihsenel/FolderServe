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
    /// Listen on the local network too (phones, other computers). Off by default: the folder, and any proxy
    /// rule, is then reachable by everyone on the same network.
    public var shareOnNetwork = false

    public init(spaMode: Bool = true, liveReload: Bool = true, serveDotfiles: Bool = false, cors: Bool = false,
                proxyRules: [ProxyRule] = [], shareOnNetwork: Bool = false) {
        self.spaMode = spaMode
        self.liveReload = liveReload
        self.serveDotfiles = serveDotfiles
        self.cors = cors
        self.proxyRules = proxyRules
        self.shareOnNetwork = shareOnNetwork
    }

    // Older saved settings have no "cors" key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spaMode = try c.decodeIfPresent(Bool.self, forKey: .spaMode) ?? true
        liveReload = try c.decodeIfPresent(Bool.self, forKey: .liveReload) ?? true
        serveDotfiles = try c.decodeIfPresent(Bool.self, forKey: .serveDotfiles) ?? false
        cors = try c.decodeIfPresent(Bool.self, forKey: .cors) ?? false
        proxyRules = try c.decodeIfPresent([ProxyRule].self, forKey: .proxyRules) ?? []
        shareOnNetwork = try c.decodeIfPresent(Bool.self, forKey: .shareOnNetwork) ?? false
    }
}
