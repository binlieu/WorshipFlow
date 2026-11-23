// OUT-002d (KI-007): why was a frame late? Reporting only. The render thread keeps a small fixed ring of what each display-link tick did and
// when; a dropped or late frame copies the ring around it into its event, and the soak report classifies the event from those numbers.
// Everything here is pure: times are passed in, nothing reads a clock.
import Foundation

/// What one display-link tick did. All times are seconds on the media clock (`CACurrentMediaTime`); the three phases are durations.
public struct TickSample: Sendable, Equatable {
    public static let gateHolding: UInt8 = 1
    public static let sceneChanged: UInt8 = 2
    public static let newVideoFrame: UInt8 = 4
    public static let skipped: UInt8 = 8

    /// When the tick began (the first thing the display-link callback did).
    public var start: Double
    /// The display link's own timestamp for this callback, 0 when the link gave none.
    public var linkTimestamp: Double
    /// The time the link says this frame should reach the screen, 0 when the link gave none.
    public var linkTarget: Double
    /// Getting the drawable (and a command buffer): the existing `nextDrawable()` call, where it can wait.
    public var drawable: Double
    /// Building the scene: the scene provider, the preparation gate, the media frame fetch and the video texture fetch.
    public var build: Double
    /// Encoding the frame and committing it to the GPU.
    public var encode: Double
    public var flags: UInt8

    public init(start: Double, linkTimestamp: Double = 0, linkTarget: Double = 0, drawable: Double = 0, build: Double = 0, encode: Double = 0, flags: UInt8 = 0) {
        self.start = start
        self.linkTimestamp = linkTimestamp
        self.linkTarget = linkTarget
        self.drawable = drawable
        self.build = build
        self.encode = encode
        self.flags = flags
    }

    /// The tick's own work: the three phases together.
    public var work: Double { drawable + build + encode }
    /// OUT-002e: the display link's target time minus the moment the tick ended, in seconds (negative: it ended after the target). Nil when the link gave no target.
    public var margin: Double? { linkTarget > 0 ? linkTarget - (start + work) : nil }
    /// The preparation gate was keeping the previous scene on screen while the next was prepared.
    public var gateHolding: Bool { flags & TickSample.gateHolding != 0 }
    /// The scene drawn on this tick differs from the one drawn before it.
    public var sceneChanged: Bool { flags & TickSample.sceneChanged != 0 }
    /// A video frame the previous tick did not draw was available.
    public var newVideoFrame: Bool { flags & TickSample.newVideoFrame != 0 }
    /// No frame was made: two frames were still on the GPU.
    public var skipped: Bool { flags & TickSample.skipped != 0 }

    static let empty = TickSample(start: 0)
}

/// The last few ticks, in storage reserved once. `push` is a handful of stores: no allocation, no lock of its own (the owner's lock guards it).
public struct TickRing: Sendable, Equatable {
    public static let defaultCapacity = 8

    public let capacity: Int
    private var samples: [TickSample]
    private var next = 0
    public private(set) var count = 0

    public init(capacity: Int = TickRing.defaultCapacity) {
        self.capacity = max(1, capacity)
        samples = Array(repeating: TickSample.empty, count: self.capacity)
    }

    public mutating func push(_ sample: TickSample) {
        samples[next] = sample
        next += 1
        if next == capacity { next = 0 }
        if count < capacity { count += 1 }
    }

    /// The recorded ticks, oldest first. Allocates; only called for a notable frame.
    public func snapshot() -> [TickSample] {
        guard count > 0 else { return [] }
        let first = count < capacity ? 0 : next
        return (0..<count).map { samples[(first + $0) % capacity] }
    }
}

/// How long ticks worked, in fixed buckets: no per-frame storage.
public struct TickWorkHistogram: Sendable, Equatable {
    /// Upper edges in milliseconds; one more bucket holds everything at or above the last edge.
    public static let edgesMs: [Double] = [0.5, 1, 2, 4, 8, 12, 16, 20, 33, 66]

    public private(set) var counts = [Int](repeating: 0, count: TickWorkHistogram.edgesMs.count + 1)
    /// Ticks that made a frame.
    public private(set) var ticks = 0
    /// Ticks that made none because the GPU still held two frames.
    public private(set) var skipped = 0
    /// Ticks whose work exceeded the frame period.
    public private(set) var overPeriod = 0
    public private(set) var maxWorkMs = 0.0
    /// OUT-002e: ticks that had a link target, how many ended after it, and the sum and minimum of target minus tick end, in ms.
    public private(set) var marginTicks = 0
    public private(set) var marginLateTicks = 0
    public private(set) var marginSumMs = 0.0
    public private(set) var marginMinMs = 0.0
    public var marginMeanMs: Double { marginTicks > 0 ? marginSumMs / Double(marginTicks) : 0 }
    /// Ticks whose work was 12 ms or more (the buckets from 12 ms up).
    public var ticksAtTwelveMsOrMore: Int { counts.indices.filter { $0 > 5 }.reduce(0) { $0 + counts[$1] } }

