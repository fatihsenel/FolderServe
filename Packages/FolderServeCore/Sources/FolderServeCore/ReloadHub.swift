import Foundation
import Network

/// What open pages should do after a change on disk.
public enum ReloadKind: Equatable, Sendable {
    /// Reload the whole page.
    case full
    /// Only stylesheets changed: pages re-fetch their linked stylesheets and keep their state (scroll position, forms, open menus).
    case styles

    /// `.styles` when every changed path belongs to a stylesheet, otherwise `.full` (also for an empty list, and for anything we cannot tell).
    public static func classify(paths: [String]) -> ReloadKind {
        guard !paths.isEmpty, paths.allSatisfy(isStylesheetFile) else { return .full }
        return .styles
    }

    /// A `.css` file, or the temporary / backup file an editor writes next to it while saving (`a.css.sb-1f2e`, `a.css~`, `.a.css.swp`,
    /// `a.css.tmp`): most editors save by writing a temp file and renaming it over the original, so both show up in one burst.
    /// Code that merely has `.css` in its name (`styles.css.ts`, `.css.js`) is not a stylesheet.
    static func isStylesheetFile(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if ext == "css" { return true }
        if codeExtensions.contains(ext) { return false }
        let name = url.lastPathComponent.lowercased()
        guard let r = name.range(of: ".css") else { return false }
        let after = name[r.upperBound...]
        return after.isEmpty || !(after.first!.isLetter || after.first!.isNumber)
    }

    private static let codeExtensions: Set<String> = ["js", "mjs", "cjs", "ts", "tsx", "jsx", "html", "htm", "json", "vue", "svelte", "php", "scss", "sass", "less"]

    var message: String { self == .styles ? "data: css\n\n" : "data: reload\n\n" }
}

/// Tracks open Server-Sent-Events connections. All access happens on the server's serial queue.
final class ReloadHub {
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func add(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        watchForClose(conn, id: id)
    }

    func broadcast(_ kind: ReloadKind = .full) { send(Data(kind.message.utf8)) }

    func ping() { send(Data(": ping\n\n".utf8)) }

    func removeAll() {
        for c in connections.values { c.cancel() }
        connections.removeAll()
    }

    private func send(_ data: Data) {
        for (id, conn) in connections {
            conn.send(content: data, completion: .contentProcessed { [weak self] err in
                if err != nil { self?.connections[id] = nil; conn.cancel() }
            })
        }
    }

    // Clients never send after the request; a completed/failed receive means they hung up.
    private func watchForClose(_ conn: NWConnection, id: ObjectIdentifier) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                self?.connections[id] = nil
                conn.cancel()
            } else {
                self?.watchForClose(conn, id: id)
            }
        }
    }
}
