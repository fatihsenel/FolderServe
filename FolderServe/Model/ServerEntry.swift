import Foundation
import FolderServeCore

struct ServerEntry: Codable, Identifiable, Equatable {
    var id: UUID
    /// Security-scoped bookmark for the served folder (empty only if one could not be created).
    var bookmark: Data
    var folderPath: String
    /// nil = pick automatically; non-nil = the user chose this exact port.
    var preferredPort: UInt16?
    var options: ServeOptions
    /// Whether the server should be running after the next launch.
    var autoStart: Bool

    /// Optional label chosen by the user. The folder on disk and the URL are not affected.
    var customName: String?

    var folderName: String { URL(fileURLWithPath: folderPath).lastPathComponent }
    var displayName: String { customName ?? folderName }
}

/// What the port search has found so far; drives the "finding a free port" animation.
struct PortSearch: Equatable {
    /// Ports that were checked and found in use, in the order they were tried.
    var busy: [UInt16]
    /// The port the server got, once known.
    var landed: UInt16?
    var began: Date
    /// How long the search is shown for (it is held for at least this long).
    var duration: TimeInterval
}

enum ServerStatus: Equatable {
    case finding(PortSearch)
    case stopped
    case running(port: UInt16)
    case error(String)
    case folderMissing
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let serverID: UUID
    let entry: RequestLogEntry
}
