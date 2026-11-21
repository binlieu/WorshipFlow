// HW-002: a real-time clock for the simulated card, so the app can run a simulated output live (ADR-0005 decision 5:
// the render clock of an SDI output is the device's completion callbacks, never a display link). It advances the
// device one frame period at a time on its own thread; tests keep using `SimulatedSDIDevice.advance(frames:)`.
// Simulated: it proves the scheduling loop, never the timing of a real card.
import Foundation

/// Where the simulated clock gets its time and how it waits (KI-060). The app uses the system's; a test supplies its own and
/// moves time by hand, so no test depends on how fast the machine runs.
public protocol SDIClockTimeSource: Sendable {
    /// A monotonic time in nanoseconds.
    func nowNanoseconds() -> UInt64
    /// Lets about this much time pass. May return early: the clock checks for a stop after every pause.
    func pause(nanoseconds: UInt64)
}

public struct SystemSDIClockTimeSource: SDIClockTimeSource {
    public init() {}
    public func nowNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    public func pause(nanoseconds: UInt64) {
        var wait = timespec(tv_sec: 0, tv_nsec: Int(min(nanoseconds, 999_999_999)))
        nanosleep(&wait, nil)
    }
}

/// The pacing rule of the simulated clock as a pure function of time: given "now", either wait or fire one frame.
/// A clock that stalls catches up, but never by more than a few frames: the card keeps its own time.
struct SDIClockPacer {
    /// The longest a pause lasts, so a stop is noticed promptly.
    static let wakeInterval: UInt64 = 5_000_000
    enum Step: Equatable { case wait(UInt64), advance }

    private let period: UInt64
    private var deadline: UInt64

    init(start: UInt64, period: UInt64) {
        self.period = period
        self.deadline = start + period
    }

    mutating func step(now: UInt64) -> Step {
        if now < deadline { return .wait(min(deadline - now, Self.wakeInterval)) }
        let behind = Int((now - deadline) / period)
        if behind > 4 { deadline = now }
        deadline += period
        return .advance
    }
}

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
    private let timeSource: any SDIClockTimeSource
    private let threads = DispatchGroup()
    private let lock = NSLock()
    private var users = 0
    private var generation = 0
    private var thread: Thread?

    public init(device: SimulatedSDIDevice, mode: SDIVideoMode, timeSource: any SDIClockTimeSource = SystemSDIClockTimeSource()) {
        self.device = device
        self.mode = mode
        self.timeSource = timeSource
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
        threads.enter()
        let t = Thread { [weak self] in
            self?.run(generation: mine)
            self?.threads.leave()
        }
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

    /// Blocks until every clock thread this driver started has returned. For tests, after `stop()`.
    func waitForThreadsToExit() { threads.wait() }

    private func run(generation g: Int) {
        guard periodNanoseconds > 0 else { return }
        var pacer = SDIClockPacer(start: timeSource.nowNanoseconds(), period: periodNanoseconds)
        while isCurrent(g) {
            switch pacer.step(now: timeSource.nowNanoseconds()) {
            case .wait(let ns): timeSource.pause(nanoseconds: ns)
            case .advance: device.advance(frames: 1)
            }
        }
    }
}
