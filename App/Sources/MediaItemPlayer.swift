// UI-005b item 4: plays what the playlist's media-file items and announcements loops ask for. The workspace model says what the
// operator chose (`MediaItemCommand`); this plays it through the media bin's own models, so a playlist item sounds and looks like the
// same file chosen in the bin. A picture loop moves to its next picture by a one-second check of a monotonic clock, and only while
// the loop is live: it stops with Next, Previous, a slide going live, Clear all, Stop, or the operator clearing the foreground.
import Foundation
import Domain
import OperatorCore

@MainActor
final class MediaItemPlayer {
    private let media: MediaModel
    private let audio: AudioModel?
    private let preview: (UUID?) -> Void
    private var loop: AnnouncementsSpec?
    private var loopStartedAt: TimeInterval = 0
    private var shownIndex = -1
    private var ticker: Timer?

    init(media: MediaModel, audio: AudioModel?, preview: @escaping (UUID?) -> Void) {
        self.media = media
        self.audio = audio
        self.preview = preview
    }

    func handle(_ command: MediaItemCommand) {
        switch command {
        case .preview(let spec):
            guard media.asset(spec.assetID) != nil else { media.report(Self.missing(spec.name)); return }
            preview(spec.assetID)
        case .play(let spec):
            guard media.asset(spec.assetID) != nil else { media.report(Self.missing(spec.name)); return }
            if spec.kind == .audio { audio?.play(spec.assetID) } else { media.playForeground(spec.assetID) }
        case .stop(let spec):
            if spec.kind == .audio { audio?.stop(spec.assetID) }
            else if media.layers.foreground?.selection.assetID == spec.assetID { media.stopForeground() }
        case .startLoop(let spec): start(spec)
        case .stopLoop: stopLoop()
        }
    }

    private static func missing(_ name: String) -> String {
        "\"\(name)\" is not in the media bin any more. Add the file to the bin again, then put it back in the playlist."
    }

    private func start(_ spec: AnnouncementsSpec) {
        stopLoop()
        guard let first = spec.items.first(where: { media.asset($0.assetID) != nil }) else {
            media.report("None of the pictures or the video of \"\(spec.label)\" are in the media bin any more."); return
        }
        loop = spec
        loopStartedAt = ProcessInfo.processInfo.systemUptime
        shownIndex = spec.items.firstIndex(of: first) ?? 0
        media.playForeground(first.assetID)
        if spec.isVideoLoop { media.setForegroundLoops(true); return }
        guard spec.items.count > 1 else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
    }

    private func tick() {
        guard let loop else { stopLoop(); return }
        guard media.layers.foreground != nil else { stopLoop(); return }       // the operator cleared the foreground: the loop ends with it
        let index = loop.pictureIndex(afterSeconds: ProcessInfo.processInfo.systemUptime - loopStartedAt)
        guard index != shownIndex, loop.items.indices.contains(index), media.asset(loop.items[index].assetID) != nil else { return }
        shownIndex = index
        media.playForeground(loop.items[index].assetID)
    }

    func stopLoop() {
        ticker?.invalidate()
        ticker = nil
        guard let spec = loop else { return }
        loop = nil
        let ids = Set(spec.assetIDs)
        if let shown = media.layers.foreground?.selection.assetID, ids.contains(shown) {
            media.setForegroundLoops(false)
            media.stopForeground()
        }
    }
}
