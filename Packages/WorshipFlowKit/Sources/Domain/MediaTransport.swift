// MEDIA-02 / MEDIA-03: play, pause and seek for one media item, as a pure value. Foundation only.
//
// Like `ShowTimer`, a transport stores an anchor (`anchor`) and a position, never a ticking counter, so the position
// can be computed at any instant. Times are seconds on whatever monotonic clock the caller uses; the transport only
// ever subtracts them.
import Foundation

public struct MediaTransport: Sendable, Equatable, Codable, Hashable {
    public enum Status: String, Sendable, Equatable, Codable, Hashable {
        /// Not started, or stopped. The position is where a seek left it (zero when untouched).
        case idle
        case playing
        case paused
        /// A clip that does not loop reached its duration. The position holds at the duration.
        case ended
    }

    private enum Phase: String, Sendable, Codable, Hashable {
        case idle, running, paused
    }

    /// Seconds. Zero means a still image or a duration that is not known: such an item never ends.
    public let duration: Double
    public let loops: Bool
    private var phase: Phase = .idle
    /// Position at `anchor` while running, or the held position otherwise.
    private var base: Double = 0
    private var anchor: Double = 0

    public init(duration: Double, loops: Bool) {
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        self.loops = loops
    }

    private var isSized: Bool { duration > 0 }

    /// Unwrapped position: `base` plus the time run since `anchor`.
    private func raw(at now: Double) -> Double {
        guard phase == .running else { return base }
        let elapsed = now.isFinite ? max(0, now - anchor) : 0
        return base + elapsed
    }

    public func status(at now: Double) -> Status {
        switch phase {
        case .idle: return .idle
        case .paused: return .paused
        case .running:
            if isSized, !loops, raw(at: now) >= duration { return .ended }
            return .playing
        }
    }

    /// Seconds into the item, always within 0...duration. A looping item wraps.
    public func position(at now: Double) -> Double {
        guard isSized else { return 0 }
        let r = raw(at: now)
        if loops { return r.truncatingRemainder(dividingBy: duration) }
        return min(duration, max(0, r))
    }

    /// Seconds left (zero for an item without a known duration, and for one that has ended).
    public func remaining(at now: Double) -> Double {
        guard isSized else { return 0 }
        return max(0, duration - position(at: now))
    }

    /// How many times a looping item has wrapped since it was last started or sought (zero otherwise).
    public func loopCount(at now: Double) -> Int {
        guard isSized, loops else { return 0 }
        return Int(saturating: (raw(at: now) / duration).rounded(.down))
    }

    /// Starts or resumes. After the end of a clip that does not loop, starts again from zero. Does nothing when playing.
    public mutating func play(at now: Double) {
        guard now.isFinite else { return }
        switch status(at: now) {
        case .playing: return
        case .ended: base = 0
        case .idle, .paused:
            if isSized, !loops, base >= duration { base = 0 }
        }
        anchor = now
        phase = .running
    }

    /// Holds the current position. Does nothing unless playing (a clip that has ended stays ended).
    public mutating func pause(at now: Double) {
        guard status(at: now) == .playing else { return }
        base = loops && isSized ? raw(at: now).truncatingRemainder(dividingBy: duration) : raw(at: now)
        phase = .paused
    }

    /// Moves to `seconds`, clamped to 0...duration. Keeps playing, pausing or idling as it was.
    public mutating func seek(to seconds: Double, at now: Double) {
        guard seconds.isFinite, now.isFinite else { return }
        var target = max(0, seconds)
        if isSized { target = min(duration, target) }
        if loops, isSized, target >= duration { target = 0 }
        base = target
        anchor = now
        // The phase is untouched: a clip that had ended is still running, so it plays on from the new position.
    }

    /// Back to idle at position zero.
    public mutating func stop() {
        phase = .idle
        base = 0
        anchor = 0
    }
}
