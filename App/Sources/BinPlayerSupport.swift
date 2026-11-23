// MEDIA-010 item 4: the sidebar player's AVFoundation side. A player of its own, on the operator's Mac only: it has no
// connection to the media registry or any output. Its sound follows --silent-audio (the model keeps it muted).
import AVFoundation
import Domain
import OperatorCore

@MainActor
final class AVPreviewPlayer: PreviewPlayback {
    let player = AVPlayer()
    private var loops = false
    /// UI-007d: the part of the clip to play. The player stops at the out mark (and reports the end like a clip's own end); a loop starts again at the in mark.
    private var markIn: Double?
    private var markOut: Double?
    private var endObserver: NSObjectProtocol?
    private(set) var openedKind: MediaKind?

    var position: Double { let t = player.currentTime().seconds; return t.isFinite ? t : 0 }
    var duration: Double { let d = player.currentItem?.duration.seconds ?? 0; return d.isFinite ? d : 0 }
    var isPlaying: Bool { player.rate != 0 }

    func open(path: String, kind: MediaKind) {
        close()
        openedKind = kind
        guard kind != .image else { return }
        let item = AVPlayerItem(url: URL(fileURLWithPath: path))
        player.actionAtItemEnd = .pause
        markIn = nil; markOut = nil
        player.replaceCurrentItem(with: item)
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.loops { self.player.seek(to: CMTime(seconds: self.markIn ?? 0, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); self.player.play() }
            }
        }
    }

    func play() {
        let end = markOut ?? duration
        if end > 0, position >= end - 0.05 { seek(to: markIn ?? 0) }
        player.play()
    }
    func setMarks(in markIn: Double?, out markOut: Double?) {
        self.markIn = markIn
        self.markOut = markOut
        player.currentItem?.forwardPlaybackEndTime = markOut.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .invalid
    }
    func pause() { player.pause() }
    func seek(to seconds: Double) { player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
    func setLoops(_ on: Bool) { loops = on }
    func setMuted(_ on: Bool) { player.isMuted = on }

    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        openedKind = nil
        markIn = nil; markOut = nil
    }
}
