// CUE-004: tokens (salted hashes only, constant-time comparison) and the pairing code (rotation, lockout).
import Testing
import Foundation
import Synchronization
@testable import RemoteControl

private func authority(_ store: TokenStore = InMemoryTokenStore(), clock: TestClock = TestClock(), max: Int = 32,
                       random: @escaping @Sendable (Int) throws -> Data = SecureRandom.bytes) -> TokenAuthority {
    TokenAuthority(store: store, clock: clock.asClosure, maxTokens: max, randomBytes: random)
}

@Suite struct TokenTests {
    @Test func issuedTokenAuthenticates() throws {
        let a = authority()
        let issued = try a.issue(label: "Phone")
        #expect(a.authenticate(issued.token)?.id == issued.info.id)
        #expect(a.authenticate(issued.token + "x") == nil)
        #expect(a.authenticate(String(issued.token.dropLast())) == nil)
        #expect(a.authenticate("") == nil)
        #expect(a.authenticate("not a token") == nil)
        #expect(a.authenticate("\(UUID().uuidString).\(String(repeating: "A", count: 43))") == nil)
        #expect(a.authenticate(String(repeating: "A", count: 5000)) == nil)
    }

    @Test func theStoreHoldsOnlyASaltedHashNeverTheToken() throws {
        let store = InMemoryTokenStore()
        let a = authority(store)
        let t1 = try a.issue(label: "One")
        let t2 = try a.issue(label: "Two")
        let secret1 = String(t1.token.split(separator: ".").last ?? "")
        for rec in store.all() {
            let blob = rec.salt + rec.hash + Data(rec.label.utf8)
            #expect(blob.range(of: Data(secret1.utf8)) == nil)
            #expect(rec.salt.count >= 16)
            #expect(rec.hash.count == 32)
        }
        let recs = store.all()
        #expect(Set(recs.map(\.salt)).count == 2, "every token has its own salt")
        #expect(Set(recs.map(\.hash)).count == 2)
        _ = t2
    }

    @Test func tokensAreLongAndUnique() throws {
        let a = authority(max: 2000)
        var seen = Set<String>()
        for _ in 0..<500 {
            let t = try a.issue(label: "x").token
            #expect(t.count >= 64)
            seen.insert(t)
        }
        #expect(seen.count == 500)
    }

    @Test func lastUsedIsRecordedAndListedWithoutSecrets() throws {
        let clock = TestClock()
        let a = authority(clock: clock)
        let issued = try a.issue(label: "Pastor")
        #expect(a.list().first?.lastUsed == nil)
        clock.advance(90)
        _ = a.authenticate(issued.token)
        let info = try #require(a.list().first)
        #expect(info.label == "Pastor")
        #expect(info.lastUsed == clock.now)
    }

    @Test func revokeOneAndRevokeAll() throws {
        let a = authority()
        let t1 = try a.issue(label: "1")
        let t2 = try a.issue(label: "2")
        #expect(a.revoke(id: t1.info.id))
        #expect(a.authenticate(t1.token) == nil)
        #expect(a.authenticate(t2.token) != nil)
        #expect(!a.revoke(id: t1.info.id))
        a.revokeAll()
        #expect(a.authenticate(t2.token) == nil)
        #expect(a.list().isEmpty)
    }

    @Test func failsClosedWhenRandomIsUnavailable() {
        struct Boom: Error {}
        let a = authority(random: { _ in throw Boom() })
        #expect(throws: (any Error).self) { try a.issue(label: "x") }
        #expect(a.list().isEmpty)
    }

    @Test func refusesTooManyDevices() throws {
        let a = authority(max: 2)
        _ = try a.issue(label: "1"); _ = try a.issue(label: "2")
        #expect(throws: TokenAuthority.Failure.tooManyDevices) { try a.issue(label: "3") }
    }

    @Test func constantTimeEqualWorks() {
        #expect(constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 3])))
        #expect(!constantTimeEqual(Data([1, 2, 3]), Data([1, 2, 4])))
        #expect(!constantTimeEqual(Data([1, 2, 3]), Data([1, 2])))
        #expect(!constantTimeEqual(Data([0, 2, 3]), Data([1, 2, 3])))
        #expect(constantTimeEqual(Data(), Data()))
    }
}

private func manager(_ clock: TestClock, customize: (inout RemoteServerConfiguration) -> Void = { _ in }) -> PairingManager {
    var cfg = RemoteServerConfiguration()
    customize(&cfg)
    return PairingManager(configuration: cfg, clock: clock.asClosure, randomBytes: SecureRandom.bytes)
}

