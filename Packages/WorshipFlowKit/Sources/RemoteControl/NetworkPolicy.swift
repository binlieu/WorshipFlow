// CUE-004: who may talk to the server (local-network peers only) and under which names (DNS-rebinding and cross-site defence).
import Foundation
import Network
import Synchronization

enum PeerAddress {
    /// IPv4-mapped IPv6 addresses are treated as the IPv4 address inside.
    private static func unmapped(_ raw: Data) -> Data {
        let b = Array(raw)
        if b.count == 16, b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return Data(b[12..<16]) }
        return Data(b)
    }

    static func isLocalNetwork(_ raw: Data) -> Bool {
        let b = Array(unmapped(raw))
        if b.count == 4 {
            switch (b[0], b[1]) {
            case (127, _), (10, _), (192, 168), (169, 254): return true
            case (172, let x) where (16...31).contains(x): return true
            default: return false
            }
        }
        if b.count == 16 {
            if b[0..<15].allSatisfy({ $0 == 0 }) && b[15] == 1 { return true }        // ::1
            if b[0] == 0xfe && (b[1] & 0xc0) == 0x80 { return true }                    // fe80::/10
            if (b[0] & 0xfe) == 0xfc { return true }                                    // fc00::/7
            return false
        }
        return false
    }

    /// A printable, stable key for rate limiting and events.
    static func key(_ raw: Data) -> String {
        let b = Array(unmapped(raw))
        if b.count == 4 { return b.map(String.init).joined(separator: ".") }
        return stride(from: 0, to: b.count, by: 2).map { String(format: "%02x%02x", b[$0], b.indices.contains($0 + 1) ? b[$0 + 1] : 0) }.joined(separator: ":")
    }

    static func raw(of endpoint: NWEndpoint?) -> Data? {
        guard case .hostPort(let host, _)? = endpoint else { return nil }
        switch host {
        case .ipv4(let a): return a.rawValue
        case .ipv6(let a): return a.rawValue
        default: return nil
        }
    }
}

struct HostPolicy: Sendable {
    let port: UInt16
    let allowedNames: Set<String>
    let localAddresses: @Sendable () -> [Data]

    init(port: UInt16, allowedNames: Set<String>, localAddresses: @escaping @Sendable () -> [Data]) {
        self.port = port
        self.allowedNames = Set(allowedNames.map { Self.normalise($0) })
        self.localAddresses = localAddresses
    }

    private static func normalise(_ s: String) -> String {
        var n = s.lowercased()
        if n.hasSuffix(".") { n.removeLast() }
        return n
    }

    /// This Mac's own names: localhost, its host name, and the short and `.local` forms of it.
    static func ownNames(extra: Set<String>) -> Set<String> {
        var names: Set<String> = ["localhost"]
        let host = ProcessInfo.processInfo.hostName.lowercased()
        if !host.isEmpty {
            names.insert(host)
            if let dot = host.firstIndex(of: ".") { names.insert(String(host[..<dot])) } else { names.insert(host + ".local") }
        }
        return names.union(extra)
    }

    /// The interface addresses of this Mac (raw bytes), read when asked.
    static func systemLocalAddresses() -> [Data] {
        var result: [Data] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return result }
        defer { freeifaddrs(list) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            if let sa = p.pointee.ifa_addr {
                if sa.pointee.sa_family == sa_family_t(AF_INET) {
                    sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { s in
                        withUnsafeBytes(of: s.pointee.sin_addr.s_addr) { result.append(Data($0)) }
                    }
                } else if sa.pointee.sa_family == sa_family_t(AF_INET6) {
                    sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { s in
                        withUnsafeBytes(of: s.pointee.sin6_addr) { result.append(Data($0)) }
                    }
                }
            }
            cur = p.pointee.ifa_next
        }
        return result
    }

    func isAllowedHost(_ header: String) -> Bool {
        guard !header.isEmpty, header.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return false }
        var hostPart: Substring
        var portPart: Substring?
        if header.hasPrefix("[") {
            guard let close = header.firstIndex(of: "]") else { return false }
            hostPart = header[header.index(after: header.startIndex)..<close]
            let rest = header[header.index(after: close)...]
            if rest.isEmpty { portPart = nil }
            else if rest.hasPrefix(":") { portPart = rest.dropFirst() }
            else { return false }
        } else {
            let pieces = header.split(separator: ":", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { return false }
            hostPart = pieces[0]
            portPart = pieces.count == 2 ? pieces[1] : nil
        }
        if let portPart {
            guard !portPart.isEmpty, portPart.count <= 5, portPart.allSatisfy({ $0.isASCII && $0.isNumber }),
                  UInt16(portPart) == port else { return false }
        }
        guard !hostPart.isEmpty else { return false }
        let host = Self.normalise(String(hostPart))
        // Only plain dotted decimal counts as an address; the shortened and hex forms some parsers accept are refused.
        let quad = host.split(separator: ".", omittingEmptySubsequences: false)
        let isDottedQuad = quad.count == 4 && quad.allSatisfy { (1...3).contains($0.count) && $0.allSatisfy { $0.isASCII && $0.isNumber } }
        if isDottedQuad, let v4 = IPv4Address(host) {
            return v4.rawValue == Data([127, 0, 0, 1]) || localAddresses().contains(v4.rawValue)
        }
        if let v6 = IPv6Address(host) {
            return v6.rawValue == IPv6Address.loopback.rawValue || localAddresses().contains(v6.rawValue)
        }
        return allowedNames.contains(host)
    }

    /// No Origin (not a browser, or a same-origin GET) is fine. If there is one it must be this server, over http.
    func isAllowedOrigin(_ origin: String?, host: String) -> Bool {
        guard let origin else { return true }
        return origin.lowercased() == "http://" + host.lowercased()
    }
}
