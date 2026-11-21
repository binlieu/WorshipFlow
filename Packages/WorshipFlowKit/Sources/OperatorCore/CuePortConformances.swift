// CUE-002b (item 1): the other models, behind the cue ports.
import Foundation
import Domain

extension SettingsModel: CueLookPort {
    public func hasLook(_ id: UUID) -> Bool { looks.contains { $0.id == id } }
    public func hasProp(_ id: UUID) -> Bool { props.contains { $0.id == id } }
}

extension StageModel: CueStagePort {
    public func hasTimer(_ id: UUID) -> Bool { timers.contains { $0.id == id } }
}

/// Pictures, videos and sounds: the media bin and the audio cue player.
@MainActor
public final class MediaCueAdapter: CueMediaPort {
    private let media: MediaModel
    private let audio: AudioModel?

    public init(media: MediaModel, audio: AudioModel?) {
        self.media = media
        self.audio = audio
    }

    public func hasAsset(_ id: UUID) -> Bool { media.asset(id).map { $0.kind != .audio } ?? false }
    public func hasSound(_ id: UUID) -> Bool { media.asset(id)?.kind == .audio && audio != nil }
    public func setBackground(_ id: UUID?) { if let id { media.setBackground(id) } else { media.clearBackground() } }
    public func playForeground(_ id: UUID) { media.playForeground(id) }
    public func stopForeground() { media.stopForeground() }
    public func playSound(_ id: UUID) { audio?.play(id) }
    public func stopSound(_ id: UUID) { audio?.stop(id) }
    public func clearMusic() { audio?.stopAll() }
}
