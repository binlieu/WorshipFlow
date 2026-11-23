// OUT-002b: when each dropped or late frame happened (reporting only). A fixed-size log the render thread appends to.
import Foundation

/// What one presentation did to the cadence, computed from numbers `FrameStatistics` already had. `nil` for the first presentation.
public struct PresentationOutcome: Sendable, Equatable {
    /// Seconds since the previous presentation.
    public var gap: Double
    /// Whole target intervals with no presentation (counted as dropped frames).
    public var missed: Int
    /// The gap exceeded 1.5 target intervals (the "late" counter).
    public var isLate: Bool
    /// The gap exceeded 2 target intervals.
    public var isLong: Bool

    public init(gap: Double, missed: Int, isLate: Bool, isLong: Bool) {
        self.gap = gap
        self.missed = missed
        self.isLate = isLate
        self.isLong = isLong
    }

    /// True when a person reading the report would want this frame listed.
    public var isNotable: Bool { missed > 0 || isLate || isLong }
}

/// One presentation that dropped frames, was late, or followed a gap of more than twice the frame period.
public struct FrameEvent: Sendable, Equatable {
    /// Presentation time on the media clock (`CACurrentMediaTime` base), seconds.
    public var time: Double
    public var intervalMs: Double
    public var missed: Int
    public var isLate: Bool
    public var isLong: Bool
    /// OUT-002d: the target frame period in ms when the event was recorded (0: unknown).
    public var targetMs: Double
    /// OUT-002d: the render thread's last ticks when the event was recorded, oldest first; at most the ring's capacity (8).
    public var ticks: [TickSample]

    public init(time: Double, intervalMs: Double, missed: Int, isLate: Bool, isLong: Bool, targetMs: Double = 0, ticks: [TickSample] = []) {
        self.time = time
        self.intervalMs = intervalMs
        self.missed = missed
        self.isLate = isLate
        self.isLong = isLong
        self.targetMs = targetMs
        self.ticks = ticks
    }
}

/// A bounded list of `FrameEvent`. The storage is reserved once, so `record` on the render thread is a compare and a few assignments:
/// no allocation, no logging, no lock of its own (the owner's lock guards it). Events past the cap are only counted.
public struct FrameEventLog: Sendable, Equatable {
    public static let defaultCapacity = 2_000

    public let capacity: Int
    public private(set) var events: [FrameEvent]
    /// Notable presentations after the cap was reached (not listed, not classified).
    public private(set) var beyondCap = 0
    /// OUT-002d: how long the render thread's ticks worked over the run (fixed buckets).
    public private(set) var workHistogram = TickWorkHistogram()

    public init(capacity: Int = FrameEventLog.defaultCapacity) {
        self.capacity = max(0, capacity)
        events = []
        events.reserveCapacity(self.capacity)
    }

    public mutating func record(at time: Double, _ outcome: PresentationOutcome) {
        record(at: time, outcome, targetInterval: 0, ticks: [])
    }

    /// OUT-002d: as `record(at:_:)`, and the event carries the ticks around it. `ticks` is evaluated only for a notable frame that fits under the cap.
    public mutating func record(at time: Double, _ outcome: PresentationOutcome, targetInterval: Double, ticks: @autoclosure () -> [TickSample]) {
        guard outcome.isNotable else { return }
        if events.count < capacity {
            events.append(FrameEvent(time: time, intervalMs: outcome.gap * 1000, missed: outcome.missed,
                                     isLate: outcome.isLate, isLong: outcome.isLong, targetMs: targetInterval * 1000, ticks: ticks()))
        } else {
            beyondCap += 1
        }
    }

    /// OUT-002d: a tick that made a frame, with its own work in seconds. A compare chain and two increments.
    public mutating func noteTick(work: Double, period: Double) { workHistogram.record(work: work, period: period) }

    /// OUT-002d: a tick that made no frame because the GPU was behind.
    public mutating func noteSkippedTick() { workHistogram.recordSkipped() }
}

/// When the output window was covered, from visibility samples. A span opens at the last sample that saw the window visible (the
/// cover happened somewhere after it) and closes at the first sample that sees it visible again. Resolution is the sampling period.
public struct VisibilityTimeline: Sendable, Equatable {
    public struct Span: Sendable, Equatable {
        public var start: Double
        /// Nil while the window is still covered.
        public var end: Double?
    }

