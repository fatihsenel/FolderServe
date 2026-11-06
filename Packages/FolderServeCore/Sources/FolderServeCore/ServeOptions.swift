import Foundation

public struct ServeOptions: Codable, Equatable, Sendable {
    public var spaMode = true
    public var liveReload = true
    public var serveDotfiles = false

    public init(spaMode: Bool = true, liveReload: Bool = true, serveDotfiles: Bool = false) {
        self.spaMode = spaMode
        self.liveReload = liveReload
        self.serveDotfiles = serveDotfiles
    }
}
