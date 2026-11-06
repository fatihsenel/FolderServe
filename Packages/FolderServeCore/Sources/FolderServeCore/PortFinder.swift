import Foundation
import Darwin

public enum PortFinder {
    /// First port in `startingAt...upTo` that can be bound on 127.0.0.1, or nil if none can.
    public static func firstFree(startingAt: UInt16, upTo: UInt16 = 65535) -> UInt16? {
        guard startingAt <= upTo else { return nil }
        for port in Int(startingAt)...Int(upTo) where canBind(UInt16(port)) {
            return UInt16(port)
        }
        return nil
    }

    private static func canBind(_ port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // Mirror NWListener: SO_REUSEADDR lets us rebind a port whose old connections linger in
        // TIME_WAIT, while an active listener on the same address still makes bind() fail.
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = UInt32(INADDR_LOOPBACK).bigEndian
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return rc == 0
    }
}