    /// Seconds after becoming visible again during which a frame is still counted as covered (the first presentation after a cover
    /// reports the whole covered gap).
    public static let grace = 1.0
    public static let defaultSpanCapacity = 500

    public let spanCapacity: Int
    public private(set) var spans: [Span] = []
    /// Covered periods after the cap was reached (not listed; the last listed span is not extended).
    public private(set) var spansBeyondCap = 0
    private var lastVisibleSample: Double?
    private var openIndex: Int?
    private var overflowOpen = false

    public init(spanCapacity: Int = VisibilityTimeline.defaultSpanCapacity) {
        self.spanCapacity = max(0, spanCapacity)
        spans.reserveCapacity(self.spanCapacity)
    }

    /// Records one visibility sample taken at `time` (seconds on the media clock).
    public mutating func note(sampleAt time: Double, covered: Bool) {
        if covered {
            guard openIndex == nil, !overflowOpen else { return }
            if spans.count < spanCapacity {
                spans.append(Span(start: lastVisibleSample ?? time, end: nil))
                openIndex = spans.count - 1
            } else {
                spansBeyondCap += 1
                overflowOpen = true
            }
        } else {
            lastVisibleSample = time
            overflowOpen = false
            if let i = openIndex {
                spans[i].end = time
                openIndex = nil
            }
        }
    }

    /// Closes a span still open when the run ends.
    public mutating func finish(at time: Double) {
        if let i = openIndex { spans[i].end = time; openIndex = nil }
    }

    /// True when `time` falls in a covered span or within `grace` seconds after one ended.
    public func isCovered(at time: Double) -> Bool {
        for s in spans {
            if time < s.start { continue }
            guard let end = s.end else { return true }
            if time <= end + VisibilityTimeline.grace { return true }
        }
        return false
    }
}

/// The soak report's per-event section (OUT-002b). Pure: every time is passed in.
public enum SoakDropReport {
    public struct Totals: Sendable, Equatable {
        public var dropped = 0
        public var late = 0
        public var longIntervals = 0
        public var longestIntervalMs = 0.0
    }

    public struct Split: Sendable, Equatable {
        public var visible = Totals()
        public var covered = Totals()
    }

    public static func split(events: [FrameEvent], timeline: VisibilityTimeline) -> Split {
        var result = Split()
        for e in events {
            let isCovered = timeline.isCovered(at: e.time)
            var t = isCovered ? result.covered : result.visible
            t.dropped += e.missed
            if e.isLate { t.late += 1 }
            if e.isLong { t.longIntervals += 1 }
            t.longestIntervalMs = max(t.longestIntervalMs, e.intervalMs)
            if isCovered { result.covered = t } else { result.visible = t }
        }
        return result
    }

    /// `origin` is the media-clock time of the soak's start; `maxListed` bounds the event lines in the text (the log's own cap bounds memory).
    /// `advances` and `loops` are media-clock moments of slide advances and video loop points (OUT-002d); nil means "not measured" (no video, for loops).
    public static func lines(log: FrameEventLog, timeline: VisibilityTimeline, origin: Double, maxListed: Int = FrameEventLog.defaultCapacity,
                             advances: [Double]? = nil, loops: [Double]? = nil) -> [String] {
        let split = split(events: log.events, timeline: timeline)
        func f(_ x: Double, _ d: Int = 3) -> String { String(format: "%.\(d)f", x) }
        var out: [String] = []
        out.append("events recorded: \(log.events.count) (cap \(log.capacity)), further events not listed or classified: \(log.beyondCap)")
        out.append("visibility basis: \(timeline.spans.count) covered span(s) from 250 ms visibility samples; a span starts at the last sample that saw the window visible, "
                   + "and an event counts as covered up to \(f(VisibilityTimeline.grace, 0)) s after the window is visible again")
        out.append("while visible: dropped \(split.visible.dropped), late \(split.visible.late), intervals over 2x period \(split.visible.longIntervals)")
        out.append("while covered or within \(f(VisibilityTimeline.grace, 0)) s after becoming visible again: dropped \(split.covered.dropped), late \(split.covered.late), intervals over 2x period \(split.covered.longIntervals)")
        if split.visible.longestIntervalMs > 0 {
            out.append("longest interval while visible: \(f(split.visible.longestIntervalMs, 2)) ms")
        } else {
            out.append("longest interval while visible: no interval over 1.5x period was recorded")
        }
        out.append(contentsOf: classificationLines(log: log))
        if timeline.spans.isEmpty {
            out.append("covered spans: none")
        } else {
            out.append("covered spans (start s, length s):")
            for s in timeline.spans {
                let length = s.end.map { f($0 - s.start) } ?? "open"
                out.append("  \(f(s.start - origin)), \(length)")
            }
            if timeline.spansBeyondCap > 0 { out.append("  further covered spans not listed: \(timeline.spansBeyondCap)") }
        }
        if log.events.isEmpty {
            out.append("events: none")
        } else {
            out.append("events (time s, kind, interval ms, window):")
            for e in log.events.prefix(maxListed) {
                var kinds: [String] = []
                if e.missed > 0 { kinds.append("dropped \(e.missed)") }
                if e.isLate { kinds.append("late") }
                if e.isLong { kinds.append("over 2x period") }
                let window = timeline.isCovered(at: e.time) ? "covered" : "visible"
                out.append("  \(f(e.time - origin)), \(kinds.joined(separator: " + ")), \(f(e.intervalMs, 2)), \(window)")
                out.append(eventDetailLine(e, advances: advances, loops: loops))
            }
        }
        let more = log.beyondCap > 0 ? " (at least: \(log.beyondCap) further event(s) were not classified)" : ""
        out.append("drops while visible: \(split.visible.dropped)\(more)")
        return out
    }

