// FIX-G item 2 (MEDIA-010): a slide's own background lives with the slide in the library: undo and redo are saved, a re-flow that
// matches the slide carries it, and one that cannot is listed in the loss list before the operator confirms.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXG_SlideBackgroundLifecycleTests {
    private func rig() async throws -> (WorkspaceModel, SlideEditorModel, MediaRig, ManualSaveClock, LibraryStore, UUID) {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store, clock: clock)
        await workspace.load()
        let media = try MediaRig(store: store)
        await media.model.load()
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await workspace.openPresentation(song.id)
        return (workspace, SlideEditorModel(workspace: workspace), media, clock, store, song.id)
    }

    private func stored(_ store: LibraryStore, _ id: UUID) async throws -> [MediaSelection?] {
        try await store.slides(of: id).map(\.content.background)
    }

    @Test func undoAndRedoAreSavedWithTheSlide() async throws {
        let (workspace, editor, media, clock, store, id) = try await rig()
        let loop = await media.add("loop.mov")
        let video = MediaSelection(asset: loop)
        workspace.selectSlide(1)
        #expect(editor.setBackground(video, forSlide: workspace.slides[1].id))
        await clock.advance(by: 2.1)
        #expect(try await stored(store, id) == [nil, video, nil])
        editor.undo()
        await clock.advance(by: 2.1)
        #expect(try await stored(store, id) == [nil, nil, nil], "undo is written to the library")
        editor.redo()
        await clock.advance(by: 2.1)
        #expect(try await stored(store, id) == [nil, video, nil])
    }

    @Test func aReflowKeepsTheBackgroundOfAnUnchangedSlideAndNamesTheOnesItCannotKeep() async throws {
        let (workspace, editor, media, clock, store, id) = try await rig()
        let loop = await media.add("loop.mov")
        let video = MediaSelection(asset: loop)
        #expect(editor.setBackground(video, forSlide: workspace.slides[0].id))
        #expect(editor.setBackground(video, forSlide: workspace.slides[2].id))
        await clock.advance(by: 2.1)
        // The same song with the last slide's words changed: slide one is matched, slide three has no match.
        let results = [ReflowResult(sectionName: nil, content: SlideContent(primary: "one")),
                       ReflowResult(sectionName: nil, content: SlideContent(primary: "two")),
                       ReflowResult(sectionName: nil, content: SlideContent(primary: "new last line"))]
        let losses = await workspace.reflowLosses(id: id, results: results)
        #expect(losses.count == 1 && losses[0].primary == "three" && losses[0].hasBackground)
        #expect(await workspace.reflowPresentation(id: id, results: results))
        #expect(try await stored(store, id) == [video, nil, nil])
        #expect(workspace.slides.map(\.content.background) == [video, nil, nil])
    }
}
