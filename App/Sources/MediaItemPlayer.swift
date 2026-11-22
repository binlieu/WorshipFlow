// UI-005b item 4 / FIX-H items 1 and 6: plays what the playlist's media-file items and announcements loops ask for. The decisions (what
// starts, what failed, when a loop moves on or ends) are the runner's, in OperatorCore, where they are tested with a fake clock and fake
// players; this only hands it the bin's own models as its players. The app's half-second timer calls `tick()`.
import Foundation
import OperatorCore

@MainActor
final class MediaItemPlayer {
    let runner: MediaItemRunner

    init(media: MediaModel, audio: AudioModel?, preview: @escaping (UUID?) -> Void) {
        runner = MediaItemRunner(foreground: media, audio: audio, preview: preview)
    }

    func handle(_ command: MediaItemCommand) -> MediaItemOutcome { runner.handle(command) }
    func tick() { runner.tick() }
}
