// MEDIA-010 item 2: four separate live clears (lyric, background, foreground, music), each through the one command path,
// each removing only its own layer, composing with Blackout, and each brought back by the next Go Live or bin choice.
import Testing
import Foundation
import Domain
import CueEngine
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct MEDIA010_LiveClearTests {
    struct Rig {
        let workspace: WorkspaceModel
        let media: MediaRig
        let audio: AudioRig
        let target: ShowCueTarget
        let loop: MediaAsset
        let clip: MediaAsset
        let hymn: MediaAsset
    }

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: ManualSaveClock())
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let loop = await media.add("loop.mov")
        let clip = await media.add("clip.mov")
        let audio = try AudioRig(store: store)
        let hymn = AudioRig.sound("hymn")
        _ = await audio.loaded([hymn])
        workspace.onShowChange = { state in
            media.model.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut)
            audio.model.showStateChanged(isLive: !state.isStopped)
        }
        media.model.onBackgroundChosen = { workspace.showBackground() }
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        media.model.setBackground(loop.id)
        media.model.playForeground(clip.id)
        audio.model.play(hymn.id)
        let fake = FakeShow()
        let target = ShowCueTarget(transport: workspace, looks: fake, stage: fake, media: MediaCueAdapter(media: media.model, audio: audio.model),
                                   midiOut: { nil })
        return Rig(workspace: workspace, media: media, audio: audio, target: target, loop: loop, clip: clip, hymn: hymn)
    }

    private func scene(_ r: Rig, theme: Theme = .fullScreen, hideForeground: Bool = false) -> SceneDescription {
        let layers = LiveMedia.effective(override: r.media.model.layers, slide: r.workspace.show.liveSlide, at: 1000)
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: theme, look: .standard, props: [], media: layers)
    }

    private struct Present: Equatable { var words: Bool; var background: Bool; var foreground: Bool; var music: Bool }
    private func present(_ r: Rig) -> Present {
        // The words are drawn only while no clip covers them, so look at the show state for them.
        Present(words: r.workspace.show.liveSlide != nil, background: scene(r).backgroundMedia != nil,
                foreground: r.media.model.layers.foreground != nil, music: r.audio.model.isActive(r.hymn.id))
    }

    @Test func everythingIsOnToStartWith() async throws {
        let r = try await rig()
        #expect(present(r) == Present(words: true, background: true, foreground: true, music: true))
    }

    @Test func clearBackgroundRemovesOnlyTheBackground() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        #expect(present(r) == Present(words: true, background: false, foreground: true, music: true))
        #expect(r.workspace.show.isBackgroundCleared && !r.workspace.show.isCleared)
        let s = scene(r)
        #expect(s.backgroundMedia == nil && s.showsVideo == false && s.backgroundImage == nil, "not even the theme's own background")
    }

    @Test func clearForegroundRemovesOnlyTheClip() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearForeground))
        #expect(present(r) == Present(words: true, background: true, foreground: false, music: true))
    }

    @Test func clearMusicRemovesOnlyTheAudioPlayersCuesNotAVideosOwnSound() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearMusic))
        #expect(present(r) == Present(words: true, background: true, foreground: true, music: false))
        #expect(r.media.model.layers.foreground != nil, "the clip, with its own sound, keeps playing")
    }

    @Test func clearLyricIsTodaysClearAndLeavesTheOtherThree() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clear))
        #expect(present(r) == Present(words: false, background: true, foreground: true, music: true))
    }

    @Test func aLayerClearCancelsNothingElseAndMovesNothing() async throws {
        let r = try await rig()
        let epoch = r.workspace.transportEpoch
        let place = r.workspace.show.liveIndex
        try r.target.perform(.transport(.clearBackground))
        try r.target.perform(.transport(.clearForeground))
        try r.target.perform(.transport(.clearMusic))
        #expect(r.workspace.transportEpoch == epoch, "an in-flight Next is not cancelled")
        #expect(r.workspace.show.liveIndex == place && !r.workspace.show.isBlackedOut)
    }

    @Test func blackoutOnClearBackgroundBlackoutOffGivesTheWordsBackAndTheBackgroundStaysCleared() async throws {
        let r = try await rig()
        r.media.model.stopForeground()                 // a clip over the words would hide them whatever else is cleared
        r.workspace.blackout()
        try r.target.perform(.transport(.clearBackground))
        r.workspace.blackout()
        #expect(!r.workspace.show.isBlackedOut)
        #expect(r.workspace.show.liveSlide != nil)
        let s = scene(r)
        #expect(!s.textLayers.isEmpty, "the words are back")
        #expect(s.backgroundMedia == nil && r.workspace.show.isBackgroundCleared, "the background stays cleared")
    }

    @Test func blackoutSceneIsStillBlackWhateverIsCleared() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        r.workspace.blackout()
        let s = scene(r)
        #expect(s.textLayers.isEmpty && s.backgroundMedia == nil && s.backgroundColor == .black)
    }

    @Test func goLiveNextAndPreviousBringTheBackgroundBack() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        await r.workspace.next()
        // FIX-I item 4, owner: "when clear the background. the live in media bin should be cleared as well". The hidden background comes
        // back with the next slide, but the bin choice was dropped by the clear, so it is the slide's or the theme's own, not the loop.
        #expect(!r.workspace.show.isBackgroundCleared && scene(r).backgroundMedia == nil && !r.media.model.hasLiveBackgroundOverride)
        try r.target.perform(.transport(.clearBackground))
        await r.workspace.goLive()
        #expect(!r.workspace.show.isBackgroundCleared)
    }

    @Test func aNewBinChoiceBringsTheBackgroundBack() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        r.media.model.setBackground(r.clip.id)
        #expect(!r.workspace.show.isBackgroundCleared && scene(r).backgroundMedia == .video(r.clip.id))
    }

    @Test func clearsOnAStoppedShowDoNothingAndDoNotFail() async throws {
        let r = try await rig()
        r.workspace.stop()
        try r.target.perform(.transport(.clearBackground))
        #expect(r.workspace.show.isStopped && !r.workspace.show.isBackgroundCleared && r.workspace.lastError == nil)
    }

    @Test func aStopEndsTheClearSoTheNextShowStartsWithABackground() async throws {
        let r = try await rig()
        try r.target.perform(.transport(.clearBackground))
        r.workspace.stop()
        await r.workspace.goLive()
        #expect(!r.workspace.show.isBackgroundCleared)
    }

    @Test func theLayerClearsPublishToTheScreensLikeClearDoes() async throws {
        let r = try await rig()
        let before = LiveOutputKey(state: r.workspace.show, notes: nil)
        try r.target.perform(.transport(.clearBackground))
        #expect(LiveOutputKey(state: r.workspace.show, notes: nil) != before, "a changed key is what makes the app republish")
    }

    // MARK: Vocabulary

    @Test func theNewCommandsHaveSummariesAndKeepTheirShapeInJSON() throws {
        let all: [CueTransport] = [.clearBackground, .clearForeground, .clearMusic]
        #expect(all.map(\.summary) == ["Clear background", "Clear foreground", "Clear music"])
        for t in all {
            let data = try JSONEncoder().encode(CueAction.transport(t))
            #expect(try JSONDecoder().decode(CueAction.self, from: data) == .transport(t))
        }
        #expect(String(decoding: try JSONEncoder().encode(CueAction.transport(.clearBackground)), as: UTF8.self).contains("transport.clearBackground"))
        #expect(CueAction.transport(.clearMusic).isTransport)
    }

    @Test func theClearMenuListsThemWithShortcutsThatDoNotClashWithTheKeyTable() {
        let layers = ClearControl.layerMenu
        #expect(layers == [.clearBackground, .clearForeground, .clearMusic])
        #expect(ClearControl.menu == [.clearAll], "the earlier entry is unchanged")
        let keys = ShowShortcuts.all.map(\.key)
        #expect(Set(keys).count == keys.count, "no two commands share a key")
        for action in layers { #expect(ShowShortcuts.all.contains { $0.key == action.shortcut }) }
        #expect(ShowShortcuts.all.contains { $0.key == "esc" && $0.command == "Clear" })
    }

    @Test func theCueEditorOffersTheThreeClearsAsMacroActions() {
        let kinds: [CueActionKind] = [.clearLiveBackground, .clearLiveForeground, .clearMusic]
        let expected: [CueAction] = [.transport(.clearBackground), .transport(.clearForeground), .transport(.clearMusic)]
        for (kind, action) in zip(kinds, expected) {
            #expect(kind.isTransport && kind.group == "Show")
            #expect(CueActionEditing.defaultAction(for: kind, choices: CueChoices()) == action)
            #expect(CueActionKind.of(action) == kind)
            #expect(CueActionEditing.isAllowed(kind, in: .macro) && !CueActionEditing.isAllowed(kind, in: .slide))
            #expect(!CueActionEditing.describe(action, choices: CueChoices()).isBroken)
        }
        #expect(CueActionKind.clearBackground.title == "Clear background", "the earlier action (drop the override) is unchanged")
    }
}
