// CUE-004: random bytes, constant-time comparison, bearer tokens (salted hashes only) and the pairing code.
import Foundation
import CryptoKit
import Security
import Synchronization

enum SecureRandom {
    struct Failure: Error {}

    /// The system's cryptographically secure generator.
    @Sendable static func bytes(_ count: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: count)
        let status = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        guard status == errSecSuccess else { throw Failure() }
        return Data(buffer)
    }

    /// A uniform number in 0..<1_000_000 as six digits (rejection sampling, so no modulo bias).
    static func sixDigits(_ random: @Sendable (Int) throws -> Data) throws -> String {
        let limit: UInt32 = 4_294_000_000          // 4294 * 1_000_000, the largest multiple that fits
        while true {
            let d = try random(4)
            guard d.count == 4 else { throw Failure() }
            let v = d.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            if v < limit { return String(format: "%06d", v % 1_000_000) }
        }
    }
}

/// Compares without stopping at the first difference. Lengths are not secret.
func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for (x, y) in zip(a, b) { diff |= x ^ y }
    return diff == 0
}

// MARK: tokens

public struct TokenInfo: Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var createdAt: Date
    public var lastUsed: Date?
}

/// What must be stored for one paired device. The token itself is never in it.
public struct StoredToken: Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var salt: Data
    /// SHA-256 over salt then token secret.
    public var hash: Data
    public var createdAt: Date
    public var lastUsed: Date?

    public init(id: UUID, label: String, salt: Data, hash: Data, createdAt: Date, lastUsed: Date? = nil) {
        self.id = id
        self.label = label
        self.salt = salt
        self.hash = hash
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
}

/// The caller (the app) may persist these records; they are safe to write to disk.
public protocol TokenStore: Sendable {
    func add(_ record: StoredToken)
    func record(id: UUID) -> StoredToken?
    func all() -> [StoredToken]
    @discardableResult func remove(id: UUID) -> Bool
    func removeAll()
    func touch(id: UUID, at date: Date)
}

public final class InMemoryTokenStore: TokenStore {
    private let records = Mutex<[UUID: StoredToken]>([:])
    public init() {}
    public func add(_ record: StoredToken) { records.withLock { $0[record.id] = record } }
    public func record(id: UUID) -> StoredToken? { records.withLock { $0[id] } }
    public func all() -> [StoredToken] { records.withLock { $0.values.sorted { $0.createdAt < $1.createdAt } } }
    public func remove(id: UUID) -> Bool { records.withLock { $0.removeValue(forKey: id) != nil } }
    public func removeAll() { records.withLock { $0.removeAll() } }
    public func touch(id: UUID, at date: Date) { records.withLock { $0[id]?.lastUsed = date } }
}

/// Issues and checks bearer tokens. A token is `<id>.<secret>`; the id selects the record, the secret is 256 random bits
/// that exist only in the client and in the response that created them.
public final class TokenAuthority: Sendable {
    public enum Failure: Error, Sendable, Equatable { case tooManyDevices, randomUnavailable }

    private let store: TokenStore
    private let clock: @Sendable () -> Date
    private let maxTokens: Int
    private let randomBytes: @Sendable (Int) throws -> Data
    private let dummySalt = Data(repeating: 7, count: 16)

    init(store: TokenStore, clock: @escaping @Sendable () -> Date, maxTokens: Int,
         randomBytes: @escaping @Sendable (Int) throws -> Data) {
        self.store = store
        self.clock = clock
        self.maxTokens = maxTokens
        self.randomBytes = randomBytes
    }

    private static let secretAlphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    static func hash(salt: Data, secret: Data) -> Data { Data(SHA256.hash(data: salt + secret)) }

    func issue(label: String) throws -> (token: String, info: TokenInfo) {
        guard store.all().count < maxTokens else { throw Failure.tooManyDevices }
        let secretBytes: Data, salt: Data
        do { secretBytes = try randomBytes(32); salt = try randomBytes(16) } catch { throw Failure.randomUnavailable }
        guard secretBytes.count == 32, salt.count == 16 else { throw Failure.randomUnavailable }
        let secret = secretBytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let id = UUID()
        let now = clock()
        store.add(StoredToken(id: id, label: label, salt: salt, hash: Self.hash(salt: salt, secret: Data(secret.utf8)), createdAt: now))
        return ("\(id.uuidString).\(secret)", TokenInfo(id: id, label: label, createdAt: now, lastUsed: nil))
    }

