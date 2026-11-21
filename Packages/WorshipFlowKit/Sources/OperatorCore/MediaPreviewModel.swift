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

    public init(player: any PreviewPlayback, silent: Bool) {
        self.player = player
        self.silent = silent
    }

    public var canUnmute: Bool { !silent }
    public var controls: PreviewControls? { asset.map { PreviewControls.for(kind: $0.kind) } }
    public var isPlaying: Bool { player.isPlaying }
    public var duration: Double { player.duration }
    public var position: Double { min(player.position, max(player.duration, player.position)) }
    public var remaining: Double { max(0, duration - position) }

    /// Shows an item (nil shows none). The earlier one is closed; the same item again changes nothing.
    public func select(_ next: MediaAsset?) {
        guard next?.id != asset?.id else { return }
        if asset != nil { player.close() }
        asset = next
        loops = false
        guard let next else { return }
        player.open(path: next.path, kind: next.kind)
        isMuted = silent ? true : isMuted
        player.setMuted(isMuted)
        player.setLoops(false)
    }

    public func togglePlay() {
        guard let asset, PreviewControls.for(kind: asset.kind).showsTransport else { return }
        if player.isPlaying { player.pause() } else { player.play() }
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
