import Foundation

public struct ServeOptions: Codable, Equatable, Sendable {
    public var spaMode = true
    public var liveReload = true
    public var serveDotfiles = false
    /// Send CORS headers (and answer preflight requests) so pages from other origins can read the files.
    /// Off by default: with it on, any website open in your browser can read what is served.
    public var cors = false

    public init(spaMode: Bool = true, liveReload: Bool = true, serveDotfiles: Bool = false, cors: Bool = false) {
        self.spaMode = spaMode
        self.liveReload = liveReload
        self.serveDotfiles = serveDotfiles
        self.cors = cors
    }

    // Older saved settings have no "cors" key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spaMode = try c.decodeIfPresent(Bool.self, forKey: .spaMode) ?? true
        liveReload = try c.decodeIfPresent(Bool.self, forKey: .liveReload) ?? true
        serveDotfiles = try c.decodeIfPresent(Bool.self, forKey: .serveDotfiles) ?? false
        cors = try c.decodeIfPresent(Bool.self, forKey: .cors) ?? false
    }
}
