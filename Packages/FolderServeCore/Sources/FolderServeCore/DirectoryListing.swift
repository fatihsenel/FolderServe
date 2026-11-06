import Foundation

public enum DirectoryListing {
    public static func html(directory: URL, urlPath: String, showDotfiles: Bool) -> String {
        let fm = FileManager.default
        // The filesystem may hand back decomposed (NFD) names; present NFC so links match what browsers send.
        let names = ((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { $0.precomposedStringWithCanonicalMapping }
            .filter { showDotfiles || !$0.hasPrefix(".") }
        var folders: [String] = [], files: [String] = []
        for name in names {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: directory.appendingPathComponent(name).path, isDirectory: &isDir)
            if isDir.boolValue { folders.append(name) } else { files.append(name) }
        }
        let sorted = { (a: String, b: String) in a.localizedStandardCompare(b) == .orderedAscending }
        var rows: [String] = []
        if urlPath != "/" { rows.append(row(href: "../", label: "../")) }
        for f in folders.sorted(by: sorted) { rows.append(row(href: encode(f) + "/", label: f + "/")) }
        for f in files.sorted(by: sorted) { rows.append(row(href: encode(f), label: f)) }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Index of \(PageStyle.escape(urlPath))</title><style>\(PageStyle.css)</style></head>
        <body><main><h1>Index of \(PageStyle.escape(urlPath))</h1><ul>\(rows.joined())</ul></main></body></html>
        """
    }

    private static func encode(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    }

    private static func row(href: String, label: String) -> String {
        "<li><a href=\"\(href)\">\(PageStyle.escape(label))</a></li>"
    }
}
