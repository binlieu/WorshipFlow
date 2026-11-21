// MEDIA-02 / MEDIA-03: which media sits behind the slide and which plays over it. Foundation only.
import Foundation

/// A media-bin item chosen for a layer. `duration` is nil for stills and for items whose length is not known yet.
public struct MediaSelection: Sendable, Equatable, Codable, Hashable {
    public var assetID: UUID
    public var kind: MediaKind
    public var duration: Double?

    public init(assetID: UUID, kind: MediaKind, duration: Double?) {
        self.assetID = assetID
        self.kind = kind
        self.duration = duration
    }

    public init(asset: MediaAsset) {
        self.init(assetID: asset.id, kind: asset.kind, duration: asset.duration)
    }

    /// Only pictures and video are drawn. Audio never becomes a visual layer.
    public var isVisual: Bool { kind == .image || kind == .video }

    var sceneMedia: SceneMedia? {
        switch kind {
        case .video: return .video(assetID)
        case .image: return .image(assetID)
        case .audio: return nil
        }
    }
}

public struct MediaLayer: Sendable, Equatable, Codable, Hashable {
    public var selection: MediaSelection
    public var transport: MediaTransport

    public init(selection: MediaSelection, transport: MediaTransport) {
        self.selection = selection
        self.transport = transport
    }
}

/// The two media layers. The background loops and runs underneath the slide. The foreground plays once over it
/// (hiding the slide text) and removes itself when it ends, which brings the previous state back.
public struct MediaLayers: Sendable, Equatable, Codable, Hashable {
    public private(set) var background: MediaLayer?
    public private(set) var foreground: MediaLayer?

    public init() {}

    /// The same layers without the clip over the slide: what a slide thumbnail draws (UI-002).
    public var withoutForeground: MediaLayers { var copy = self; copy.foreground = nil; return copy }

    /// Replaces the background and starts it looping. Nil clears it. Audio is ignored.
    /// `loops: false` is for a folder playing one clip after another (MEDIA-010): the clip ends and the next one follows.
    public mutating func setBackground(_ selection: MediaSelection?, at now: Double, loops: Bool = true) {
        guard let selection else { background = nil; return }
        guard selection.isVisual else { return }
        var transport = MediaTransport(duration: selection.duration ?? 0, loops: loops)
        transport.play(at: now)
        background = MediaLayer(selection: selection, transport: transport)
    }

    /// Replaces the foreground and plays it once from the start. Audio is ignored.
    public mutating func startForeground(_ selection: MediaSelection, at now: Double) {
        guard selection.isVisual else { return }
        var transport = MediaTransport(duration: selection.duration ?? 0, loops: false)
        transport.play(at: now)
        foreground = MediaLayer(selection: selection, transport: transport)
    }

    public mutating func pauseForeground(at now: Double) { foreground?.transport.pause(at: now) }
    public mutating func resumeForeground(at now: Double) { foreground?.transport.play(at: now) }
    public mutating func seekForeground(to seconds: Double, at now: Double) { foreground?.transport.seek(to: seconds, at: now) }
    public mutating func stopForeground() { foreground = nil }

    // UI-003: the background loop answers to the same controls as the clip (the media controller row drives either).
    public mutating func pauseBackground(at now: Double) { background?.transport.pause(at: now) }
    public mutating func resumeBackground(at now: Double) { background?.transport.play(at: now) }
    public mutating func seekBackground(to seconds: Double, at now: Double) { background?.transport.seek(to: seconds, at: now) }

    /// Removes a foreground that has ended. Returns true when something changed.
    @discardableResult
    public mutating func tick(at now: Double) -> Bool {
        guard let f = foreground, f.transport.status(at: now) == .ended else { return false }
        foreground = nil
        return true
    }
}
