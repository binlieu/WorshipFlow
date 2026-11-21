// MEDIA-002 acceptance tests: media transport and layer rules (MEDIA-02, MEDIA-03).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct MediaTransportTests {
    @Test func playPauseSeekOnAClip() {
        var t = MediaTransport(duration: 60, loops: false)
        #expect(t.status(at: 0) == .idle && t.position(at: 0) == 0)
        t.play(at: 100)
        #expect(t.status(at: 110) == .playing && t.position(at: 110) == 10)
        t.pause(at: 120)
        #expect(t.status(at: 500) == .paused && t.position(at: 500) == 20)
        t.seek(to: 45, at: 500)
        #expect(t.position(at: 600) == 45)                 // seeking while paused stays paused
        t.play(at: 600)
        #expect(t.position(at: 610) == 55)
        t.seek(to: 5, at: 610)
        #expect(t.status(at: 612) == .playing && t.position(at: 612) == 7)
    }

    /// MEDIA-03: a clip that reaches its end reports ended and holds its last position.
    @Test func clipEndsAtItsDuration() {
        var t = MediaTransport(duration: 60, loops: false)
        t.play(at: 0)
        #expect(t.status(at: 59.9) == .playing)
        #expect(t.status(at: 60) == .ended && t.position(at: 75) == 60)
        #expect(t.remaining(at: 45) == 15 && t.remaining(at: 75) == 0)
        t.play(at: 80)                                     // playing again after the end restarts from zero
        #expect(t.position(at: 83) == 3 && t.status(at: 83) == .playing)
    }

    /// MEDIA-02: a looping background never ends and wraps its position.
    @Test func loopWrapsAndNeverEnds() {
        var t = MediaTransport(duration: 20, loops: true)
        t.play(at: 0)
        #expect(t.status(at: 3600) == .playing)
        #expect(abs(t.position(at: 45) - 5) < 1e-9)
        #expect(t.loopCount(at: 45) == 2)
    }

    @Test func seekClampsAndStopResets() {
        var t = MediaTransport(duration: 60, loops: false)
        t.seek(to: 500, at: 0)
        #expect(t.position(at: 0) == 60)
        t.seek(to: -5, at: 0)
        #expect(t.position(at: 0) == 0)
        t.play(at: 0); t.stop()
        #expect(t.status(at: 10) == .idle && t.position(at: 10) == 0)
    }

    @Test func zeroOrUnknownDurationIsSafe() {
        var still = MediaTransport(duration: 0, loops: false)      // a still image, or duration not known yet
        still.play(at: 0)
        #expect(still.status(at: 100) == .playing && still.position(at: 100) == 0 && still.remaining(at: 100) == 0)
        var loop = MediaTransport(duration: 0, loops: true)
        loop.play(at: 0)
        #expect(loop.position(at: 9) == 0 && loop.loopCount(at: 9) == 0)
    }

    @Test func transportRoundTripsThroughCodable() throws {
        var t = MediaTransport(duration: 60, loops: false); t.play(at: 100)
        let d = try JSONDecoder().decode(MediaTransport.self, from: JSONEncoder().encode(t))
        #expect(d == t && d.position(at: 130) == 30)
    }
}

@Suite struct MediaLayersTests {
    let loopID = UUID(), clipID = UUID(), otherLoop = UUID()

    @Test func backgroundAndForegroundAreIndependent() {
        var layers = MediaLayers()
        #expect(layers.background == nil && layers.foreground == nil)
        layers.setBackground(MediaSelection(assetID: loopID, kind: .video, duration: 20), at: 0)
        #expect(layers.background?.selection.assetID == loopID)
        #expect(layers.background?.transport.loops == true && layers.background?.transport.status(at: 5) == .playing)
        layers.startForeground(MediaSelection(assetID: clipID, kind: .video, duration: 60), at: 10)
        #expect(layers.foreground?.selection.assetID == clipID && layers.foreground?.transport.loops == false)
        #expect(layers.background?.selection.assetID == loopID)        // the background keeps running underneath
    }

