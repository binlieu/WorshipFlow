// CUE-002b (item 5): the remote server's `TokenStore` backed by the library. The server calls it synchronously from its own queue,
// so the records live in memory and every change is written behind, in order, by one task. Only salted hashes are stored.
import Foundation
import Synchronization
import Persistence
import RemoteControl

public final class LibraryTokenStore: TokenStore, Sendable {
    private enum Op: Sendable {
        case save(RemoteTokenRecord)
        case delete(UUID)
        case deleteAll
        case touch(UUID, Date)
        case barrier(CheckedContinuation<Void, Never>)
    }

    /// Writing `lastUsed` for every request would be a disk write per tap; the disk keeps it to once per this many seconds.
    static let touchInterval: TimeInterval = 30

    private let cache: Mutex<[UUID: StoredToken]>
    private let ops: AsyncStream<Op>.Continuation
    private let worker: Task<Void, Never>
    private final class Problem: Sendable { let text = Mutex<String?>(nil) }
    private let problem: Problem

    private init(library: LibraryStore, records: [StoredToken]) {
        cache = Mutex(Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
        let (stream, continuation) = AsyncStream<Op>.makeStream(bufferingPolicy: .unbounded)
        ops = continuation
        let problem = Problem()
        self.problem = problem
        worker = Task {
            for await op in stream {
                do {
                    switch op {
                    case .save(let r): try await library.saveRemoteToken(r)
                    case .delete(let id): try await library.deleteRemoteToken(id: id)
                    case .deleteAll: try await library.deleteAllRemoteTokens()
                    case .touch(let id, let at): try await library.touchRemoteToken(id: id, at: at)
                    case .barrier(let c): c.resume()
                    }
                } catch {
                    problem.text.withLock { $0 = "Paired devices could not be saved: \(error.localizedDescription)" }
                }
            }
        }
    }

    deinit { ops.finish() }

    public static func load(from library: LibraryStore) async throws -> LibraryTokenStore {
        let records = try await library.remoteTokens().map {
            StoredToken(id: $0.id, label: $0.label, salt: $0.salt, hash: $0.hash, createdAt: $0.createdAt, lastUsed: $0.lastUsed)
        }
        return LibraryTokenStore(library: library, records: records)
    }

    /// Waits until every change made so far has been written.
    public func flush() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in ops.yield(.barrier(c)) }
    }

    /// The newest write failure, for the operator to read.
    public var writeProblem: String? { problem.text.withLock { $0 } }

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
