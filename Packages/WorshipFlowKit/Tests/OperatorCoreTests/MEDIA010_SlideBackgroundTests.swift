// MEDIA-010 item 6: a video or picture dropped on one slide is that slide's own background. Unlike a bin choice this is
// an edit to the presentation: saved, undoable, marked on the thumbnail, removable, used when the slide goes live unless
// a live override is on, and an edit to an inactive slide never changes Live.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct MEDIA010_SlideBackgroundTests {
    struct Rig {
        let store: LibraryStore
        let workspace: WorkspaceModel
        let editor: SlideEditorModel
        let media: MediaRig
        let clock: ManualSaveClock
        let presentationID: UUID
        let loop: MediaAsset
        let other: MediaAsset
        let picture: MediaAsset
        var video: MediaSelection { MediaSelection(asset: loop) }
    }

    private func rig() async throws -> Rig {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: clock)
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let loop = await media.add("loop.mov"), other = await media.add("other.mov"), picture = await media.add("cross.png")
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        return Rig(store: store, workspace: workspace, editor: SlideEditorModel(workspace: workspace), media: media, clock: clock,
                   presentationID: song.id, loop: loop, other: other, picture: picture)
    }

    private func stored(_ r: Rig) async throws -> [MediaSelection?] {
        try await r.store.slides(of: r.presentationID).map(\.content.background)
    }

    private func scene(_ r: Rig, theme: Theme) -> SceneDescription {
        let layers = LiveMedia.effective(override: r.media.model.layers, slide: r.workspace.show.liveSlideAtPlace, at: 1000)
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: theme, look: .standard, props: [], media: layers)
    }

    @Test func aDroppedBackgroundIsSavedAndComesBackAfterReopeningTheLibrary() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[1].id
        #expect(r.editor.setBackground(r.video, forSlide: slideID))
        #expect(r.workspace.slides[1].content.background == r.video, "shown in the open presentation at once")
        #expect(try await stored(r) == [nil, nil, nil], "not written yet")
        await r.clock.advance(by: 2.1)
        #expect(try await stored(r) == [nil, r.video, nil])
        let reopened = WorkspaceModel(store: r.store, clock: ManualSaveClock())
        await reopened.load()
        await reopened.openPresentation(r.presentationID)
        #expect(reopened.slides.map(\.content.background) == [nil, r.video, nil])
        #expect(reopened.slides[0].content.primary == "one" && reopened.slides[1].content.primary == "two", "words are untouched")
    }

    @Test func aPictureCanBeABackgroundAndASoundFileCannot() async throws {
        let r = try await rig()
        let sound = MediaAsset(name: "s", kind: .audio, path: "/m/s.mp3", duration: 3)
        #expect(SlideBackgroundDrop.selection(for: r.picture)?.kind == .image)
        #expect(SlideBackgroundDrop.selection(for: r.loop)?.kind == .video)
        #expect(SlideBackgroundDrop.selection(for: sound) == nil)
        #expect(!r.editor.setBackground(nil, forSlide: UUID()), "an unknown slide changes nothing")
    }

    @Test func theChangeCanBeUndoneAndRedoneAndRemoved() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[0].id
        r.editor.setBackground(r.video, forSlide: slideID)
        #expect(r.editor.canUndo)
        r.editor.undo()
        #expect(r.workspace.slides[0].content.background == nil)
        r.editor.redo()
        #expect(r.workspace.slides[0].content.background == r.video)
        r.editor.setBackground(nil, forSlide: slideID)          // "Use the presentation's background"
        #expect(r.workspace.slides[0].content.background == nil)
        await r.clock.advance(by: 2.1)
        #expect(try await stored(r) == [nil, nil, nil])
        r.editor.undo()
        #expect(r.workspace.slides[0].content.background == r.video)
    }

    @Test func settingTheSameBackgroundAgainIsNotAnotherUndoStep() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[0].id
        r.editor.setBackground(r.video, forSlide: slideID)
        r.editor.setBackground(r.video, forSlide: slideID)
        r.editor.undo()
        #expect(r.workspace.slides[0].content.background == nil)
        #expect(!r.editor.canUndo)
    }

    @Test func undoingAnObjectEditDoesNotRollBackTheBackground() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[0].id
        r.editor.add(.rectangle)
        r.editor.setBackground(r.video, forSlide: slideID)
        r.editor.undo()                                    // the background step
        #expect(r.workspace.slides[0].content.background == nil && r.workspace.slides[0].content.objects.count == 1)
        r.editor.redo()
        r.editor.add(.ellipse)
        r.editor.undo()                                    // the ellipse step
        #expect(r.workspace.slides[0].content.background == r.video && r.workspace.slides[0].content.objects.count == 1)
    }

    @Test func aSlideGoingLiveUsesItsOwnBackgroundOnAnyTheme() async throws {
        let r = try await rig()
        r.editor.setBackground(r.video, forSlide: r.workspace.slides[0].id)
        await r.workspace.goLive()
        for theme in [Theme.fullScreen, MEDIA010_LiveOverrideTests.colourTheme] {
            #expect(scene(r, theme: theme).backgroundMedia == .video(r.loop.id))
        }
        await r.workspace.next()
        #expect(scene(r, theme: .fullScreen).backgroundMedia == nil, "the next slide has none of its own")
    }

    @Test func aLiveOverrideBeatsTheSlidesOwnBackgroundAndDroppingItBringsTheOwnBack() async throws {
        let r = try await rig()
        r.editor.setBackground(r.video, forSlide: r.workspace.slides[0].id)
        await r.workspace.goLive()
        r.media.model.setBackground(r.other.id)
        #expect(scene(r, theme: .fullScreen).backgroundMedia == .video(r.other.id))
        r.media.model.dropBackgroundOverride()
        #expect(scene(r, theme: .fullScreen).backgroundMedia == .video(r.loop.id))
    }

    @Test func theEffectiveLayersCarryThePlayerTransportOfTheSlidesBackground() {
        let slide = SlideContent(primary: "x", background: MediaSelection(assetID: UUID(), kind: .video, duration: 8))
        let layers = LiveMedia.effective(override: MediaLayers(), slide: slide, at: 50)
        #expect(layers.background?.selection == slide.background && layers.background?.transport.loops == true)
        #expect(LiveMedia.effective(override: MediaLayers(), slide: SlideContent(primary: "y"), at: 50).background == nil)
        #expect(LiveMedia.preview(slide: slide, at: 50).foreground == nil)
    }

    @Test func editingAnInactiveSlidesBackgroundLeavesLiveUnchanged() async throws {
        let r = try await rig()
        await r.workspace.goLive()                          // slide 0 is live
        let liveDeck = r.workspace.show.liveDeck
        let before = scene(r, theme: .fullScreen)
        r.editor.setBackground(r.video, forSlide: r.workspace.slides[2].id)
        #expect(r.workspace.show.liveDeck == liveDeck, "the live deck is not touched")
        #expect(scene(r, theme: .fullScreen) == before)
        // The live slide's own edit also waits for the next Go Live.
        r.editor.setBackground(MediaSelection(asset: r.other), forSlide: r.workspace.slides[0].id)
        #expect(scene(r, theme: .fullScreen) == before)
        await r.workspace.goLive()
        #expect(scene(r, theme: .fullScreen).backgroundMedia == .video(r.other.id))
    }

    @Test func clearingTheWordsLeavesTheSlidesOwnBackgroundOnScreen() async throws {
        let r = try await rig()
        r.editor.setBackground(r.video, forSlide: r.workspace.slides[0].id)
        await r.workspace.goLive()
        r.workspace.clear()
        #expect(r.workspace.show.liveSlide == nil)
        #expect(scene(r, theme: .fullScreen).backgroundMedia == .video(r.loop.id), "Clear hides the words, not the background")
        #expect(r.workspace.show.liveSlideAtPlace?.background == r.video)
        r.workspace.clearBackground()
        #expect(scene(r, theme: .fullScreen).backgroundMedia == nil)
    }

    @Test func aQuickEditOfTheLiveWordsKeepsTheLiveSlidesBackground() async throws {
        let r = try await rig()
        r.editor.setBackground(r.video, forSlide: r.workspace.slides[0].id)
        await r.workspace.goLive()
        var content = try #require(r.workspace.show.liveSlide)
        content.primary = "changed"
        await r.workspace.quickEditLiveSlide(content)
        #expect(scene(r, theme: .fullScreen).backgroundMedia == .video(r.loop.id))
        #expect(r.workspace.slides[0].content.background == r.video)
    }

    @Test func theThumbnailMarkSaysWhetherTheSlideHasItsOwnBackground() {
        #expect(SlideBackgroundDrop.hasOwnBackground(SlideContent(primary: "a", background: MediaSelection(assetID: UUID(), kind: .image, duration: nil))))
        #expect(!SlideBackgroundDrop.hasOwnBackground(SlideContent(primary: "a")))
    }

    @Test func aDragFromTheBinIsToldApartFromAReorderDrag() {
        let id = UUID()
        #expect(SlideBackgroundDrop.mediaID(fromDragText: SlideBackgroundDrop.dragText(for: id)) == id)
        #expect(SlideBackgroundDrop.mediaID(fromDragText: "3") == nil, "a slide being reordered is just its index")
        #expect(SlideBackgroundDrop.mediaID(fromDragText: "wfmedia:not-a-uuid") == nil)
    }

    @Test func slideContentWithoutABackgroundEncodesAsItAlwaysDidAndOldContentDecodes() throws {
        let plain = try JSONEncoder().encode(SlideContent(primary: "a", secondary: "b"))
        #expect(!String(decoding: plain, as: UTF8.self).contains("background"))
        let old = Data(#"{"primary":"a"}"#.utf8)
        #expect(try JSONDecoder().decode(SlideContent.self, from: old).background == nil)
        let with = SlideContent(primary: "a", background: MediaSelection(assetID: UUID(), kind: .video, duration: 4))
        #expect(try JSONDecoder().decode(SlideContent.self, from: JSONEncoder().encode(with)) == with)
    }
}