    /// MEDIA-03: when the clip ends, the foreground goes away and the previous state is back.
    @Test func foregroundClearsItselfWhenItEnds() {
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: loopID, kind: .video, duration: 20), at: 0)
        layers.startForeground(MediaSelection(assetID: clipID, kind: .video, duration: 60), at: 10)
        #expect(layers.tick(at: 69.9) == false)
        #expect(layers.tick(at: 70) == true)                            // returns true when something changed
        #expect(layers.foreground == nil && layers.background?.selection.assetID == loopID)
        #expect(layers.tick(at: 71) == false)
    }

    /// A paused clip does not end by the clock.
    @Test func pausedForegroundStays() {
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: clipID, kind: .video, duration: 60), at: 0)
        layers.pauseForeground(at: 30)
        #expect(layers.tick(at: 1000) == false && layers.foreground != nil)
        layers.resumeForeground(at: 1000)
        #expect(layers.tick(at: 1030) == true && layers.foreground == nil)
    }

    @Test func stillImagesNeverEndByThemselves() {
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: clipID, kind: .image, duration: nil), at: 0)
        #expect(layers.tick(at: 100_000) == false && layers.foreground != nil)
        layers.stopForeground()
        #expect(layers.foreground == nil)
    }

    @Test func replacingAndClearingTheBackground() {
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: loopID, kind: .video, duration: 20), at: 0)
        layers.setBackground(MediaSelection(assetID: otherLoop, kind: .image, duration: nil), at: 5)
        #expect(layers.background?.selection.assetID == otherLoop)
        layers.setBackground(nil, at: 6)
        #expect(layers.background == nil)
    }

    @Test func audioIsNeverAVisualLayer() {
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: loopID, kind: .audio, duration: 20), at: 0)
        layers.startForeground(MediaSelection(assetID: clipID, kind: .audio, duration: 20), at: 0)
        #expect(layers.background == nil && layers.foreground == nil)
    }
}

@Suite struct MediaSceneTests {
    func liveState() -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amazing grace", secondary: "Ân điển")])))
        s.apply(.trigger(index: 0))
        return s
    }
    let clip = MediaSelection(assetID: UUID(), kind: .video, duration: 60)
    let loop = MediaSelection(assetID: UUID(), kind: .video, duration: 20)

    /// While a foreground clip plays, the audience sees the clip and not the lyrics; props stay.
    @Test func foregroundHidesSlideTextOnAudienceAndBroadcast() {
        var layers = MediaLayers(); layers.setBackground(loop, at: 0); layers.startForeground(clip, at: 0)
        let logo = Prop(id: UUID(), name: "Logo", imagePath: "/tmp/logo.png", frame: NormalizedRect(x: 0.8, y: 0, width: 0.1, height: 0.1), opacity: 1, isOn: true)
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [logo], media: layers)
        #expect(scene.foregroundMedia == .video(clip.assetID))
        #expect(scene.textLayers.isEmpty)
        #expect(scene.overlayImages.count == 1)
        #expect(scene.backgroundMedia == .video(loop.assetID))
    }

    @Test func withoutForegroundTheSlideShowsOverTheChosenBackground() {
        var layers = MediaLayers(); layers.setBackground(loop, at: 0)
        let scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(scene.foregroundMedia == nil && scene.textLayers.count == 2)
        #expect(scene.backgroundMedia == .video(loop.assetID) && scene.showsVideo)
    }

    /// A theme with a colour or transparent background does not show the media background.
    @Test func themeDecidesWhetherTheMediaBackgroundShows() {
        var layers = MediaLayers(); layers.setBackground(loop, at: 0)
        let lower = SceneComposer.scene(for: .broadcast, state: liveState(), theme: .lowerThird, look: .standard, props: [], media: layers)
        #expect(lower.backgroundMedia == nil && lower.showsVideo == false && lower.backgroundColor.alpha == 0)
    }

    @Test func stillImageBackgroundAndForeground() {
        let image = MediaSelection(assetID: UUID(), kind: .image, duration: nil)
        var layers = MediaLayers(); layers.setBackground(image, at: 0)
        var scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(scene.backgroundMedia == .image(image.assetID) && scene.showsVideo == false)
        layers.startForeground(image, at: 0)
        scene = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(scene.foregroundMedia == .image(image.assetID))
    }

    /// The stage never shows media; a Look that hides the background hides the media background too.
    @Test func stageAndLooks() {
        var layers = MediaLayers(); layers.setBackground(loop, at: 0); layers.startForeground(clip, at: 0)
        let stage = SceneComposer.scene(for: .stage, state: liveState(), theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(stage.foregroundMedia == nil && stage.backgroundMedia == nil)
        #expect(stage.textLayers.isEmpty == false)                       // the stage still shows the words
        let hidden = SceneComposer.scene(for: .audience, state: liveState(), theme: .fullScreen,
                                         look: ScreenLook(themeID: nil, visibleLayers: [.slide, .props]), props: [], media: layers)
        #expect(hidden.backgroundMedia == nil)
    }

    /// Stop empties media from the scene. Clear removes the words, not the media.
    @Test func clearAndStop() {
        var layers = MediaLayers(); layers.setBackground(loop, at: 0)
        var s = liveState(); s.apply(.clear)
        #expect(SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [], media: layers).backgroundMedia == .video(loop.assetID))
        s.apply(.stop)
        let stopped = SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [], media: layers)
        #expect(stopped.backgroundMedia == nil && stopped.foregroundMedia == nil)
    }

    /// Without the media argument everything behaves as before.
    @Test func defaultMediaArgumentChangesNothing() {
        let s = liveState()
        #expect(SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: []) ==
                SceneComposer.scene(for: .audience, state: s, theme: .fullScreen, look: .standard, props: [], media: nil))
    }
}
