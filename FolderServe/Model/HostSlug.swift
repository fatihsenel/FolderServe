import Foundation

/// A folder's name as a DNS label for `name.localhost` (browsers and curl send `*.localhost` to this Mac).
enum HostSlug {
    static let maxLength = 40

    static func make(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "i")
            .lowercased()
        var out = ""
        var lastWasDash = true   // swallows leading dashes
        for scalar in folded.unicodeScalars {
            if (scalar.value >= 97 && scalar.value <= 122) || (scalar.value >= 48 && scalar.value <= 57) {
                out.unicodeScalars.append(scalar); lastWasDash = false
            } else if !lastWasDash {
                out.append("-"); lastWasDash = true
            }
        }
        out = String(out.prefix(maxLength))
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "folder" : out
    }
}
