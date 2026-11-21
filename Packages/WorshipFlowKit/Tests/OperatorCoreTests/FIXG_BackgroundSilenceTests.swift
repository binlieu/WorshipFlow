// FIX-G item 1 (MEDIA-010): an unmuted background video is silent while its picture is hidden. Clear background, Stop and
// Blackout; the sound returns with the picture. The registry plays whatever `LiveMedia.playing` hands it, so a hidden
// background must not be in that set at all (patching the mute flag alone would leave a player running).
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXG_BackgroundSilenceTests {
    private func deck() -> ShowDeck {
        ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "one"), SlideContent(primary: "two"), SlideContent(primary: "three")])
    }

    private func liveShow() -> ShowState {
        var show = ShowState()
        show.apply(.load(deck()))
        show.apply(.trigger(index: 0))
        return show
    }

    /// What the speakers would carry: a background player exists and its sound is on.
    private func audible(_ rig: MediaRig, _ show: ShowState) -> Bool {
        let layers = LiveMedia.playing(override: rig.model.layers, state: show, at: 1000)
        return layers.background != nil && !rig.model.backgroundHeardMuted
    }

    private func unmutedBackground() async throws -> (MediaRig, ShowState) {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.setBackground(loop.id)
        rig.model.setBackgroundMuted(false)
        return (rig, liveShow())
    }

    @Test func anUnmutedBackgroundIsHeardWhenNothingHidesIt() async throws {
        let (rig, show) = try await unmutedBackground()
        #expect(audible(rig, show))
    }

    @Test func clearBackgroundSilencesItAndNextBringsTheSoundBack() async throws {
        let (rig, base) = try await unmutedBackground()
        var show = base
        show.apply(.clearBackground)
        #expect(show.isBackgroundCleared)
        #expect(!audible(rig, show), "no background player plays while the background is cleared")
        #expect(rig.model.hasLiveBackgroundOverride, "the choice itself is kept")
        show.apply(.next)
        #expect(audible(rig, show), "Next brings the picture and its sound back")
    }

    @Test func stopSilencesItAndGoLiveBringsItBack() async throws {
        let (rig, base) = try await unmutedBackground()
        var show = base
        show.apply(.stop)
        #expect(show.isStopped)
        #expect(!audible(rig, show), "after Stop nothing plays, whatever the mute flag says")
        show.apply(.trigger(index: 0))
        #expect(audible(rig, show))
    }

    @Test func blackoutStillComposesAsBeforeAndTheSoundIsSilencedByTheFlagThere() async throws {
        let (rig, base) = try await unmutedBackground()
        var show = base
        show.apply(.blackout)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        let layers = LiveMedia.playing(override: rig.model.layers, state: show, at: 1000)
        #expect(layers.background != nil, "Blackout keeps the player running, as before")
        #expect(rig.model.backgroundHeardMuted)
        #expect(!audible(rig, show))
        let scene = SceneComposer.scene(for: .audience, state: show, theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(scene.backgroundMedia == nil, "the picture is black under Blackout")
        show.apply(.blackout)
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(audible(rig, show))
    }

    @Test func aSlidesOwnBackgroundIsSilencedTheSameWay() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackgroundMuted(false)
        var slides = deck()
        slides.slides[0].background = MediaSelection(asset: loop)
        var show = ShowState()
        show.apply(.load(slides)); show.apply(.trigger(index: 0))
        #expect(LiveMedia.playing(override: MediaLayers(), state: show, at: 1000).background != nil)
        show.apply(.clearBackground)
        #expect(LiveMedia.playing(override: MediaLayers(), state: show, at: 1000).background == nil)
    }

    @Test func aClipOverTheWordsIsNotTouchedByClearBackground() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(loop.id)
        var show = liveShow()
        show.apply(.clearBackground)
        #expect(LiveMedia.playing(override: rig.model.layers, state: show, at: 1000).foreground != nil)
    }
}
