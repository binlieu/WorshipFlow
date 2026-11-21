// HW-002: a real-time clock for the simulated card, so the app can run a simulated output live (ADR-0005 decision 5:
// the render clock of an SDI output is the device's completion callbacks, never a display link). It advances the
// device one frame period at a time on its own thread; tests keep using `SimulatedSDIDevice.advance(frames:)`.
// Simulated: it proves the scheduling loop, never the timing of a real card.
import Foundation

/// Something that drives a device's completion callbacks in real time. Started and stopped by each output that uses it.
public protocol SDIOutputClock: Sendable {
    func start()
    func stop()
}

/// One clock per simulated card. Reference counted: every `start()` needs a matching `stop()`, and the thread runs
/// while any user remains. The card has one clock, so every connector ticks at the rate of the first user's mode.
/// `@unchecked Sendable`: `users` and `thread` are only touched while holding `lock`.
public final class SimulatedClockDriver: SDIOutputClock, @unchecked Sendable {
    private let device: SimulatedSDIDevice
    /// The mode whose frame rate the clock ticks at.
    public let mode: SDIVideoMode
    private let periodNanoseconds: UInt64
    private let lock = NSLock()
    private var users = 0
    private var generation = 0
    private var thread: Thread?

    public init(device: SimulatedSDIDevice, mode: SDIVideoMode) {
        self.device = device
        self.mode = mode
        self.periodNanoseconds = UInt64(Double(mode.frameDurationValue) / Double(mode.timeScale) * 1_000_000_000)
    }

    /// True while any user has started the clock and not stopped it.
    public var isRunning: Bool { lock.withLock { users > 0 } }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        users += 1
        guard users == 1 else { return }
        generation += 1
        let mine = generation
        let t = Thread { [weak self] in self?.run(generation: mine) }
        t.name = "WorshipFlow.sdi.simulated-clock"
        t.qualityOfService = .userInteractive
        thread = t
        t.start()
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        guard users > 0 else { return }
        users -= 1
        if users == 0 {
            generation += 1        // the running thread sees a newer generation and returns
            thread = nil
        }
    }

    private func isCurrent(_ g: Int) -> Bool { lock.withLock { generation == g && users > 0 } }

    private func run(generation g: Int) {
        let period = periodNanoseconds
        guard period > 0 else { return }
        var deadline = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) + period
        while isCurrent(g) {
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            if now < deadline {
                var wait = timespec(tv_sec: 0, tv_nsec: Int(min(deadline - now, 5_000_000)))   // wake often so stop is prompt
                nanosleep(&wait, nil)
                continue
            }
            // A stalled thread catches up, but never by more than a few frames: the card keeps its own time.
            let behind = Int((now - deadline) / period)
            if behind > 4 { deadline = now }
            device.advance(frames: 1)
            deadline += period
        }
    }
}
