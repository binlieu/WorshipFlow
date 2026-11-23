// MEDIA-010 item 4: the player in the right sidebar for the item chosen in the media bin. A local preview on the operator's
// Mac only: it has no connection to the media layers or the outputs, and its sound follows --silent-audio. Foundation and
// Domain only; the app supplies the AVFoundation player.
import Foundation
import Observation
import Domain

/// The one door to the sidebar's player. The app's adapter plays through AVFoundation; tests use a fake.
@MainActor
public protocol PreviewPlayback: AnyObject {
    var position: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    func open(path: String, kind: MediaKind)
    func play()
    func pause()
    func seek(to seconds: Double)
    func setLoops(_ on: Bool)
    func setMuted(_ on: Bool)
    func close()
    /// UI-007d: the part of the clip to play (nil is the start / the end): the player stops at the out mark, and a loop starts again at the in mark.
    func setMarks(in markIn: Double?, out markOut: Double?)
}

public extension PreviewPlayback {
    func setMarks(in markIn: Double?, out markOut: Double?) {}
}

/// Which controls the player shows for a kind.
public struct PreviewControls: Equatable, Sendable {
    public var showsPicture: Bool
    public var showsTransport: Bool
    public var hasLoop: Bool { showsTransport }
    public var hasMute: Bool { showsTransport }
    public var hasScrubber: Bool { showsTransport }
    public var hasTime: Bool { showsTransport }

    public static func `for`(kind: MediaKind) -> PreviewControls {
        switch kind {
        case .video: PreviewControls(showsPicture: true, showsTransport: true)
        case .audio: PreviewControls(showsPicture: false, showsTransport: true)
        case .image: PreviewControls(showsPicture: true, showsTransport: false)
        }
    }
}

/// What the buttons under the player offer.
public struct PreviewSendActions: Equatable, Sendable {
    public var background: Bool
    public var foreground: Bool
    public var playLive: Bool

    public static func available(for kind: MediaKind, showIsLive: Bool) -> PreviewSendActions {
        switch kind {
        case .video, .image: PreviewSendActions(background: true, foreground: showIsLive, playLive: false)
        case .audio: PreviewSendActions(background: false, foreground: false, playLive: true)
        }
    }
}

@MainActor
@Observable
public final class MediaPreviewModel {
    public private(set) var asset: MediaAsset?
    public private(set) var loops = false
    public private(set) var isMuted = false
    /// With `--silent-audio` the preview never makes a sound and cannot be unmuted.
    public let silent: Bool
    @ObservationIgnored private let player: any PreviewPlayback

    public init(player: any PreviewPlayback, silent: Bool, startsMuted: Bool = false) {
        self.player = player
        self.silent = silent
        self.isMuted = silent || startsMuted
    }

    /// FIX-G: the preview the app uses. It starts muted every session: its sound goes through the Mac's default output, which may be
    /// the house system. The operator's mute choice lasts as long as this object (the session) and is never stored.
    public static func sessionPreview(player: any PreviewPlayback, silent: Bool) -> MediaPreviewModel {
        MediaPreviewModel(player: player, silent: silent, startsMuted: true)
    }

    /// FIX-G: the line under the player: where the sound is heard. `outputName` is the Mac's default output as the app knows it.
    public func heardLine(outputName: String?) -> String {
        let place = outputName.map { "this Mac's default sound output (\($0))" } ?? "this Mac's default sound output"
        if silent { return "Started silent (--silent-audio): this preview makes no sound." }
        if isMuted { return "Muted. If you turn the sound on it plays on \(place), not the show's sound output." }
        return "Playing on \(place), not the show's sound output."
    }

    /// FIX-G: an item was sent to the live screens or the audio output. If it is the one previewed, the preview pauses, so the
    /// same sound is not heard twice.
    public func itemSentLive(_ id: UUID) {
        guard asset?.id == id, player.isPlaying else { return }
        player.pause()
    }

    public var canUnmute: Bool { !silent }
    public var controls: PreviewControls? { asset.map { PreviewControls.for(kind: $0.kind) } }
    public var isPlaying: Bool { player.isPlaying }
    public var duration: Double { player.duration }
    public var position: Double { min(player.position, max(player.duration, player.position)) }
    public var remaining: Double { max(0, duration - position) }

    /// UI-007d: where the preview starts and where Restart and Stop go back to: the in mark, or the beginning.
    public var startPosition: Double { markedStart ?? 0 }
    private var markedStart: Double? { usableMarks(asset)?.in }

    /// The marks of a video that can work: an in mark before the out mark (and before the end of a clip whose length is known). A picture, a
    /// sound (the audio player does not honour marks) or a clip without a usable mark has none.
    private func usableMarks(_ asset: MediaAsset?) -> (in: Double?, out: Double?)? {
        guard let asset, asset.kind == .video else { return nil }
        let transport = MediaTransport(duration: asset.duration ?? 0, loops: false, markIn: asset.markIn, markOut: asset.markOut)
        guard transport.markIn != nil || transport.markOut != nil else { return nil }
        return (transport.markIn, transport.markOut)
    }

    /// Shows an item (nil shows none). The earlier one is closed; the same item again changes nothing, except that its marks are passed on to
    /// the player when they changed (setting a mark never reopens the file).
    public func select(_ next: MediaAsset?) {
        if let next, next.id == asset?.id {
            let changed = asset?.markIn != next.markIn || asset?.markOut != next.markOut
            asset = next
            if changed { applyMarks(next) }
            return
        }
        guard next?.id != asset?.id else { return }
        if asset != nil { player.close() }
        asset = next
        loops = false
        guard let next else { return }
        player.open(path: next.path, kind: next.kind)
        isMuted = silent ? true : isMuted
        player.setMuted(isMuted)
        player.setLoops(false)
        applyMarks(next)
    }

    private func applyMarks(_ item: MediaAsset) {
        let marks = usableMarks(item)
        player.setMarks(in: marks?.in, out: marks?.out)
    }

    /// Plays or pauses. A clip with marks that is before its in mark, or at or past its out mark, starts at the in mark.
    public func togglePlay() {
        guard let asset, PreviewControls.for(kind: asset.kind).showsTransport else { return }
        if player.isPlaying { player.pause(); return }
        if let marks = usableMarks(asset) {
            let start = marks.in ?? 0
            let position = player.position
            if position < start - 0.05 || (marks.out.map { position >= $0 - 0.05 } ?? false) { player.seek(to: start) }
        }
        player.play()
    }

    public func seek(to seconds: Double) {
        guard let asset, PreviewControls.for(kind: asset.kind).showsTransport else { return }
        let top = player.duration > 0 ? player.duration : seconds
        player.seek(to: min(max(0, seconds.isFinite ? seconds : 0), top))
    }

    public func setLoops(_ on: Bool) {
        guard asset != nil else { return }
        loops = on
        player.setLoops(on)
    }

    public func setMuted(_ muted: Bool) {
        let value = silent ? true : muted
        isMuted = value
        player.setMuted(value)
    }
}