    public init() {}

    public mutating func record(work seconds: Double, period: Double, margin: Double? = nil) {
        if let margin {
            let m = margin * 1000
            if marginTicks == 0 || m < marginMinMs { marginMinMs = m }
            marginTicks += 1
            marginSumMs += m
            if m < 0 { marginLateTicks += 1 }
        }
        let ms = seconds * 1000
        ticks += 1
        var i = 0
        let edges = TickWorkHistogram.edgesMs
        while i < edges.count, ms >= edges[i] { i += 1 }
        counts[i] += 1
        if ms > maxWorkMs { maxWorkMs = ms }
        if period > 0, seconds > period { overPeriod += 1 }
    }

    public mutating func recordSkipped() { skipped += 1 }

    /// "< 0.5 ms", "0.5 to 1 ms", ... ">= 66 ms".
    public static func bucketLabel(_ i: Int) -> String {
        func f(_ x: Double) -> String { x == x.rounded() ? String(format: "%.0f", x) : String(format: "%g", x) }
        if i == 0 { return "< \(f(edgesMs[0])) ms" }
        if i >= edgesMs.count { return ">= \(f(edgesMs[edgesMs.count - 1])) ms" }
        return "\(f(edgesMs[i - 1])) to \(f(edgesMs[i])) ms"
    }
}

/// OUT-002e: how long a frame took from the start of the tick that made it to the presented time the system reports. Fixed size.
public struct PresentLatencyStats: Sendable, Equatable {
    public private(set) var count = 0
    public private(set) var sumMs = 0.0
    public private(set) var minMs = 0.0
    public private(set) var maxMs = 0.0
    public var meanMs: Double { count > 0 ? sumMs / Double(count) : 0 }
    public init() {}
    public mutating func record(_ seconds: Double) {
        guard seconds > 0 else { return }
        let ms = seconds * 1000
        if count == 0 || ms < minMs { minMs = ms }
        if ms > maxMs { maxMs = ms }
        count += 1
        sumMs += ms
    }
}

/// A bounded, ascending list of moments on the media clock (slide advances, video loop points).
public struct EventMarks: Sendable, Equatable {
    public let capacity: Int
    public private(set) var times: [Double] = []
    public private(set) var beyondCap = 0

    public init(capacity: Int = 2_000) {
        self.capacity = max(0, capacity)
        times.reserveCapacity(self.capacity)
    }

    public mutating func add(_ time: Double) {
        if times.count < capacity { times.append(time) } else { beyondCap += 1 }
    }

    /// `time` minus the mark nearest to it, in seconds: positive when the event is after the mark. Nil when there are no marks.
    public static func nearest(to time: Double, in marks: [Double]) -> Double? {
        guard !marks.isEmpty else { return nil }
        var lo = 0, hi = marks.count            // first mark not before `time`
        while lo < hi {
            let mid = (lo + hi) / 2
            if marks[mid] < time { lo = mid + 1 } else { hi = mid }
        }
        var best: Double?
        for i in [lo - 1, lo] where marks.indices.contains(i) {
            let d = time - marks[i]
            if best == nil || abs(d) < abs(best!) { best = d }
        }
        return best
    }
}

public enum LatenessClass: String, Sendable, Equatable, CaseIterable {
    case appSlow, appLate, presentedLate, unknown

    public var label: String {
        switch self {
        case .appSlow: "app slow"
        case .appLate: "app late"
        case .presentedLate: "presented late"
        case .unknown: "unknown"
        }
    }
}

public struct LatenessClassification: Sendable, Equatable {
    public var kind: LatenessClass
    public var detail: String
}

/// The rule that says, for one dropped or late frame, whether the app or the system was late. Checked in this order, on the ticks that started
/// from three frame periods before the previous presentation up to the event:
/// 1. app slow: a tick's own work (drawable + build + encode) exceeded the frame period. The largest phase is named.
/// 2. app late: no tick was slow, but a tick started more than 1.5 periods after the previous tick started, or ran more than 1.5 periods after the
///    display link's own timestamp: the callback arrived late or the render thread was busy.
/// 3. unknown: a tick in the window was skipped (two frames were still on the GPU), or no tick was recorded there.
/// 4. presented late: otherwise. Every tick was on time and short, yet a refresh was skipped: the system or the display.
public enum FrameLateness {
    public static let lateStartFactor = 1.5
    public static let windowPeriods = 3.0

