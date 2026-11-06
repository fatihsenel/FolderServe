import Foundation

public enum Resolution: Equatable, Sendable {
    case file(URL)
    case directoryListing(URL)
    /// Same path with a trailing slash appended.
    case redirect(String)
    case notFound
    case forbidden
}

public struct PathResolver: Sendable {
    private let realRoot: URL
    private let options: ServeOptions

    public init(root: URL, options: ServeOptions) {
        self.realRoot = root.resolvingSymlinksInPath()
        self.options = options
    }

    public func resolve(path: String, acceptsHTML: Bool) -> Resolution {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if parts.contains("..") { return .forbidden }
        let components = parts.filter { $0 != "." }
        if !options.serveDotfiles, components.contains(where: { $0.hasPrefix(".") }) { return .forbidden }

        var candidate = realRoot
        for c in components { candidate.appendPathComponent(c) }
        let real = candidate.resolvingSymlinksInPath()
        guard real.path == realRoot.path || real.path.hasPrefix(realRoot.path + "/") else { return .forbidden }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: real.path, isDirectory: &isDir) {
            guard isDir.boolValue else { return .file(real) }
            if !path.hasSuffix("/") { return .redirect(path + "/") }
            let index = real.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: index.path) { return .file(index) }
            return .directoryListing(real)
        }
        return spaFallback(lastComponent: components.last, acceptsHTML: acceptsHTML) ?? .notFound
    }

    private func spaFallback(lastComponent: String?, acceptsHTML: Bool) -> Resolution? {
        guard options.spaMode, acceptsHTML else { return nil }
        if let last = lastComponent, last.contains(".") { return nil }
        let index = realRoot.appendingPathComponent("index.html")
        return FileManager.default.fileExists(atPath: index.path) ? .file(index) : nil
    }
}
