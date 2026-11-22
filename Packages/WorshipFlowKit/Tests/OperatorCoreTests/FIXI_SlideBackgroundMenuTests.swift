// FIX-I item 6, owner: "right click to the thumbnail slide have option to clear background for that slide". A slide thumbnail's context menu
// (Show grid and list, Edit film strip) offers "Clear this slide's background" whenever the slide has its own, and "Set background..." (a
// choice from the bin). Each is one undo step. Editing the slide that is live does not change Live until it is taken live again.
import Foundation
import Testing
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXI_SlideBackgroundMenuTests {
    struct Rig {
        let workspace: WorkspaceModel
        let editor: SlideEditorModel
        let media: MediaRig
        let clock: ManualSaveClock
        let loop: MediaAsset, other: MediaAsset, sound: MediaAsset
    }

    private func rig() async throws -> Rig {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: clock)
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let loop = await media.add("loop.mov"), other = await media.add("cross.png")
        let sound = await media.add("hymn.mp3")
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        return Rig(workspace: workspace, editor: SlideEditorModel(workspace: workspace), media: media, clock: clock, loop: loop, other: other, sound: sound)
    }

    private func scene(_ r: Rig) -> SceneDescription {
        let layers = LiveMedia.effective(override: r.media.model.layers, slide: r.workspace.show.liveSlideAtPlace, at: 1000)
        return SceneComposer.scene(for: .audience, state: r.workspace.show, theme: .fullScreen, look: .standard, props: [], media: layers)
    }

    @Test func theMenuUsesTheOwnersWordsAndOffersClearOnlyWhenThereIsSomethingToClear() {
        #expect(SlideBackgroundMenu.clearTitle == "Clear this slide's background")
        #expect(SlideBackgroundMenu.setTitle == "Set background…")
        #expect(SlideBackgroundMenu.clearIsOffered(for: SlideContent(primary: "x")) == false)
        var own = SlideContent(primary: "x")
        own.background = MediaSelection(assetID: UUID(), kind: .video, duration: 4)
        #expect(SlideBackgroundMenu.clearIsOffered(for: own))
    }

    @Test func theChoicesAreThePicturesAndVideosOfTheBinInOrderAndNeverASound() async throws {
        let r = try await rig()
        let names = SlideBackgroundMenu.choices(from: r.media.model.allAssets).map(\.name)
        #expect(names == r.media.model.allAssets.filter { $0.kind != .audio }.map(\.name) && !names.contains("hymn.mp3") && names.count == 2)
    }

    @Test func clearingASlidesBackgroundIsOneUndoStepAndItsWordsAreUntouched() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[1].id
        r.editor.setBackgroundFromMenu(MediaSelection(asset: r.loop), forSlide: slideID)
        r.editor.setBackgroundFromMenu(nil, forSlide: slideID)                // "Clear this slide's background", on a slide that was not selected
        #expect(r.workspace.slides[1].content.background == nil && r.workspace.slides[1].content.primary == "two")
        #expect(r.workspace.show.selectedIndex == 1, "the slide is selected so that Undo reaches it; nothing went live")
        #expect(r.workspace.show.liveDeck == nil)
        r.editor.undo()                                                       // one step brings it back
        #expect(r.workspace.slides[1].content.background == MediaSelection(asset: r.loop))
        r.editor.undo()                                                       // the next undo is the earlier "set"
        #expect(r.workspace.slides[1].content.background == nil)
    }

    @Test func choosingFromTheBinIsOneUndoStep() async throws {
        let r = try await rig()
        let slideID = r.workspace.slides[0].id
        let choice = try #require(SlideBackgroundMenu.choices(from: r.media.model.allAssets).first { $0.kind == .image })
        #expect(r.editor.setBackgroundFromMenu(SlideBackgroundDrop.selection(for: choice), forSlide: slideID))
        #expect(r.workspace.slides[0].content.background?.assetID == choice.id)
        r.editor.undo()
        #expect(r.workspace.slides[0].content.background == nil && !r.editor.canUndo)
    }

    @Test func editingTheLiveSlidesBackgroundDoesNotChangeLiveUntilItIsTakenLiveAgain() async throws {
        let r = try await rig()
        let slide = r.workspace.slides[0]
        r.editor.setBackground(MediaSelection(asset: r.loop), forSlide: slide.id)
        await r.workspace.goLive()
        #expect(scene(r).backgroundMedia == .video(r.loop.id))
        r.editor.setBackgroundFromMenu(nil, forSlide: slide.id)               // clear it while the slide is live
        #expect(scene(r).backgroundMedia == .video(r.loop.id), "Live still shows what was taken live")
        await r.workspace.goLive()
        #expect(scene(r).backgroundMedia == nil, "taken live again, it has none")
    }

    @Test func theTooltipSaysSo() {
        #expect(SlideBackgroundMenu.liveNote.contains("next time this slide is taken live"))
    }
}