    /// The device this token belongs to, or nil. Updates "last used".
    func authenticate(_ token: String) -> TokenInfo? {
        guard token.utf8.count <= 128, let dot = token.firstIndex(of: "."),
              let id = UUID(uuidString: String(token[..<dot])) else { return nil }
        let secret = String(token[token.index(after: dot)...])
        guard !secret.isEmpty, secret.allSatisfy({ Self.secretAlphabet.contains($0) }) else { return nil }
        let record = store.record(id: id)
        // Hash and compare even for an unknown id so timing does not tell which ids exist.
        let computed = Self.hash(salt: record?.salt ?? dummySalt, secret: Data(secret.utf8))
        guard let record, constantTimeEqual(computed, record.hash) else { return nil }
        let now = clock()
        store.touch(id: id, at: now)
        return TokenInfo(id: id, label: record.label, createdAt: record.createdAt, lastUsed: now)
    }

    func contains(id: UUID) -> Bool { store.record(id: id) != nil }
    func list() -> [TokenInfo] {
        store.all().map { TokenInfo(id: $0.id, label: $0.label, createdAt: $0.createdAt, lastUsed: $0.lastUsed) }
    }
    @discardableResult func revoke(id: UUID) -> Bool { store.remove(id: id) }
    func revokeAll() { store.removeAll() }
}

// MARK: pairing

enum PairingOutcome: Equatable {
    case accepted
    case wrong
    /// `isNew` is true for the attempt that started the cool-down.
    case lockedOut(retryAfter: TimeInterval, isNew: Bool)
}

/// The six-digit code the operator reads out, and the limit on guessing it.
final class PairingManager: Sendable {
    private struct Address { var failures: [Date] = []; var lockedUntil: Date? }
    private struct State {
        var code: String?
        var issuedAt: Date
        var failuresOnThisCode = 0
        var addresses: [String: Address] = [:]
    }

    private let config: RemoteServerConfiguration
    private let clock: @Sendable () -> Date
    private let randomBytes: @Sendable (Int) throws -> Data
    private let state: Mutex<State>

    init(configuration: RemoteServerConfiguration, clock: @escaping @Sendable () -> Date,
         randomBytes: @escaping @Sendable (Int) throws -> Data) {
        self.config = configuration
        self.clock = clock
        self.randomBytes = randomBytes
        self.state = Mutex(State(code: try? SecureRandom.sixDigits(randomBytes), issuedAt: clock()))
    }

    private func rotate(_ s: inout State, now: Date) {
        s.code = try? SecureRandom.sixDigits(randomBytes)
        s.issuedAt = now
        s.failuresOnThisCode = 0
    }

    private func rotateIfExpired(_ s: inout State, now: Date) {
        if now.timeIntervalSince(s.issuedAt) >= config.pairingCodeLifetime || now < s.issuedAt { rotate(&s, now: now) }
    }

    /// The code to show the operator. Empty if the system random source failed (nobody can pair then).
    var currentCode: String {
        state.withLock { s in
            let now = clock()
            rotateIfExpired(&s, now: now)
            return s.code ?? ""
        }
    }

    var expiresAt: Date {
        state.withLock { s in
            rotateIfExpired(&s, now: clock())
            return s.issuedAt.addingTimeInterval(config.pairingCodeLifetime)
        }
    }

    func rotateNow() { state.withLock { rotate(&$0, now: clock()) } }

    func attempt(code: String, address: String) -> PairingOutcome {
        state.withLock { s in
            let now = clock()
            rotateIfExpired(&s, now: now)
            var a = s.addresses[address] ?? Address()
            if let until = a.lockedUntil {
                if until > now { return .lockedOut(retryAfter: until.timeIntervalSince(now), isNew: false) }
                a.lockedUntil = nil
            }
            a.failures.removeAll { now.timeIntervalSince($0) >= config.pairingFailureWindow }
            let matches = constantTimeEqual(Data(code.utf8), Data((s.code ?? "").utf8)) && s.code != nil
            if matches {
                s.addresses[address] = nil
                rotate(&s, now: now)
                return .accepted
            }
            a.failures.append(now)
            s.failuresOnThisCode += 1
            var outcome = PairingOutcome.wrong
            if a.failures.count >= config.pairingMaxFailures {
                a.lockedUntil = now.addingTimeInterval(config.pairingLockout)
                a.failures = []
                outcome = .lockedOut(retryAfter: config.pairingLockout, isNew: true)
            }
            s.addresses[address] = a
            if s.failuresOnThisCode >= config.pairingMaxFailuresPerCode { rotate(&s, now: now) }
            if s.addresses.count > 256 {
                s.addresses = s.addresses.filter { ($0.value.lockedUntil ?? .distantPast) > now || !$0.value.failures.isEmpty }
                if s.addresses.count > 256 { s.addresses.removeAll() }
            }
            return outcome
        }
    }
}
