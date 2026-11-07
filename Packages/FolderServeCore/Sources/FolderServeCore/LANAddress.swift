import Foundation
import Darwin

/// This Mac's IPv4 addresses on the local network (Wi-Fi / Ethernet), for sharing a folder with a phone.
public enum LANAddress {
    public static func ipv4Addresses() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var found: [String] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = ptr.pointee
            guard let sa = i.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET),
                  Int32(i.ifa_flags) & IFF_UP != 0, Int32(i.ifa_flags) & IFF_LOOPBACK == 0,
                  String(cString: i.ifa_name).hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(cString: host)
            if !address.hasPrefix("169.254.") && !found.contains(address) { found.append(address) }
        }
        return found
    }
}
