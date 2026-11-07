import Foundation

public struct RequestLogEntry: Sendable, Equatable {
    public var date: Date
    public var method: String
    public var path: String
    public var status: Int
    public var bytes: Int64
    /// e.g. "→ https://localhost:5003" for proxied requests.
    public var note: String?

    public init(date: Date = Date(), method: String, path: String, status: Int, bytes: Int64, note: String? = nil) {
        self.date = date
        self.method = method
        self.path = path
        self.status = status
        self.bytes = bytes
        self.note = note
    }
}
