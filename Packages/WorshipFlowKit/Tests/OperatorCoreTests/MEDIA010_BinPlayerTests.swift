// MEDIA-010 item 4: selecting an item in the bin shows a player for it in the right sidebar: a video with play, pause,
// scrub, time, loop and mute; sound the same without a picture; a picture as a picture. It is a local preview on the
// operator's Mac only: it never reaches an output and its sound follows --silent-audio.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
final class FakePreviewPlayer: PreviewPlayback {
    var log: [String] = []
    var position = 0.0
    var duration = 0.0
    var isPlaying = false
    var loops = false
    var muted: Bool?
    func open(path: String, kind: MediaKind) { log.append("open \(path)"); position = 0; isPlaying = false }
    func play() { log.append("play"); isPlaying = true }
    func pause() { log.append("pause"); isPlaying = false }
    func seek(to seconds: Double) { log.append("seek \(seconds)"); position = seconds }
    func setLoops(_ on: Bool) { loops = on; log.append("loops \(on)") }
    func setMuted(_ on: Bool) { muted = on; log.append("muted \(on)") }
    func close() { log.append("close"); isPlaying = false }
}

@MainActor
@Suite struct MEDIA010_BinPlayerTests {
    private let video = MediaAsset(name: "loop", kind: .video, path: "/m/loop.mov", duration: 20)
    private let sound = MediaAsset(name: "hymn", kind: .audio, path: "/m/hymn.mp3", duration: 30)
    private let picture = MediaAsset(name: "cross", kind: .image, path: "/m/cross.png")

    @Test func eachKindShowsTheControlsItNeeds() {
        let v = PreviewControls.for(kind: .video), a = PreviewControls.for(kind: .audio), p = PreviewControls.for(kind: .image)
        #expect(v.showsPicture && v.showsTransport && v.hasLoop && v.hasMute && v.hasScrubber && v.hasTime)
        #expect(!a.showsPicture && a.showsTransport && a.hasLoop && a.hasMute && a.hasScrubber && a.hasTime)
        #expect(p.showsPicture && !p.showsTransport && !p.hasLoop && !p.hasMute && !p.hasScrubber && !p.hasTime)
    }

    @Test func selectingOpensItAndSelectingAnotherClosesTheFirst() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: false)
        model.select(video)
        #expect(model.asset == video && player.log == ["open /m/loop.mov", "muted false", "loops false"])
        model.select(sound)
        #expect(player.log.suffix(4) == ["close", "open /m/hymn.mp3", "muted false", "loops false"])
        model.select(nil)
        #expect(model.asset == nil && player.log.last == "close")
    }

    @Test func selectingTheSameItemAgainDoesNotRestartIt() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: false)
        model.select(video)
        model.togglePlay()
        let count = player.log.count
        model.select(video)
        #expect(player.log.count == count && player.isPlaying)
    }

    @Test func playPauseScrubAndLoopGoToThePlayer() {
        let player = FakePreviewPlayer()
        player.duration = 20
        let model = MediaPreviewModel(player: player, silent: false)
        model.select(video)
        model.togglePlay()
        #expect(model.isPlaying)
        model.togglePlay()
        #expect(!model.isPlaying)
        model.seek(to: 7)
        #expect(model.position == 7 && model.remaining == 13)
        model.seek(to: 99)
        #expect(model.position == 20, "clamped to the length")
        model.setLoops(true)
        #expect(model.loops && player.loops)
        model.setMuted(true)
        #expect(model.isMuted && player.muted == true)
    }

    @Test func aPictureHasNothingToPlay() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: false)
        model.select(picture)
        model.togglePlay()
        #expect(!model.isPlaying && !player.log.contains("play"))
    }

    @Test func silentAudioKeepsThePreviewMutedWhateverTheOperatorAsks() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: true)
        model.select(video)
        #expect(player.muted == true && model.isMuted && !model.canUnmute)
        model.setMuted(false)
        #expect(model.isMuted && player.muted == true, "--silent-audio holds")
    }

    @Test func thePreviewNeverTouchesTheLiveLayers() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.layerChanges.removeAll(); rig.audioChanges.removeAll()
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel(player: player, silent: false)
        model.select(loop)
        model.togglePlay(); model.seek(to: 3); model.setLoops(true); model.setMuted(false)
        #expect(rig.layerChanges.isEmpty && rig.audioChanges.isEmpty && rig.model.layers.background == nil && rig.model.layers.foreground == nil)
    }

    @Test func theSendButtonsFollowTheKindAndTheShow() {
        let v = PreviewSendActions.available(for: .video, showIsLive: true)
        #expect(v.background && v.foreground && !v.playLive)
        let notLive = PreviewSendActions.available(for: .video, showIsLive: false)
        #expect(notLive.background && !notLive.foreground, "a clip over the words needs a live show")
        let p = PreviewSendActions.available(for: .image, showIsLive: true)
        #expect(p.background && p.foreground && !p.playLive)
        let a = PreviewSendActions.available(for: .audio, showIsLive: false)
        #expect(!a.background && !a.foreground && a.playLive)
    }
}
