// FIX-C / S9 (HW-002): renders SDI frames ahead of the card, on a thread of its own, into a small bounded queue.
//
// Why: the card's completion callback used to render, wait for the GPU, read back and copy about 8 MB on the SDK's own
// thread (the review's S9). Now that thread only calls `next()`, which takes a finished frame out of the queue under a
// short lock, or answers nil when none is ready (the session then repeats the last frame and counts the repeat).
//
// Threading: one render thread per instance, started by `start` and ended by `stop`. `condition` guards every stored
// property after init. The render closure runs outside the lock. Frames are the renderer's own ring buffers (value
// semantics, reference counted): nothing is allocated per frame here.
import Foundation
import SDIEngine

/// Simulated only: no card, no vendor SDK has run this.
final class SDIRenderAhead: @unchecked Sendable {
    typealias Render = @Sendable () -> SDIFrame?

    private let depth: Int
    private let pacing: SDIRenderPacing
    private let frameInterval: TimeInterval
    private let render: Render

    private let condition = NSCondition()
    private var slots: [SDIFrame?]
    private var head = 0
    private var count = 0
    private var running = false
    private var generation = 0
    /// Lockstep: frames the callback is waiting for and the render thread has not started on yet.
    private var wanted = 0
    /// Render attempts that produced no frame, so a lockstep caller stops waiting for a frame that will not come.
    private var failedAttempts = 0
    private var exited: DispatchSemaphore?

    /// - Parameters:
    ///   - depth: the most finished frames waiting (free pacing). At least 1.
    ///   - frameInterval: how long the render thread backs off after a render that gave no frame, so a failing renderer does not spin.
    init(depth: Int, pacing: SDIRenderPacing, frameInterval: TimeInterval, render: @escaping Render) {
        self.depth = max(1, depth)
        self.pacing = pacing
        self.frameInterval = max(0.001, frameInterval)
        self.render = render
        self.slots = Array(repeating: nil, count: max(1, depth))
    }

    /// Starts the render thread. With `prefill` > 0 it waits (up to `timeout` seconds) until that many frames are ready,
    /// so the session's preroll takes real frames instead of repeating black. Call from the output's own queue, never
    /// from the main thread or a callback. Starting twice does nothing.
    func start(prefill: Int, timeout: TimeInterval) {
        condition.lock()
        guard !running else { condition.unlock(); return }
        running = true
        generation += 1
        head = 0; count = 0; wanted = 0; failedAttempts = 0
        for i in slots.indices { slots[i] = nil }
        let mine = generation
        let done = DispatchSemaphore(value: 0)
        exited = done
        condition.unlock()

        let thread = Thread { [self] in
            loop(generation: mine)
            done.signal()
        }
        thread.name = "WorshipFlow.sdi.render"
        thread.qualityOfService = .userInteractive
        thread.start()

        guard prefill > 0, pacing == .free else { return }
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        while running, generation == mine, count < min(prefill, depth), failedAttempts == 0 {
            if !condition.wait(until: deadline) { break }
        }
        condition.unlock()
    }

    /// Ends the render thread and drops the queued frames. Waits (bounded) for a frame that is mid-render to finish, so
    /// nothing renders after this returns in the normal case. Safe to call more than once.
    func stop(timeout: TimeInterval = 1.0) {
        condition.lock()
        let done = exited
        let wasRunning = running
        running = false
        exited = nil
        for i in slots.indices { slots[i] = nil }
        head = 0; count = 0; wanted = 0
        condition.broadcast()
        condition.unlock()
        if wasRunning { _ = done?.wait(timeout: .now() + timeout) }
    }

    /// The next finished frame, or nil. Free pacing: never waits. Lockstep: asks for one frame and waits for it.
    func next() -> SDIFrame? {
        condition.lock()
        defer { condition.unlock() }
        guard running else { return nil }
        if pacing == .lockstep, count == 0 {
            wanted += 1
            let attempts = failedAttempts
            let mine = generation
            condition.broadcast()
            let deadline = Date().addingTimeInterval(5)
            while running, generation == mine, count == 0, failedAttempts == attempts {
                if !condition.wait(until: deadline) { break }
            }
        }
        guard count > 0, let frame = slots[head] else { return nil }
        slots[head] = nil
        head = (head + 1) % slots.count
        count -= 1
        condition.broadcast()                 // a free slot: the render thread may start the next frame
        return frame
    }

    var queuedFrames: Int { condition.lock(); defer { condition.unlock() }; return count }

    // MARK: Render thread

    private func loop(generation mine: Int) {
        while true {
            condition.lock()
            while running, generation == mine, !shouldRender { condition.wait() }
            guard running, generation == mine else { condition.unlock(); return }
            if pacing == .lockstep { wanted -= 1 }
            condition.unlock()

            let frame = render()

            condition.lock()
            guard running, generation == mine else { condition.unlock(); return }
            if let frame {
                slots[(head + count) % slots.count] = frame
                count += 1
            } else {
                failedAttempts += 1
            }
            condition.broadcast()
            condition.unlock()
            if frame == nil { Thread.sleep(forTimeInterval: frameInterval) }
        }
    }

    /// Call with the lock held.
    private var shouldRender: Bool {
        switch pacing {
        case .free: return count < depth
        case .lockstep: return wanted > 0 && count == 0
        }
    }
}
