// MEDIA-001: scenes published with `media:`. The rules themselves are tested in MediaRulesTests; these tests check that
// the model's state, passed through `PublishedScenes`, reaches each kind of screen as those rules say.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct MediaScenesTests {
    let audience = ScreenProfile(name: "Audience", role: .audience, destination: .window)
    let stage = ScreenProfile(name: "Stage", role: .stage, destination: .window)
    let broadcast = ScreenProfile(name: "Broadcast", role: .broadcast, destination: .window)
    var profiles: [ScreenProfile] { [audience, stage, broadcast] }

    func liveState() -> ShowState {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "Amazing grace"), SlideContent(primary: "How sweet")])))
        state.apply(.trigger(index: 0))
        return state
    }

    func scenes(_ state: ShowState, _ media: MediaLayers) -> PublishedScenes {
        PublishedScenes(state: state, clockText: "10:00", profiles: profiles, media: media)
    }

    func words(_ scene: SceneDescription) -> [String] { scene.textLayers.map(\.text) }

    func rig() async throws -> (MediaRig, MediaAsset, MediaAsset) {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        return (rig, loop, clip)
    }

    @Test func startingAClipHidesTheLyricsOnAudienceAndBroadcastAndEndingRestoresThem() async throws {
        let (rig, _, clip) = try await rig()
        let state = liveState()
        #expect(words(scenes(state, rig.model.layers).scene(forScreen: audience.id)) == ["Amazing grace"])

        rig.model.playForeground(clip.id)
        let during = scenes(state, rig.model.layers)
        for screen in [audience, broadcast] {
            let scene = during.scene(forScreen: screen.id)
            #expect(scene.foregroundMedia == .video(clip.id))
            #expect(words(scene).isEmpty)
        }

        rig.clock.advance(11)
        #expect(rig.model.tick())
        let after = scenes(state, rig.model.layers)
        for screen in [audience, broadcast] {
            let scene = after.scene(forScreen: screen.id)
            #expect(scene.foregroundMedia == nil)
            #expect(words(scene) == ["Amazing grace"])
        }
    }

    @Test func theWordsComeBackByTheClockEvenIfThePlayerNeverReportsTheEnd() async throws {
        let (rig, _, clip) = try await rig()
        let state = liveState()
        rig.model.playForeground(clip.id)
        #expect(words(scenes(state, rig.model.layers).scene(forScreen: audience.id)).isEmpty)
        // Nothing ever calls playerReportedEnd(): a stalled or silent player. Only the timer's tick runs.
        rig.clock.advance(5)
        #expect(!rig.model.tick())
        rig.clock.advance(5.01)
        #expect(rig.model.tick())
        #expect(words(scenes(state, rig.model.layers).scene(forScreen: audience.id)) == ["Amazing grace"])
        #expect(scenes(state, rig.model.layers).scene(forScreen: audience.id).foregroundMedia == nil)
    }

    @Test func theStageNeverShowsMediaOrLosesItsWords() async throws {
        let (rig, loop, clip) = try await rig()
        let state = liveState()
        let before = scenes(state, MediaLayers()).scene(forScreen: stage.id)
        rig.model.setBackground(loop.id)
        rig.model.playForeground(clip.id)
        let scene = scenes(state, rig.model.layers).scene(forScreen: stage.id)
        #expect(scene.foregroundMedia == nil && scene.backgroundMedia == nil)
        #expect(scene == before)
    }

    @Test func stopRemovesMediaFromEveryScene() async throws {
        let (rig, loop, clip) = try await rig()
        rig.model.setBackground(loop.id)
        rig.model.playForeground(clip.id)
        var state = liveState()
        state.apply(.stop)
        let stopped = scenes(state, rig.model.layers)
        for screen in profiles {
            let scene = stopped.scene(forScreen: screen.id)
            #expect(scene.foregroundMedia == nil && scene.backgroundMedia == nil)
            if screen.role != .stage { #expect(words(scene).isEmpty) }     // the stage keeps its own clock and labels
        }
    }

    @Test func theChosenBackgroundReachesAScreenWhoseThemeUsesMediaBehindTheWords() async throws {
        let (rig, loop, _) = try await rig()
        rig.model.setBackground(loop.id)
        let published = scenes(liveState(), rig.model.layers)
        // The audience's default theme has a media background; the broadcast lower third is transparent, so it has none.
        let audienceScene = published.scene(forScreen: audience.id)
        #expect(audienceScene.backgroundMedia == .video(loop.id) && words(audienceScene) == ["Amazing grace"])
        let broadcastScene = published.scene(forScreen: broadcast.id)
        #expect(broadcastScene.backgroundMedia == nil && words(broadcastScene) == ["Amazing grace"])
        #expect(published.scene(forScreen: stage.id).backgroundMedia == nil)
        rig.model.clearBackground()
        #expect(scenes(liveState(), rig.model.layers).scene(forScreen: audience.id).backgroundMedia == nil)
    }

    @Test func clearKeepsTheClipOnTheScreensAndStopRemovesIt() async throws {
        let (rig, _, clip) = try await rig()
        rig.model.playForeground(clip.id)
        var state = liveState()
        state.apply(.clear)
        #expect(scenes(state, rig.model.layers).scene(forScreen: audience.id).foregroundMedia == .video(clip.id))
        // The model removes the clip itself when the app reports that the show stopped.
        rig.model.showStateChanged(isLive: false)
        #expect(rig.model.layers.foreground == nil)
    }

    @Test func publishingWithoutMediaChangesNothing() {
        let state = liveState()
        let plain = PublishedScenes(state: state, clockText: "10:00", profiles: profiles)
        let empty = PublishedScenes(state: state, clockText: "10:00", profiles: profiles, media: MediaLayers())
        #expect(plain == empty)
    }
}