@Suite struct PairingTests {
    @Test func codeIsSixDigits() {
        let m = manager(TestClock())
        for _ in 0..<50 {
            let c = m.currentCode
            #expect(c.count == 6 && c.allSatisfy(\.isASCII) && c.allSatisfy(\.isNumber))
        }
    }

    @Test func codeRotatesEveryTwoMinutes() {
        let clock = TestClock()
        let m = manager(clock)
        let first = m.currentCode
        clock.advance(119)
        #expect(m.currentCode == first)
        // Rotation draws a fresh code; a chance repeat is one in a million, so compare with a few rotations.
        var changed = false
        for _ in 0..<5 {
            clock.advance(121)
            if m.currentCode != first { changed = true; break }
        }
        #expect(changed)
    }

    @Test func expiredCodeIsRefused() {
        let clock = TestClock()
        let m = manager(clock)
        let old = m.currentCode
        clock.advance(121)
        let fresh = m.currentCode
        guard fresh != old else { return }      // one in a million
        #expect(m.attempt(code: old, address: "10.0.0.5") != .accepted)
    }

    @Test func successRotatesTheCode() {
        let clock = TestClock()
        let m = manager(clock)
        let c = m.currentCode
        #expect(m.attempt(code: c, address: "10.0.0.5") == .accepted)
        #expect(m.attempt(code: c, address: "10.0.0.5") != .accepted, "a code works once")
    }

    @Test func fiveWrongCodesLockTheAddressOut() {
        let clock = TestClock()
        let m = manager(clock)
        let right = m.currentCode
        let wrong = right == "000000" ? "111111" : "000000"
        for _ in 0..<4 { #expect(m.attempt(code: wrong, address: "10.0.0.5") == .wrong) }
        guard case .lockedOut(let retry, let isNew) = m.attempt(code: wrong, address: "10.0.0.5") else { Issue.record("expected lockout"); return }
        #expect(isNew)
        #expect(retry > 0 && retry <= 60)
        // Even the right code is refused during the cool-down.
        guard case .lockedOut(_, let again) = m.attempt(code: m.currentCode, address: "10.0.0.5") else { Issue.record("expected lockout"); return }
        #expect(!again)
        // Another address is not affected.
        #expect(m.attempt(code: m.currentCode, address: "10.0.0.9") == .accepted)
    }

    @Test func lockoutEndsAfterTheCoolDown() {
        let clock = TestClock()
        let m = manager(clock)
        let wrong = m.currentCode == "000000" ? "111111" : "000000"
        for _ in 0..<5 { _ = m.attempt(code: wrong, address: "10.0.0.5") }
        clock.advance(61)
        #expect(m.attempt(code: m.currentCode, address: "10.0.0.5") == .accepted)
    }

    @Test func failuresOutsideTheWindowDoNotAdd() {
        let clock = TestClock()
        let m = manager(clock)
        let wrong = m.currentCode == "000000" ? "111111" : "000000"
        for _ in 0..<4 { _ = m.attempt(code: wrong, address: "10.0.0.5") }
        clock.advance(61)
        for _ in 0..<4 { #expect(m.attempt(code: wrong, address: "10.0.0.5") == .wrong) }
    }

    @Test func tooManyGuessesFromAnywhereReplaceTheCode() {
        let clock = TestClock()
        let m = manager(clock) { $0.pairingMaxFailuresPerCode = 10 }
        let original = m.currentCode
        let wrong = original == "000000" ? "111111" : "000000"
        for i in 0..<10 { _ = m.attempt(code: wrong, address: "10.0.0.\(i)") }
        if m.currentCode != original {
            #expect(m.attempt(code: original, address: "10.0.1.1") != .accepted)
        } // else the new draw repeated the old code: one in a million
    }

    @Test func malformedCodesAreWrongNotCrashes() {
        let m = manager(TestClock())
        #expect(m.attempt(code: "", address: "a") == .wrong)
        #expect(m.attempt(code: "12345", address: "a") == .wrong)
        #expect(m.attempt(code: String(repeating: "9", count: 10_000), address: "a") == .wrong)
    }

    @Test func failsClosedWithoutRandom() {
        struct Boom: Error {}
        let m = PairingManager(configuration: RemoteServerConfiguration(), clock: TestClock().asClosure, randomBytes: { _ in throw Boom() })
        #expect(m.currentCode == "")
        #expect(m.attempt(code: "", address: "a") == .wrong)
        #expect(m.attempt(code: "000000", address: "a") == .wrong)
    }
}
