import Foundation

/// What the "remove this folder?" confirmation says.
enum RemovalPrompt {
    struct Consequence: Equatable {
        enum Kind { case stops, forgets, safe }
        let kind: Kind
        let text: String
    }

    static func title(for entry: ServerEntry) -> String {
        "Remove “\(entry.displayName)” from FolderServe?"
    }

    /// What will stop and be forgotten, and that the files themselves are not touched.
    static func consequences(for entry: ServerEntry, status: ServerStatus) -> [Consequence] {
        var list: [Consequence] = []
        switch status {
        case .running(let port): list.append(.init(kind: .stops, text: "Its server on port \(port) will stop."))
        case .finding: list.append(.init(kind: .stops, text: "Its server is starting and will be stopped."))
        default: break
        }
        var details: [String] = []
        if entry.customName != nil { details.append("custom name") }
        let rules = entry.options.proxyRules.count
        if rules > 0 { details.append(rules == 1 ? "1 proxy rule" : "\(rules) proxy rules") }
        let settings = details.isEmpty ? "Its settings will be forgotten." : "Its settings will be forgotten (\(details.joined(separator: ", ")))."
        list.append(.init(kind: .forgets, text: "It disappears from this list. " + settings))
        list.append(.init(kind: .safe, text: "The files in the folder are not deleted."))
        return list
    }

    /// The same content as one paragraph (used for accessibility).
    static func message(for entry: ServerEntry, status: ServerStatus) -> String {
        consequences(for: entry, status: status).map(\.text).joined(separator: " ")
    }
}
