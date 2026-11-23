// MEDIA-02 / MEDIA-03: play, pause and seek for one media item, as a pure value. Foundation only.
//
// Like `ShowTimer`, a transport stores an anchor (`anchor`) and a position, never a ticking counter, so the position
// can be computed at any instant. Times are seconds on whatever monotonic clock the caller uses; the transport only
// ever subtracts them.
//
// UI-007d: a clip may carry a mark in and a mark out. The transport then plays the part between them: it starts at the in
// mark, a clip that does not loop ends at the out mark, a loop wraps from the out mark back to the in mark. Positions stay in
// the clip's own time (the in mark is 10 s into the clip, not 0). A clip with no marks behaves exactly as before.
import Foundation

public struct MediaTransport: Sendable, Equatable, Codable, Hashable {
    public enum Status: String, Sendable, Equatable, Codable, Hashable {
        /// Not started, or stopped. The position is where a seek left it (the start of the played part when untouched).
        case idle
        case playing
        case paused
        /// A clip that does not loop reached its end (its out mark, or its duration). The position holds there.
        case ended
    }

    private enum Phase: String, Sendable, Codable, Hashable {
        case idle, running, paused
    }

    /// Seconds. Zero means a still image or a duration that is not known: such an item never ends (unless it has an out mark).
    public let duration: Double
    public let loops: Bool
    /// UI-007d: where playing starts and where it ends, in clip seconds, as they are used: nil when the clip has no mark that can work
    /// (a mark that is not a time inside the clip, or an in mark that is not before the out mark, is ignored and the whole clip plays).
    public let markIn: Double?
    public let markOut: Double?
    private var phase: Phase = .idle
    /// Position (clip seconds) at `anchor` while running, or the held position otherwise.
    private var base: Double = 0
    private var anchor: Double = 0

    public init(duration: Double, loops: Bool, markIn: Double? = nil, markOut: Double? = nil) {
        let length = duration.isFinite && duration > 0 ? duration : 0
        self.duration = length
        self.loops = loops
        let (usedIn, usedOut) = Self.usable(markIn: markIn, markOut: markOut, duration: length)
        self.markIn = usedIn
        self.markOut = usedOut
        self.base = usedIn ?? 0
    }

    /// The marks that can be used for a clip of `duration` seconds (0 when not known), or nil for each that cannot.
    private static func usable(markIn: Double?, markOut: Double?, duration: Double) -> (Double?, Double?) {
        var lo = markIn.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        var hi = markOut.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        if duration > 0 {
            if let h = hi { hi = min(h, duration) }
            if let l = lo, l >= duration { lo = nil }
        }
        let start = lo ?? 0
        let end = hi ?? duration
        guard end > start else { return (nil, nil) }       // no part left to play: ignore both marks
        if let h = hi, h == duration { hi = nil }          // the out mark at the very end is the whole clip's end
        if let l = lo, l == 0 { lo = nil }
        return (lo, hi)
    }

    /// Where the played part starts, in clip seconds.
    public var start: Double { markIn ?? 0 }
    /// Where the played part ends, in clip seconds: the out mark, else the duration (0 when neither is known).
    public var end: Double { markOut ?? duration }
    private var span: Double { end - start }
    private var isSized: Bool { span > 0 }

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
            if isSized, !loops, raw(at: now) >= end { return .ended }
            return .playing
        }
    }

    /// Seconds into the clip, within the played part (`start...end`). A looping item wraps.
    public func position(at now: Double) -> Double {
        guard isSized else { return 0 }
        let r = raw(at: now)
        if loops { return start + (r - start).truncatingRemainder(dividingBy: span) }
        return min(end, max(start, r))
    }

    /// Seconds left of the played part (zero for an item without a known end, and for one that has ended).
    public func remaining(at now: Double) -> Double {
        guard isSized else { return 0 }
        return max(0, end - position(at: now))
    }

    /// How many times a looping item has wrapped since it was last started or sought (zero otherwise).
    public func loopCount(at now: Double) -> Int {
        guard isSized, loops else { return 0 }
        return Int(saturating: ((raw(at: now) - start) / span).rounded(.down))
    }

    /// Starts or resumes. After the end of a clip that does not loop, starts again from the start of the played part. Does nothing when playing.
    public mutating func play(at now: Double) {
        guard now.isFinite else { return }
        switch status(at: now) {
        case .playing: return
        case .ended: base = start
        case .idle, .paused:
            if isSized, !loops, base >= end { base = start }
        }
        anchor = now
        phase = .running
    }

    /// Holds the current position. Does nothing unless playing (a clip that has ended stays ended).
    public mutating func pause(at now: Double) {
        guard status(at: now) == .playing else { return }
        base = loops && isSized ? start + (raw(at: now) - start).truncatingRemainder(dividingBy: span) : raw(at: now)
        phase = .paused
    }

    /// Moves to `seconds`, clamped to the played part. Keeps playing, pausing or idling as it was.
    public mutating func seek(to seconds: Double, at now: Double) {
        guard seconds.isFinite, now.isFinite else { return }
        var target = max(0, seconds)
        if isSized { target = min(end, max(start, target)) }
        if loops, isSized, target >= end { target = start }
        base = target
        anchor = now
        // The phase is untouched: a clip that had ended is still running, so it plays on from the new position.
    }

    /// Back to idle at the start of the played part.
    public mutating func stop() {
        phase = .idle
        base = start
        anchor = 0
    }
}
