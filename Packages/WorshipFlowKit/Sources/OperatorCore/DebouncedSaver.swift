// OUT-004 / NFR-07: coalesced, time-bounded saving of edits. Foundation only.
import Foundation

/// A clock the saver waits on. The real one sleeps; `ManualSaveClock` is moved by hand in tests.
public protocol SaveClock: Sendable {
    /// Seconds on a monotonic scale. Only differences matter.
    @MainActor var now: TimeInterval { get }
    /// Returns after `seconds`, or throws `CancellationError` if the calling task is cancelled.
    @MainActor func sleep(for seconds: TimeInterval) async throws
}

/// The clock the app uses.
public struct RealSaveClock: SaveClock {
    public init() {}
    @MainActor public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    @MainActor public func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(max(0, seconds)))
    }
}

/// Collects the latest value and writes it `delay` seconds after the last change, but never later than
/// `maximumDelay` after the first unsaved change, so continuous typing still reaches the database.
/// `flush()` writes at once (resign active, quit, switching to another song). Writes never overlap and
/// happen in the order they were scheduled.
@MainActor
public final class DebouncedSaver<Value> {
    private let delay: TimeInterval
    private let maximumDelay: TimeInterval
    private let clock: any SaveClock
    private let write: @MainActor (Value) async -> Void

    private var pending: Value?
    private var firstPendingAt: TimeInterval?
    private var generation = 0
    private var timer: Task<Void, Never>?
    private var writes: Task<Void, Never>?

    public init(delay: TimeInterval = 2, maximumDelay: TimeInterval = 5, clock: any SaveClock = RealSaveClock(),
                write: @escaping @MainActor (Value) async -> Void) {
        self.delay = delay
        self.maximumDelay = max(maximumDelay, delay)
        self.clock = clock
        self.write = write
    }

    public var hasPending: Bool { pending != nil }

    /// Remembers `value` (replacing any earlier unsaved one) and restarts the wait.
    public func schedule(_ value: Value) {
        pending = value
        let now = clock.now
        let first = firstPendingAt ?? now
        firstPendingAt = first
        timer?.cancel()
        generation += 1
        let mine = generation
        let wait = max(0, min(delay, first + maximumDelay - now))
        timer = Task { @MainActor [weak self, clock] in
            do { try await clock.sleep(for: wait) } catch { return }
            guard let self, self.generation == mine, !Task.isCancelled else { return }
            self.timer = nil
            self.enqueueWrite()
        }
    }

    /// Writes any unsaved value now and returns once it, and any write already under way, is finished.
    public func flush() async {
        timer?.cancel()
        timer = nil
        generation += 1
        enqueueWrite()
        await writes?.value
    }

    private func enqueueWrite() {
        guard let value = pending else { return }
        pending = nil
        firstPendingAt = nil
        let previous = writes
        let write = self.write
        writes = Task { @MainActor in
            await previous?.value
            await write(value)
        }
    }
}

/// A clock that only moves when `advance(by:)` is called. For tests; lives here because the tests construct it.
@MainActor
public final class ManualSaveClock: SaveClock {
    private struct Sleeper {
        let id: Int
        let deadline: TimeInterval
        let continuation: CheckedContinuation<Void, Error>
    }

    public private(set) var current: TimeInterval = 0
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    public init() {}

    public var now: TimeInterval { current }

    public func sleep(for seconds: TimeInterval) async throws {
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers.append(Sleeper(id: id, deadline: current + max(0, seconds), continuation: continuation))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancelSleeper(id) }
        }
    }

    private func cancelSleeper(_ id: Int) {
        guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: i).continuation.resume(throwing: CancellationError())
    }

    /// Moves time forward, waking sleepers in deadline order and letting their work finish before the next.
    public func advance(by seconds: TimeInterval) async {
        await settle()      // let work scheduled just before this call register its sleep at the current time
        let target = current + seconds
        while let next = sleepers.filter({ $0.deadline <= target }).min(by: { ($0.deadline, $0.id) < ($1.deadline, $1.id) }) {
            sleepers.removeAll { $0.id == next.id }
            current = max(current, next.deadline)
            next.continuation.resume()
            await settle()
        }
        current = target
        await settle()
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }
}
