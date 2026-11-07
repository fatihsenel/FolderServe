import Foundation

/// The kind of web project a served folder looks like.
public enum ProjectKind: String, CaseIterable, Codable, Sendable {
    case angular, react, vue, svelte, next, nuxt, astro, vite, html

    public var displayName: String {
        switch self {
        case .angular: "Angular"
        case .react: "React"
        case .vue: "Vue"
        case .svelte: "Svelte"
        case .next: "Next.js"
        case .nuxt: "Nuxt"
        case .astro: "Astro"
        case .vite: "Vite"
        case .html: "HTML"
        }
    }
}

/// Best-effort detection of a folder's framework. Source folders are identified by
/// `package.json` / marker files; built output (`dist/`, `build/`) by markers in `index.html`.
/// Only reads small files directly inside `root`; never follows symlinks out of it.
public enum ProjectDetector {
    private static let maxFileBytes = 512 * 1024

    public static func detect(root: URL) -> ProjectKind? {
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: root.appendingPathComponent(name).path) }

        if exists("angular.json") { return .angular }
        if let deps = dependencyNames(root: root) {
            // Meta-frameworks before the libraries they are built on.
            let order: [(String, ProjectKind)] = [
                ("@angular/core", .angular), ("next", .next), ("nuxt", .nuxt), ("astro", .astro),
                ("@sveltejs/kit", .svelte), ("svelte", .svelte), ("vue", .vue), ("react", .react), ("vite", .vite),
            ]
            for (name, kind) in order where deps.contains(name) { return kind }
        }
        for (file, kind) in [("next.config.js", ProjectKind.next), ("next.config.mjs", .next), ("next.config.ts", .next),
                             ("nuxt.config.ts", .nuxt), ("nuxt.config.js", .nuxt), ("astro.config.mjs", .astro),
                             ("svelte.config.js", .svelte)] where exists(file) { return kind }

        guard let html = readSmallText(root.appendingPathComponent("index.html")) else { return nil }
        return detect(indexHTML: html) ?? .html
    }

    /// Heuristics for the `index.html` of built output. Returns nil when nothing specific is recognised.
    public static func detect(indexHTML html: String) -> ProjectKind? {
        func has(_ s: String) -> Bool { html.contains(s) }
        if has("ng-version") || has("<app-root") { return .angular }
        if has("/_next/") || has("__next") { return .next }
        if has("/_nuxt/") || has("__nuxt") { return .nuxt }
        if has("__sveltekit") { return .svelte }
        if has("astro-island") || has("content=\"Astro") { return .astro }
        let bundled = has("type=\"module\"") || has("static/js/main.")
        if bundled && (has("id=\"root\"")) { return .react }
        if bundled && has("id=\"app\"") { return .vue }
        return nil
    }

    private static func dependencyNames(root: URL) -> Set<String>? {
        guard let text = readSmallText(root.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        var names = Set<String>()
        for key in ["dependencies", "devDependencies", "peerDependencies"] {
            if let dict = json[key] as? [String: Any] { names.formUnion(dict.keys) }
        }
        return names
    }

    private static func readSmallText(_ url: URL) -> String? {
        let resolved = url.resolvingSymlinksInPath()
        let rootPath = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        guard resolved.path.hasPrefix(rootPath + "/"),
              let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= maxFileBytes,
              let data = try? Data(contentsOf: resolved) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