    public static func classify(ticks: [TickSample], eventTime: Double, gap: Double, period: Double) -> LatenessClassification {
        func ms(_ s: Double, _ d: Int = 1) -> String { String(format: "%.\(d)f", s * 1000) }
        guard period > 0 else { return LatenessClassification(kind: .unknown, detail: "no frame period to compare with") }
        let lower = eventTime - gap - windowPeriods * period
        let indices = ticks.indices.filter { ticks[$0].start >= lower && ticks[$0].start <= eventTime }
        guard !indices.isEmpty else { return LatenessClassification(kind: .unknown, detail: "no tick records near the event") }

        // 1. app slow
        if let i = indices.filter({ !ticks[$0].skipped && ticks[$0].work > period }).max(by: { ticks[$0].work < ticks[$1].work }) {
            let t = ticks[i]
            let parts: [(String, Double)] = [("getting the drawable", t.drawable), ("building the scene", t.build), ("encoding and committing", t.encode)]
            let worst = parts.max(by: { $0.1 < $1.1 })!
            return LatenessClassification(kind: .appSlow, detail: "\(worst.0) took \(ms(worst.1)) ms of \(ms(t.work)) ms work in the tick at \(ms(t.start - eventTime)) ms, frame period \(ms(period, 2)) ms")
        }
        // 2. app late
        var worstStart: (late: Double, at: Double)?
        var worstLink: (late: Double, at: Double)?
        for i in indices {
            let t = ticks[i]
            if i > 0 {
                let interval = t.start - ticks[i - 1].start
                if interval > lateStartFactor * period, interval > (worstStart?.late ?? 0) { worstStart = (interval, t.start) }
            }
            if t.linkTimestamp > 0 {
                let delay = t.start - t.linkTimestamp
                if delay > lateStartFactor * period, delay > (worstLink?.late ?? 0) { worstLink = (delay, t.start) }
            }
        }
        if let w = worstStart {
            return LatenessClassification(kind: .appLate, detail: "a tick started \(ms(w.late)) ms after the previous tick (frame period \(ms(period, 2)) ms): the callback arrived late or the render thread was busy")
        }
        if let w = worstLink {
            return LatenessClassification(kind: .appLate, detail: "a tick ran \(ms(w.late)) ms after the display link's own timestamp (frame period \(ms(period, 2)) ms): the callback arrived late")
        }
        // 3. unknown
        if indices.contains(where: { ticks[$0].skipped }) {
            return LatenessClassification(kind: .unknown, detail: "a tick was skipped because two frames were still on the GPU")
        }
        // 4. presented late
        let longest = indices.map { ticks[$0].work }.max() ?? 0
        return LatenessClassification(kind: .presentedLate, detail: "all \(indices.count) tick(s) near the drop started on time with work within the frame period (longest \(ms(longest, 2)) ms), yet a refresh was skipped: the system or the display")
    }

    public static func classify(_ event: FrameEvent) -> LatenessClassification {
        guard !event.ticks.isEmpty else { return LatenessClassification(kind: .unknown, detail: "no tick records for this event") }
        return classify(ticks: event.ticks, eventTime: event.time, gap: event.intervalMs / 1000, period: event.targetMs / 1000)
    }

    /// One line for a person: `rel` is each tick's start relative to the event. `cb` is how long after the link's own timestamp the tick ran, `m`
    /// the margin between the tick's end and the link's target presentation time, `d`/`b`/`e` the three phases in ms; flags H gate holding,
    /// C scene changed, V new video frame, S skipped.
    public static func tickText(_ ticks: [TickSample], eventTime: Double) -> String {
        func f(_ x: Double) -> String { String(format: "%.1f", x) }
        return ticks.map { t in
            var s = "\(f((t.start - eventTime) * 1000))"
            if t.linkTimestamp > 0 { s += " cb\(String(format: "%+.1f", (t.start - t.linkTimestamp) * 1000))" }
            if t.linkTarget > 0 { s += " m\(String(format: "%+.1f", (t.linkTarget - (t.start + t.work)) * 1000))" }
            s += " d\(f(t.drawable * 1000)) b\(f(t.build * 1000)) e\(f(t.encode * 1000))"
            var flags = ""
            if t.gateHolding { flags += "H" }
            if t.sceneChanged { flags += "C" }
            if t.newVideoFrame { flags += "V" }
            if t.skipped { flags += "S" }
            if !flags.isEmpty { s += " \(flags)" }
            return s
        }.joined(separator: " | ")
    }
}
