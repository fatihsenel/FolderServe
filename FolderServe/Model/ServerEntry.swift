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

    var displayName: String { URL(fileURLWithPath: folderPath).lastPathComponent }
}

enum ServerStatus: Equatable {
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
