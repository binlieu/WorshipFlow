// CUE-003: fan-out of values to any number of AsyncStream subscribers. Callable from any thread, including CoreMIDI's
// receive thread: a short lock, no allocation beyond the stream's own buffer, no actor hop.
import Foundation
import Synchronization

final class Broadcaster<Element: Sendable>: Sendable {
    private struct State {
        var next = 0
        var subscribers: [Int: AsyncStream<Element>.Continuation] = [:]
    }
    private let state = Mutex(State())
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    func subscribe() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: .bufferingNewest(capacity))
        let id = state.withLock { s -> Int in
            s.next += 1
            s.subscribers[s.next] = continuation
            return s.next
        }
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// Returns how many subscribers had to discard an older element to take this one.
    @discardableResult
    func send(_ value: Element) -> Int {
        let subs = state.withLock { Array($0.subscribers.values) }
        var dropped = 0
        for c in subs {
            if case .dropped = c.yield(value) { dropped += 1 }
        }
        return dropped
    }

    func finish() {
        let subs = state.withLock { s -> [AsyncStream<Element>.Continuation] in
            let all = Array(s.subscribers.values)
            s.subscribers = [:]
            return all
        }
        for c in subs { c.finish() }
    }
}
