// CUE-004: Host and Origin checks (DNS rebinding, cross-site calls), local-network peers, the serial command queue.
import Testing
import Foundation
import Synchronization
@testable import RemoteControl

private func addr(_ s: String) -> Data { Data(IPv4AddressBytes(s)) }
private func IPv4AddressBytes(_ s: String) -> [UInt8] { s.split(separator: ".").compactMap { UInt8($0) } }

@Suite struct HostPolicyTests {
    private let policy = HostPolicy(port: 8765, allowedNames: ["localhost", "sanctuary-mac.local", "sanctuary-mac"],
                                    localAddresses: { [Data([192, 168, 1, 20])] })

    @Test(arguments: [
        "localhost", "localhost:8765", "LOCALHOST:8765", "localhost.:8765", "sanctuary-mac.local:8765", "Sanctuary-Mac.local",
        "127.0.0.1", "127.0.0.1:8765", "192.168.1.20:8765", "[::1]:8765", "[::1]",
    ])
    func allowsOwnNamesAndAddresses(_ host: String) {
        #expect(policy.isAllowedHost(host), "\(host)")
    }

    @Test(arguments: [
        "evil.example.com", "evil.example.com:8765", "localhost.evil.com", "sanctuary-mac.local.evil.com", "192.168.1.99:8765",
        "8.8.8.8", "localhost:9999", "localhost:", "localhost:80a", "", " ", "localhost 8765", "[::2]:8765", "::1", "localhost:8765:1",
        "127.0.0.1.nip.io", "0x7f.1", "2130706433", "localhost\u{0}", "a@localhost", "localhost/x",
    ])
    func refusesEverythingElse(_ host: String) {
        #expect(!policy.isAllowedHost(host), "\(host)")
    }

    @Test func additionalNamesAreHonoured() {
        let p = HostPolicy(port: 80, allowedNames: ["localhost", "church-remote.lan"], localAddresses: { [] })
        #expect(p.isAllowedHost("church-remote.lan"))
        #expect(!p.isAllowedHost("other.lan"))
    }

    @Test func originMustMatchTheHostOrBeAbsent() {
        #expect(policy.isAllowedOrigin(nil, host: "localhost:8765"))
        #expect(policy.isAllowedOrigin("http://localhost:8765", host: "localhost:8765"))
        #expect(policy.isAllowedOrigin("HTTP://LocalHost:8765", host: "localhost:8765"))
        #expect(!policy.isAllowedOrigin("http://evil.example.com", host: "localhost:8765"))
        #expect(!policy.isAllowedOrigin("null", host: "localhost:8765"))
        #expect(!policy.isAllowedOrigin("https://localhost:8765", host: "localhost:8765"))
        #expect(!policy.isAllowedOrigin("", host: "localhost:8765"))
    }
}

@Suite struct PeerAddressTests {
    @Test(arguments: [
        [127, 0, 0, 1], [10, 1, 2, 3], [172, 16, 0, 1], [172, 31, 255, 255], [192, 168, 0, 5], [169, 254, 3, 3],
    ] as [[UInt8]])
    func localIPv4(_ b: [UInt8]) { #expect(PeerAddress.isLocalNetwork(Data(b))) }

    @Test(arguments: [
        [8, 8, 8, 8], [172, 32, 0, 1], [172, 15, 0, 1], [192, 169, 0, 1], [100, 64, 0, 1], [1, 1, 1, 1], [0, 0, 0, 0], [224, 0, 0, 1],
    ] as [[UInt8]])
    func publicIPv4(_ b: [UInt8]) { #expect(!PeerAddress.isLocalNetwork(Data(b))) }

    @Test func ipv6() {
        var loop = [UInt8](repeating: 0, count: 16); loop[15] = 1
        #expect(PeerAddress.isLocalNetwork(Data(loop)))
        var ll = [UInt8](repeating: 0, count: 16); ll[0] = 0xfe; ll[1] = 0x80; ll[15] = 5
        #expect(PeerAddress.isLocalNetwork(Data(ll)))
        var ula = [UInt8](repeating: 0, count: 16); ula[0] = 0xfd; ula[15] = 5
        #expect(PeerAddress.isLocalNetwork(Data(ula)))
        var global = [UInt8](repeating: 0, count: 16); global[0] = 0x20; global[1] = 0x01; global[15] = 5
        #expect(!PeerAddress.isLocalNetwork(Data(global)))
        var mappedLocal = [UInt8](repeating: 0, count: 16); mappedLocal[10] = 0xff; mappedLocal[11] = 0xff
        mappedLocal[12] = 192; mappedLocal[13] = 168; mappedLocal[14] = 1; mappedLocal[15] = 9
        #expect(PeerAddress.isLocalNetwork(Data(mappedLocal)))
        var mappedPublic = mappedLocal; mappedPublic[12] = 8; mappedPublic[13] = 8; mappedPublic[14] = 8; mappedPublic[15] = 8
        #expect(!PeerAddress.isLocalNetwork(Data(mappedPublic)))
        #expect(!PeerAddress.isLocalNetwork(Data([1, 2, 3])))
        #expect(!PeerAddress.isLocalNetwork(Data()))
    }

    @Test func keyNormalisesMappedAddresses() {
        var mapped = [UInt8](repeating: 0, count: 16); mapped[10] = 0xff; mapped[11] = 0xff
        mapped[12] = 192; mapped[13] = 168; mapped[14] = 1; mapped[15] = 9
        #expect(PeerAddress.key(Data(mapped)) == "192.168.1.9")
        #expect(PeerAddress.key(Data([10, 0, 0, 1])) == "10.0.0.1")
    }
}

@Suite struct CommandPumpTests {
    @Test func runsJobsOneAtATimeInSubmissionOrder() async {
        let pump = CommandPump(maxPending: 1000)
        let log = Mutex<[String]>([])
        let active = Mutex(0)
        let overlap = Mutex(false)
        let done = Mutex(0)
        for i in 0..<100 {
            let accepted = pump.submit {
                active.withLock { $0 += 1; if $0 > 1 { overlap.withLock { $0 = true } } }
                log.withLock { $0.append("b\(i)") }
                if i % 7 == 0 { try? await Task.sleep(nanoseconds: 2_000_000) }
                log.withLock { $0.append("e\(i)") }
                active.withLock { $0 -= 1 }
                done.withLock { $0 += 1 }
            }
            #expect(accepted)
        }
        for _ in 0..<500 where done.withLock({ $0 }) < 100 { try? await Task.sleep(nanoseconds: 10_000_000) }
        #expect(done.withLock { $0 } == 100)
        #expect(!overlap.withLock { $0 })
        let expected = (0..<100).flatMap { ["b\($0)", "e\($0)"] }
        #expect(log.withLock { $0 } == expected)
        pump.stop()
    }

    @Test func refusesWhenTooManyAreWaitingAndAfterStop() async {
        let pump = CommandPump(maxPending: 3)
        let gate = Mutex(false)
        for _ in 0..<3 {
            #expect(pump.submit { while !gate.withLock({ $0 }) { try? await Task.sleep(nanoseconds: 5_000_000) } })
        }
        #expect(!pump.submit { })
        gate.withLock { $0 = true }
        pump.stop()
        #expect(!pump.submit { })
    }
}
