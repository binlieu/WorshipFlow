// UI-007d (MEDIA, CUE-33): what the live player tells the markers. A `PlaybackSample` is one look at a live clip; the `MarkerFeed` turns a
// stream of samples into the markers that were reached, once per crossing, using the CueEngine's `MarkerTracker` for each layer. Pure values:
// no clock, no timer, no player, no AVFoundation. Foundation, Domain and CueEngine only.
import Foundation
import Domain
import CueEngine

/// One look at the clip playing on a media layer, taken by whoever polls (the clock-driven transport, or a test).
public struct PlaybackSample: Sendable, Equatable {
    public var assetID: UUID
    /// Changes every time the clip is started (again): a new pass for the markers.
    public var epoch: Int
    /// Changes every time the operator seeks: a jump, not playing.
    public var seekCount: Int
    /// Seconds into the clip.
    public var position: Double
    /// How many times a looping clip has wrapped since it was started or sought.
    public var loopCount: Int
    public var isPlaying: Bool
    /// The part of the clip that plays: its in mark (0 without one) and its out mark or length (nil when not known).
    public var rangeStart: Double
    public var rangeEnd: Double?

    public init(assetID: UUID, epoch: Int, seekCount: Int, position: Double, loopCount: Int, isPlaying: Bool, rangeStart: Double = 0, rangeEnd: Double? = nil) {
        self.assetID = assetID
        self.epoch = epoch
        self.seekCount = seekCount
        self.position = position
        self.loopCount = loopCount
        self.isPlaying = isPlaying
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }
}

/// Per media layer, follows the clip and answers each sample with the markers reached since the last one.
///
/// - A marker fires once when playing reaches it. A clip started again, or a looping clip that begins a new pass, arms every marker again.
/// - A jump (the operator's seek) never fires anything: markers after the new place are armed, those before are not. A step back of less than
///   a frame is jitter, not a jump and not a crossing.
/// - A marker at the in mark fires when the clip starts; one before the in mark or after the out mark is never reached.
/// - A sample of nil (the clip is not live: the show stopped, the layer was cleared) forgets the layer; nothing fires.
public struct MarkerFeed: Sendable {
    private struct Layer: Sendable {
        var assetID: UUID
        var epoch: Int
        var seekCount: Int
        var loopCount: Int
        var lastPosition: Double
        var markers: [PlaybackMarker]
        var tracker: MarkerTracker
    }

    private var layers: [MediaLayerSlot: Layer] = [:]
    private let frameRate: Double
    private var framePeriod: Double { 1 / (frameRate > 0 ? frameRate : MarkerTracker.defaultFrameRate) }

    public init(frameRate: Double = MarkerTracker.defaultFrameRate) {
        self.frameRate = frameRate
    }

    /// Whether the layer has a clip being followed now.
    public func isTracking(_ slot: MediaLayerSlot) -> Bool { layers[slot] != nil }

    /// Forgets one layer (its clip left the screens).
    public mutating func forget(_ slot: MediaLayerSlot) { layers[slot] = nil }

    /// Forgets every layer (the observer stopped).
    public mutating func reset() { layers.removeAll() }

    /// Gives a followed layer its new list of markers (one was added, moved or deleted while playing): a marker that is new or moved is armed
    /// if it lies after the playhead; the others keep their state.
    public mutating func markersChanged(_ slot: MediaLayerSlot, markers: [PlaybackMarker]) {
        guard var layer = layers[slot] else { return }
        layer.tracker.replaceMarkers(markers)
        layer.markers = markers
        layers[slot] = layer
    }

    /// One sample of a layer. Returns the markers reached, in time order (those of a finished pass first when a loop has just wrapped).
    public mutating func poll(_ slot: MediaLayerSlot, sample: PlaybackSample?, markers: [PlaybackMarker]) -> [PlaybackMarker] {
        guard let s = sample, s.position.isFinite, s.position >= 0 else { layers[slot] = nil; return [] }
        guard var layer = layers[slot], layer.assetID == s.assetID, layer.epoch == s.epoch else {
            // A new clip, or the same one started again: a new pass from where it is now.
            var tracker = MarkerTracker(markers: markers, duration: s.rangeEnd, loops: false, frameRate: frameRate)
            tracker.start(at: s.position)
            let fired = tracker.advance(to: s.position)            // a marker at the very start (the in mark) is reached now
            layers[slot] = Layer(assetID: s.assetID, epoch: s.epoch, seekCount: s.seekCount, loopCount: s.loopCount,
                                 lastPosition: s.position, markers: markers, tracker: tracker)
            return fired
        }
        var fired: [PlaybackMarker] = []
        if layer.markers != markers {
            layer.tracker.replaceMarkers(markers)
            layer.markers = markers
        }
        if s.loopCount != layer.loopCount {
            // A looping clip began another pass: the markers left in the old one are reached (a marker at the out mark belongs to it), then all
            // are armed again from the start of the new one.
            if s.loopCount > layer.loopCount, let end = s.rangeEnd { fired += layer.tracker.advance(to: end) }
            layer.tracker.start(at: s.rangeStart)
            layer.loopCount = s.loopCount
            layer.lastPosition = s.rangeStart
        }
        if s.seekCount != layer.seekCount {
            layer.seekCount = s.seekCount
            if abs(s.position - layer.lastPosition) >= framePeriod {
                layer.tracker.seek(to: s.position)                  // a jump: nothing fires, the markers after it are armed
                layer.lastPosition = s.position
            }
            // else: a seek that went nowhere (back and forth within a frame) is not a new crossing
        } else {
            fired += layer.tracker.advance(to: s.position)
            if s.position >= layer.lastPosition { layer.lastPosition = s.position }
        }
        layers[slot] = layer
        return fired
    }
}