    // MARK: OUT-002d

    public static let ruleLines: [String] = [
        "classification rule (OUT-002d): each event is judged from the ticks that started from 3 frame periods before the previous presentation up to the event, checked in this order:",
        "  app slow: a tick's own work (getting the drawable + building the scene + encoding and committing) exceeded the frame period; the largest part is named",
        "  app late: no tick was slow, but a tick started more than 1.5 periods after the previous tick started, or ran more than 1.5 periods after the display link's own timestamp (the callback arrived late or the render thread was busy)",
        "  unknown: a tick in that window was skipped (two frames were still on the GPU), or no tick was recorded near the event, or the event is past the log cap",
        "  presented late: every tick near the event started on time with work within the period, yet a refresh was skipped (the system or the display presented late)",
        "event detail lines: class and reason | nearest slide advance and video loop point in s (positive: the event is after it; loop points are item changes of the looping player, n/a without video) | ticks, oldest first: start ms relative to the event, cb = ms after the link's own timestamp, m = ms between the tick's end and the link's target time, d/b/e = drawable/build/encode ms, flags H gate holding, C scene changed, V new video frame, S skipped",
    ]

    static func classificationLines(log: FrameEventLog) -> [String] {
        var counts: [LatenessClass: Int] = [:]
        for e in log.events { counts[FrameLateness.classify(e).kind, default: 0] += 1 }
        func n(_ k: LatenessClass) -> Int { counts[k] ?? 0 }
        var out = ruleLines
        out.append("classes: app slow \(n(.appSlow)), app late \(n(.appLate)), presented late \(n(.presentedLate)), unknown \(n(.unknown))"
                   + (log.beyondCap > 0 ? " (\(log.beyondCap) further event(s) past the cap not classified)" : ""))
        let h = log.workHistogram
        if h.ticks + h.skipped == 0 {
            out.append("tick work over the run: no ticks recorded")
        } else {
            out.append(String(format: "tick work over the run: %d ticks that produced a frame, maximum %.2f ms, over the frame period: %d", h.ticks, h.maxWorkMs, h.overPeriod))
            out.append("tick work buckets (drawable + build + encode): " + h.counts.indices.map { "\(TickWorkHistogram.bucketLabel($0)): \(h.counts[$0])" }.joined(separator: ", "))
            out.append("ticks skipped because the GPU was behind: \(h.skipped)")
        }
        return out
    }

    /// The one line per event for a person: class and reason, the nearest slide advance and video loop point (positive: the event is after it), and the ticks.
    static func eventDetailLine(_ e: FrameEvent, advances: [Double]?, loops: [Double]?) -> String {
        func since(_ name: String, _ marks: [Double]?) -> String {
            guard let marks, let d = EventMarks.nearest(to: e.time, in: marks) else { return "\(name) n/a" }
            return "\(name) \(String(format: "%+.3f", d)) s"
        }
        let c = FrameLateness.classify(e)
        let ticks = e.ticks.isEmpty ? "no ticks" : "ticks: " + FrameLateness.tickText(e.ticks, eventTime: e.time)
        return "    \(c.kind.label) (\(c.detail)) | \(since("advance", advances)), \(since("loop", loops)) | \(ticks)"
    }
}
