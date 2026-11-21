// STAGE-001a (LIVE-02): countdown and elapsed timers. Foundation only.
//
// A timer stores an anchor (`runningSince`) and an accumulated amount, never a ticking counter, so a value can be
// computed at any instant and a relaunch in the middle of a countdown shows the right time.
import Foundation

public struct ShowTimer: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Kind: Sendable, Equatable, Codable, Hashable {
        /// Counts down from this many seconds when started; keeps counting below zero.
        case countdown(seconds: TimeInterval)
        /// Counts up from zero when started.
        case elapsed
        /// Counts down to a wall-clock time. Needs no start.
        case countdownTo(Date)
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    /// Time (seconds since the reference date) at which the timer last started; nil while stopped.
    public private(set) var runningSince: TimeInterval?
    /// Seconds that ran before `runningSince`.
    public private(set) var accumulated: TimeInterval

    public init(id: UUID, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
        self.runningSince = nil
        self.accumulated = 0
    }

    public var isRunning: Bool {
        if case .countdownTo = kind { return true }
        return runningSince != nil
    }

    /// Starts or resumes. Does nothing when already running or when the timer follows the clock.
    public mutating func start(at now: TimeInterval) {
        if case .countdownTo = kind { return }
        guard runningSince == nil else { return }
        runningSince = now
    }

    /// Stops and keeps the time run so far. Does nothing when already stopped.
    public mutating func pause(at now: TimeInterval) {
        guard let since = runningSince else { return }
        accumulated += max(0, now - since)
        runningSince = nil
    }

    /// Stops and returns to the initial value.
    public mutating func reset() {
        runningSince = nil
        accumulated = 0
    }

    private func ran(at now: TimeInterval) -> TimeInterval {
        accumulated + (runningSince.map { max(0, now - $0) } ?? 0)
    }

    /// Seconds shown: remaining for countdowns (negative once over), run time for `.elapsed`.
    public func value(at now: TimeInterval) -> TimeInterval {
        switch kind {
        case .countdown(let seconds): return seconds - ran(at: now)
        case .elapsed: return ran(at: now)
        case .countdownTo(let date): return date.timeIntervalSinceReferenceDate - now
        }
    }

    /// True when a countdown has passed zero.
    public func isOverrun(at now: TimeInterval) -> Bool {
        if case .elapsed = kind { return false }
        return value(at: now) < 0
    }
}
