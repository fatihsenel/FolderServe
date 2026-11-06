import Foundation
import Network

/// Tracks open Server-Sent-Events connections. All access happens on the server's serial queue.
final class ReloadHub {
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    func add(_ conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        watchForClose(conn, id: id)
    }

    func broadcast() { send(Data("data: reload\n\n".utf8)) }

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
