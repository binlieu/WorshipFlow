// CUE-004: one queue for everything that touches the target, so commands run one at a time in the order they arrived.
import Foundation
import Synchronization

final class CommandPump: Sendable {
    typealias Job = @Sendable () async -> Void

    private let maxPending: Int
    private final class Counter: Sendable {
        let value = Mutex(0)
    }
    private let pending = Counter()
    private let stopped = Mutex(false)
    private let continuation: AsyncStream<Job>.Continuation
    private let consumer: Task<Void, Never>

    init(maxPending: Int) {
        self.maxPending = maxPending
        let (stream, cont) = AsyncStream<Job>.makeStream(bufferingPolicy: .unbounded)
        self.continuation = cont
        let pending = self.pending
        self.consumer = Task {
            for await job in stream {
                if Task.isCancelled { break }
                await job()
                pending.value.withLock { $0 -= 1 }
            }
        }
    }

    /// Synchronous, so the order of calls is the order of execution. False when the queue is full or stopped.
    @discardableResult
    func submit(_ job: @escaping Job) -> Bool {
        if stopped.withLock({ $0 }) { return false }
        let accepted = pending.value.withLock { n -> Bool in
            if n >= maxPending { return false }
            n += 1
            return true
        }
        guard accepted else { return false }
        if case .terminated = continuation.yield(job) {
            pending.value.withLock { $0 -= 1 }
            return false
        }
        return true
    }

    func stop() {
        stopped.withLock { $0 = true }
        continuation.finish()
        consumer.cancel()
    }
}
