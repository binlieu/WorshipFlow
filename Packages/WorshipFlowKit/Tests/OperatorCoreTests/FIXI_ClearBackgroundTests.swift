// FIX-I item 4, owner: "when I clear the background, if the media bin background have live selected on, if I press next / previous, it
// will carry the background selected in the media bin. when clear the background. the live in media bin should be cleared as well".
// Clear background drops the live background chosen from the bin (and a Play-folder run to the background); Clear foreground does the same
// for the foreground; Clear all for both. Next, Previous and Go Live never bring a dropped choice back; the slide's own background does
// come back. Blackout is still reversible and drops nothing.
import Testing
import Foundation
import Domain
import CueEngine
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXI_ClearBackgroundTests {
    struct Rig {
        let workspace: WorkspaceModel
        let editor: SlideEditorModel
        let media: MediaRig
        let target: ShowCueTarget
        let loop: MediaAsset, clip: MediaAsset, own: MediaAsset
    }

    /// Three slides, the middle one with its own background; the bin's loop is the live background and a clip plays over the words.
    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: ManualSaveClock())
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let loop = await media.add("loop.mov"), clip = await media.add("clip.mov"), own = await media.add("own.mov")
        workspace.onShowChange = { state in media.model.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut) }
        MediaWiring.connect(workspace: workspace, media: media.model)
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        let editor = SlideEditorModel(workspace: workspace)
        editor.setBackground(MediaSelection(asset: own), forSlide: workspace.slides[1].id)
        await workspace.goLive()
        media.model.setBackground(loop.id)
        media.model.playForeground(clip.id)
        let fake = FakeShow()
        let target = ShowCueTarget(transport: workspace, looks: fake, stage: fake, media: MediaCueAdapter(media: media.model, audio: nil), midiOut: { nil })
        return Rig(workspace: workspace, editor: editor, media: media, target: target, loop: loop, clip: clip, own: own)
    }

    private func background(_ r: Rig) -> SceneMedia? {
        let layers = LiveMedia.effective(override: r.media.model.layers, slide: r.workspace.show.liveSlideAtPlace, at: 1000)
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: .fullScreen, look: .standard, props: [], media: layers).backgroundMedia
    }

    @Test func clearBackgroundDropsTheBinChoiceAndHidesTheBackground() async throws {
        let r = try await rig()
        #expect(r.media.model.hasLiveBackgroundOverride)
        try r.target.perform(.transport(.clearBackground))
        #expect(!r.media.model.hasLiveBackgroundOverride && r.media.model.layers.background == nil, "the bin tile loses its LIVE mark and the inspector row goes")
        #expect(r.workspace.show.isBackgroundCleared)
        #expect(background(r) == nil)
        #expect(r.media.model.layers.foreground != nil, "the clip over the words is a different layer")
    }

    @Test func nextPreviousAndGoLiveDoNotBringTheDroppedChoiceBack() async throws {
        for step in 0..<3 {
            let r = try await rig()
            if step == 1 { await r.workspace.goLive(at: 1) }          // Previous only counts when it moves: not from the first slide
            try r.target.perform(.transport(.clearBackground))
            switch step {
            case 0: await r.workspace.next()
            case 1: await r.workspace.previous()
            default: await r.workspace.goLive()
            }
            #expect(!r.workspace.show.isBackgroundCleared, "step \(step): the next slide shows its background again")
            #expect(!r.media.model.hasLiveBackgroundOverride && r.media.model.layers.background == nil, "step \(step): the bin choice stays dropped")
            #expect(background(r) != .video(r.loop.id), "step \(step)")
        }
    }

    @Test func whatComesBackIsTheSlidesOwnBackgroundAsIfNoBinChoiceHadBeenMade() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        await r.workspace.next()                                  // slide two, which has its own background
        #expect(background(r) == .video(r.own.id))
        await r.workspace.next()                                  // slide three has none: the theme's
        #expect(background(r) == nil)
    }

    @Test func clearBackgroundEndsAPlayFolderRunOnTheBackground() async throws {
        let r = try await rig()
        let folder = UUID()
        let a = MediaAsset(id: UUID(), name: "a", kind: .video, path: "/hot/a.mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast)
        r.media.model.setHotAssets(folder, [a])
        r.media.model.playFolder(folder, on: .background)
        #expect(r.media.model.playingFolderID == folder)
        try r.target.perform(.transport(.clearBackground))
        #expect(r.media.model.playingFolderID == nil && r.media.model.layers.background == nil)
        await r.workspace.next()
        #expect(r.media.model.playingFolderID == nil && r.media.model.layers.background == nil)
    }

    @Test func clearForegroundDropsTheForegroundChosenFromTheBinAndLeavesTheBackground() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearForeground))
        #expect(r.media.model.layers.foreground == nil)
        #expect(r.media.model.hasLiveBackgroundOverride, "the other layer is untouched")
        await r.workspace.next()
        #expect(r.media.model.layers.foreground == nil)
    }

    @Test func clearForegroundEndsAPlayFolderRunOnTheForeground() async throws {
        let r = try await rig()
        let folder = UUID()
        let a = MediaAsset(id: UUID(), name: "a", kind: .video, path: "/hot/a.mov", duration: 10, pixelWidth: 1, pixelHeight: 1, addedAt: .distantPast)
        r.media.model.setHotAssets(folder, [a])
        r.media.model.playFolder(folder, on: .foreground)
        try r.target.perform(.transport(.clearForeground))
        #expect(r.media.model.playingFolderID == nil && r.media.model.layers.foreground == nil)
    }

    @Test func clearAllDropsBothChoicesAndTheWordsGoToo() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearAll))
        #expect(r.workspace.show.isCleared)
        #expect(r.media.model.layers.foreground == nil)
        #expect(!r.media.model.hasLiveBackgroundOverride && r.media.model.layers.background == nil)
        await r.workspace.next()
        #expect(r.media.model.layers.background == nil && r.media.model.layers.foreground == nil, "Next does not bring either choice back")
        #expect(background(r) == .video(r.own.id), "the slide's own background shows as it would with no bin choice")
    }

    @Test func clearingTheWordsAloneKeepsTheBinChoices() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clear))
        #expect(r.media.model.hasLiveBackgroundOverride && r.media.model.layers.foreground != nil)
    }

    @Test func blackoutIsStillReversibleAndDropsNothing() async throws {
        let r = try await rig()
        r.workspace.blackout()
        #expect(r.media.model.hasLiveBackgroundOverride && r.media.model.layers.foreground != nil)
        r.workspace.blackout()
        #expect(r.media.model.hasLiveBackgroundOverride && r.media.model.layers.foreground != nil)
        #expect(background(r) == .video(r.loop.id))
    }

    @Test func aNewBinChoiceAfterAClearIsLiveAgain() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        r.media.model.setBackground(r.clip.id)
        #expect(r.media.model.hasLiveBackgroundOverride && !r.workspace.show.isBackgroundCleared)
        #expect(background(r) == .video(r.clip.id))
    }

    @Test func theDroppedChoiceIsNotRememberedForTheNextLaunch() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        await r.media.model.flush()
        let again = try #require(r.media.relaunched())
        await again.model.load()
        #expect(again.model.layers.background == nil)
    }
}
