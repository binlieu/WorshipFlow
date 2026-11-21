// OUT-001: a dedicated thread with a run loop that display links are scheduled on, so rendering never
// runs on the main thread.
import Foundation

// @unchecked Sendable: `runLoop` is written once before `start()` returns; `cancelled` is guarded by `lock`.
final class RunLoopThread: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private(set) var runLoop: RunLoop?
    private var thread: Thread?

    func start(name: String) {
        let ready = DispatchSemaphore(value: 0)
        let t = Thread { [self] in
            lock.lock(); runLoop = RunLoop.current; lock.unlock()
            ready.signal()
            while true {
                lock.lock(); let done = cancelled; lock.unlock()
                if done { break }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
            }
        }
        t.name = name
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
        ready.wait()
    }

    func stop() {
        lock.lock(); cancelled = true; lock.unlock()
        thread = nil
    }
}
