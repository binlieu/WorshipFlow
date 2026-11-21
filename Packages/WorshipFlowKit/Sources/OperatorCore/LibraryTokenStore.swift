// CUE-002b (item 5): the remote server's `TokenStore` backed by the library. The server calls it synchronously from its own queue,
// so the records live in memory and every change is written behind, in order, by one task. Only salted hashes are stored.
import Foundation
import Synchronization
import Persistence
import RemoteControl

/// FIX-E: where the paired devices are written. The library; a test puts another behind it to make a write fail.
public protocol RemoteTokenPersistence: Sendable {
    func remoteTokens() async throws -> [RemoteTokenRecord]
    func saveRemoteToken(_ record: RemoteTokenRecord) async throws
    func deleteRemoteToken(id: UUID) async throws
    func deleteAllRemoteTokens() async throws
    func touchRemoteToken(id: UUID, at date: Date) async throws
}

extension LibraryStore: RemoteTokenPersistence {}

public final class LibraryTokenStore: TokenStore, Sendable {
    private enum Op: Sendable {
        case save(RemoteTokenRecord)
        case delete(UUID)
        case deleteAll
        case touch(UUID, Date)
        case barrier(CheckedContinuation<String?, Never>, WriteKind?)

        var isTouch: Bool { if case .touch = self { true } else { false } }
        var kind: WriteKind { switch self { case .delete, .deleteAll: .revokes; default: .pairings } }
    }

    /// Writing `lastUsed` for every request would be a disk write per tap; the disk keeps it to once per this many seconds.
    static let touchInterval: TimeInterval = 30

    private let cache: Mutex<[UUID: StoredToken]>
    private let ops: AsyncStream<Op>.Continuation
    private let worker: Task<Void, Never>
    /// Which failed writes a `flush` reports. A pairing and a revoke are reported apart, so that the notice for one
    /// cannot take away, and mislabel, the failure of the other.
    public enum WriteKind: Sendable { case pairings, revokes }
    private final class Problem: Sendable {
        let text = Mutex<[WriteKind: String]>([:])
        func take(_ kind: WriteKind?) -> String? {
            text.withLock { slots in
                if let kind { return slots.removeValue(forKey: kind) }
                let found = slots[.revokes] ?? slots[.pairings]
                slots.removeAll()
                return found
            }
        }
    }
    private let problem: Problem

    /// A failed write is tried again this many times in all, `retryDelay` apart, before it is reported.
    static let attempts = 3

    private init(library: any RemoteTokenPersistence, records: [StoredToken], retryDelay: Duration) {
        cache = Mutex(Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        let (stream, continuation) = AsyncStream<Op>.makeStream(bufferingPolicy: .unbounded)
        ops = continuation
        let problem = Problem()
        self.problem = problem
        worker = Task {
            for await op in stream {
                if case .barrier(let c, let kind) = op { c.resume(returning: problem.take(kind)); continue }
                var lastError: Error?
                for attempt in 0..<Self.attempts {
                    if attempt > 0 { try? await Task.sleep(for: retryDelay) }
                    do {
                        switch op {
                        case .save(let r): try await library.saveRemoteToken(r)
                        case .delete(let id): try await library.deleteRemoteToken(id: id)
                        case .deleteAll: try await library.deleteAllRemoteTokens()
                        case .touch(let id, let at): try await library.touchRemoteToken(id: id, at: at)
                        case .barrier: break
                        }
                        lastError = nil
                        break
                    } catch { lastError = error }
                }
                // A `lastUsed` that is not written is no loss; a pairing or a revoke that is not written is.
                if let lastError, !op.isTouch {
                    problem.text.withLock { $0[op.kind] = "Paired devices could not be saved: \(lastError.localizedDescription)" }
                }
            }
        }
    }

    deinit { ops.finish() }

    public static func load(from library: any RemoteTokenPersistence, retryDelay: Duration = .milliseconds(250)) async throws -> LibraryTokenStore {
        let records = try await library.remoteTokens().map {
            StoredToken(id: $0.id, label: $0.label, salt: $0.salt, hash: $0.hash, createdAt: $0.createdAt, lastUsed: $0.lastUsed)
        }
        return LibraryTokenStore(library: library, records: records, retryDelay: retryDelay)
    }

    /// Waits until every change made so far has been written (a failed write is tried again first). Returns the problem, in
    /// words for the operator, when a pairing or a revoke could not be written since the last flush; nil when all is saved.
    @discardableResult
    /// Waits for every write queued so far, then returns and clears the failure of the given kind (`nil`: of any kind).
    public func flush(_ kind: WriteKind? = nil) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in ops.yield(.barrier(c, kind)) }
    }

    /// The newest write failure not yet returned by `flush()`.
    public var writeProblem: String? { problem.text.withLock { $0[.revokes] ?? $0[.pairings] } }

    // MARK: TokenStore

    public func add(_ record: StoredToken) {
        cache.withLock { $0[record.id] = record }
        ops.yield(.save(Self.row(record)))
    }

    public func record(id: UUID) -> StoredToken? { cache.withLock { $0[id] } }
    public func all() -> [StoredToken] { cache.withLock { $0.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) } } }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        let removed = cache.withLock { $0.removeValue(forKey: id) != nil }
        if removed { ops.yield(.delete(id)) }
        return removed
    }

    public func removeAll() {
        cache.withLock { $0.removeAll() }
        ops.yield(.deleteAll)
    }

    public func touch(id: UUID, at date: Date) {
        let persist = cache.withLock { records -> Bool in
            guard var record = records[id] else { return false }
            let previous = record.lastUsed
            record.lastUsed = date
            records[id] = record
            return previous.map { date.timeIntervalSince($0) >= Self.touchInterval } ?? true
        }
        if persist { ops.yield(.touch(id, date)) }
    }

    private static func row(_ r: StoredToken) -> RemoteTokenRecord {
        RemoteTokenRecord(id: r.id, label: r.label, salt: r.salt, hash: r.hash, createdAt: r.createdAt, lastUsed: r.lastUsed)
    }
}
