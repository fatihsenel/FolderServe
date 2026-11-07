import Foundation

/// The wording of the "remove this folder?" confirmation.
enum RemovalPrompt {
    static func title(for entry: ServerEntry) -> String {
        "Remove “\(entry.displayName)” from FolderServe?"
    }

    /// Says what will stop and be forgotten, and that the files themselves are not touched.
    static func message(for entry: ServerEntry, status: ServerStatus) -> String {
        var sentences: [String] = []
        switch status {
        case .running(let port): sentences.append("Its server on port \(port) will stop.")
        case .finding: sentences.append("Its server is starting and will be stopped.")
        default: break
        }

        var details: [String] = []
        if entry.customName != nil { details.append("custom name") }
        let rules = entry.options.proxyRules.count
        if rules > 0 { details.append(rules == 1 ? "1 proxy rule" : "\(rules) proxy rules") }
        let settings = details.isEmpty ? "its settings" : "its settings (\(details.joined(separator: ", ")))"
        sentences.append("It will disappear from this list and \(settings) will be forgotten.")

        sentences.append("The files in the folder are not deleted.")
        return sentences.joined(separator: " ")
    }
}
