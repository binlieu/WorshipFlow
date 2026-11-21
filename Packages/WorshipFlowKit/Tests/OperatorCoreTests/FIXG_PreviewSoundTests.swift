// FIX-G item 9 (MEDIA-010): the sidebar preview player must not surprise a room. It starts muted (its sound goes through the Mac's
// default output, which may be the house system), says where it will be heard, remembers the operator's mute choice for the
// session only, and is paused when the item it shows is sent live.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXG_PreviewSoundTests {
    private let video = MediaAsset(name: "loop", kind: .video, path: "/m/loop.mov", duration: 20)
    private let other = MediaAsset(name: "other", kind: .video, path: "/m/other.mov", duration: 20)

    @Test func thePreviewOfTheAppStartsMutedAndTheFirstThingOpenedIsMuted() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel.sessionPreview(player: player, silent: false)
        #expect(model.isMuted)
        model.select(video)
        #expect(player.muted == true, "the player was told to be muted before it could play")
        #expect(model.canUnmute)
    }

    @Test func theMuteChoiceIsRememberedForTheSessionAndNotLonger() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel.sessionPreview(player: player, silent: false)
        model.select(video)
        model.setMuted(false)
        model.select(other)
        #expect(!model.isMuted && player.muted == false, "kept while the app runs")
        model.setMuted(true)
        model.select(video)
        #expect(model.isMuted && player.muted == true)
        // The next launch is a new model: muted again, whatever was chosen before.
        model.setMuted(false)
        let next = MediaPreviewModel.sessionPreview(player: FakePreviewPlayer(), silent: false)
        #expect(next.isMuted)
    }

    @Test func aLineSaysWhereTheSoundWillBeHeard() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel.sessionPreview(player: player, silent: false)
        model.select(video)
        let muted = model.heardLine(outputName: "MacBook Speakers")
        #expect(muted.contains("Muted") && muted.contains("MacBook Speakers") && muted.contains("default"))
        model.setMuted(false)
        let loud = model.heardLine(outputName: "MacBook Speakers")
        #expect(loud.contains("MacBook Speakers") && loud.contains("not the show"))
        #expect(model.heardLine(outputName: nil).contains("default sound output"), "no name known: still says where")
        let silent = MediaPreviewModel.sessionPreview(player: FakePreviewPlayer(), silent: true)
        silent.select(video)
        #expect(silent.heardLine(outputName: "X").contains("silent"))
    }

    @Test func sendingThePreviewedItemLiveAndOnlyThatOnePausesIt() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel.sessionPreview(player: player, silent: false)
        model.select(video)
        model.togglePlay()
        #expect(player.isPlaying)
        model.itemSentLive(other.id)
        #expect(player.isPlaying, "another item going live leaves the preview alone")
        model.itemSentLive(video.id)
        #expect(!player.isPlaying && player.log.last == "pause")
        model.itemSentLive(video.id)                      // already paused: nothing more happens
        #expect(player.log.filter { $0 == "pause" }.count == 1)
    }

    @Test func goingLiveWithoutSendingTheItemDoesNotStopThePreview() {
        let player = FakePreviewPlayer()
        let model = MediaPreviewModel.sessionPreview(player: player, silent: false)
        model.select(video)
        model.togglePlay()
        // Nothing in the model reacts to the show: it is only told when its own item is sent.
        #expect(player.isPlaying)
    }
}
