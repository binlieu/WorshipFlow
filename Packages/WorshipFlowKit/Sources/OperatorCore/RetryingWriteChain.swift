// FIX-B R12: an in-order chain of library writes that does not give up. A write that fails stays on a list, keyed by
// what it writes, and is tried again with back-off (2 s, 4 s, ... at most 30 s) and whenever `flush()` is called.
// A newer write to the same thing replaces a failed older one, so a stale value is never written over a newer one.
// Foundation only.
import Foundation

@MainActor
final class RetryingWriteChain {
    private struct Failed {
        var what: String
        var operation: @Sendable () async throws -> Void
    }

    private let clock: any SaveClock
    private let describe: (Error, String) -> String
    private var tail: Task<Void, Never>?
    private var failed: [String: Failed] = [:]
    private var failures = 0
    private var retry: Task<Void, Never>?
    /// The newest write queued for each key. A failing write that is no longer the newest is simply dropped.
    private var newest: [String: Int] = [:]

    /// Tests: called with the key just before each write; throwing makes that write fail.
    var interceptor: (@Sendable (String) async throws -> Void)?
    /// The reason the newest failure gave, while any write is still waiting to succeed; nil otherwise.
    private(set) var problem: String? { didSet { if problem != oldValue { onProblemChange?(problem) } } }
    var onProblemChange: (@MainActor (String?) -> Void)?
    /// Called once when writes start failing (not on every retry), with the full message for the error bar.
    var onFirstFailure: (@MainActor (String) -> Void)?

    init(clock: any SaveClock, describe: @escaping (Error, String) -> String) {
        self.clock = clock
        self.describe = describe
    }

    var hasFailedWrites: Bool { !failed.isEmpty }

    /// Queues a write behind the earlier ones. `key` names what it writes ("look:<id>"): it supersedes a failed write
    /// with the same key.
    func persist(key: String, what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        failed[key] = nil
        newest[key, default: 0] += 1
        enqueue(key: key, what: what, operation)
    }

    private func enqueue(key: String, what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        let mine = newest[key, default: 0]
        let previous = tail
        tail = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                try await self.interceptor?(key)
                try await operation()
                self.succeeded()
            } catch {
                self.fail(key: key, what: what, operation, error, sequence: mine)
            }
        }
    }

    private func succeeded() {
        guard failed.isEmpty else { return }
        problem = nil
        failures = 0
        retry?.cancel()
        retry = nil
    }

    private func fail(key: String, what: String, _ operation: @escaping @Sendable () async throws -> Void, _ error: Error,
                      sequence: Int) {
        // A newer write to the same key was queued behind this one: it wins, so there is nothing to retry.
        guard newest[key] == sequence else { return }
        failed[key] = Failed(what: what, operation: operation)
        let message = describe(error, what)
        let first = problem == nil
        problem = "Not saved yet: \(message)"
        if first { onFirstFailure?(message) }
        scheduleRetry()
    }

    private func scheduleRetry() {
        failures += 1
        let delay = min(30.0, 2.0 * pow(2.0, Double(failures - 1)))
        retry?.cancel()
        retry = Task { @MainActor [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.retry = nil
            self.retryNow()
        }
    }

    private func retryNow() {
        let todo = failed
        failed = [:]
        for (key, item) in todo.sorted(by: { $0.key < $1.key }) { enqueue(key: key, what: item.what, item.operation) }
    }

    /// Waits for every queued write, tries the failed ones again now, and waits for those too.
    func flush() async {
        await tail?.value
        if !failed.isEmpty {
            retry?.cancel()
            retry = nil
            retryNow()
            await tail?.value
        }
    }
}
