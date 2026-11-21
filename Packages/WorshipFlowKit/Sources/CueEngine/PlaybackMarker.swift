// CUE-001 (AUTO-08): markers inside a clip. Foundation only.
//
// The tracker is fed what the player reports and answers with the markers to run. It has no timer and knows nothing
// about AVFoundation. The app calls `start` when a clip starts, `advance` on every position report while it plays,
// `pause` when it stops, and `seek` when the operator jumps.
import Foundation

public struct PlaybackMarker: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// Seconds from the start of the clip.
    public var time: Double
    public var actions: [CueAction]

    public init(id: UUID = UUID(), time: Double, actions: [CueAction]) {
        self.id = id
        self.time = time
        self.actions = actions
    }
}

public struct MarkerTracker: Sendable {
    /// 60000/1001, the first production format.
    public static let defaultFrameRate = 60_000.0 / 1_001.0

    public let duration: Double?
    public let loops: Bool
    public let frameRate: Double

    /// Where the player last said it was; nil before the first report.
    public private(set) var position: Double?

    private var markers: [PlaybackMarker]          // valid markers, by time then written order
    private var armed: [Bool]

    /// A marker is reached half a frame early: it belongs to the video frame nearest its time.
    private var tolerance: Double { 0.5 / frameRate }
    private var framePeriod: Double { 1 / frameRate }

    public init(markers: [PlaybackMarker], duration: Double? = nil, loops: Bool = false, frameRate: Double = MarkerTracker.defaultFrameRate) {
        self.duration = duration
        self.loops = loops
        self.frameRate = frameRate > 0 ? frameRate : Self.defaultFrameRate
        self.markers = Self.sorted(markers)
        self.armed = Array(repeating: false, count: self.markers.count)
    }

    private static func sorted(_ markers: [PlaybackMarker]) -> [PlaybackMarker] {
        markers.enumerated()
            .filter { $0.element.time.isFinite && $0.element.time >= 0 }
            .sorted { $0.element.time != $1.element.time ? $0.element.time < $1.element.time : $0.offset < $1.offset }
            .map(\.element)
    }

    private func withinClip(_ m: PlaybackMarker) -> Bool {
        guard let d = duration else { return true }
        return m.time <= d + tolerance
    }

    /// A new play from `position` (default the beginning). Markers at or after it are armed.
    public mutating func start(at position: Double = 0) {
        guard position.isFinite, position >= 0 else { return }
        self.position = position
        armed = markers.map { $0.time >= position - tolerance && withinClip($0) }
    }

    /// The operator jumped. Nothing fires; markers after the new position are armed, the rest are not. Landing on a
    /// marker counts as being past it.
    public mutating func seek(to position: Double) {
        guard position.isFinite, position >= 0 else { return }
        self.position = position
        armed = markers.map { $0.time > position + tolerance && withinClip($0) }
    }

    /// A position report during normal playback. Returns the markers whose time was reached since the last report.
    /// - Forward steps of any size count as playing, so call `seek` for jumps.
    /// - A step back of less than a frame is clock jitter and is ignored.
    /// - A bigger step back is a loop wrap when the clip loops, has a known duration and the position dropped by at least
    ///   half of it: the markers left in the pass fire, every marker is re-armed, then the new pass starts. Otherwise it
    ///   is treated as a seek back.
    /// - The first report without a `start` or `seek` is treated as a seek.
    public mutating func advance(to p: Double) -> [PlaybackMarker] {
        guard p.isFinite, p >= 0 else { return [] }
        guard let last = position else {
            seek(to: p)
            return []
        }
        if p >= last {
            position = p
            return fire(upTo: p)
        }
        if last - p < framePeriod { return [] }
        if loops, let d = duration, d > 0, last - p >= d / 2 {
            var out = fire(upTo: d)
            armed = markers.map { withinClip($0) }
            position = p
            out.append(contentsOf: fire(upTo: p))
            return out
        }
        seek(to: p)
        return []
    }

    /// Playback stopped at `p`. A marker exactly there fires (once) like in `advance`.
    public mutating func pause(at p: Double) -> [PlaybackMarker] { advance(to: p) }

    /// Swaps the marker list while playing. Markers whose id and time are unchanged keep their state; new or moved
    /// ones are armed when they lie after the playhead.
    public mutating func replaceMarkers(_ new: [PlaybackMarker]) {
        let old = Dictionary(zip(markers, armed).map { ($0.0.id, ($0.0.time, $0.1)) }, uniquingKeysWith: { a, _ in a })
        let sortedNew = Self.sorted(new)
        armed = sortedNew.map { m in
            if let (time, flag) = old[m.id], time == m.time { return flag }
            guard let pos = position else { return false }
            return m.time > pos + tolerance && withinClip(m)
        }
        markers = sortedNew
    }

    private mutating func fire(upTo p: Double) -> [PlaybackMarker] {
        var out: [PlaybackMarker] = []
        for i in markers.indices where armed[i] && markers[i].time <= p + tolerance {
            armed[i] = false
            out.append(markers[i])
        }
        return out
    }
}
