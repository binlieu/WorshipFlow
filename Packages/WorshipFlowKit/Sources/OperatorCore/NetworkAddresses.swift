// CUE-002b (item 5): the addresses a phone on the same network can use to reach this Mac. Numbers, never the Mac's name.
import Foundation
import Darwin

public enum NetworkAddresses {
    /// Private IPv4 addresses of this Mac's up, non-loopback interfaces, in interface order.
    public static func local() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var found: [String] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let p = current {
            defer { current = p.pointee.ifa_next }
            guard let sa = p.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = Int32(p.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            var address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { continue }
            let text = String(cString: buffer)
            if isPrivate(text), !found.contains(text) { found.append(text) }
        }
        return found
    }

    static func isPrivate(_ text: String) -> Bool {
        let parts = text.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (192, 168): return true
        case (172, let x): return (16...31).contains(x)
        default: return false
        }
    }
}
