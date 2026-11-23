// SYS-015 (SLIDE, STAGE): the new object fields behave like the existing ones in the slide editor: an edit is kept (and written after the save delay),
// a duplicate carries them, and undo and redo restore them. The deck a presentation loads for preview carries the section name of each slide.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct SYS015_EditorTests {
    private func ready(_ lyrics: String = "one\n\ntwo\n\nthree") async throws -> (model: WorkspaceModel, editor: SlideEditorModel, store: LibraryStore, clock: ManualSaveClock, id: UUID) {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: lyrics, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return (model, SlideEditorModel(workspace: model), store, clock, p.id)
    }

    @Test func anEditOfTheNewFieldsIsKeptWrittenAndSurvivesDuplicateAndUndo() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.textBox))
        s.editor.edit(id) { o in
            o.name = "  Title  "
            o.isHidden = true
            o.isLocked = true
            if case .text(var t) = o.content { t.fit = .shrinkToFit; t.backgroundFill = ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.4); o.content = .text(t) }
        }
        let edited = try #require(s.editor.objects.first)
        #expect(edited.name == "Title" && edited.isHidden && edited.isLocked)
        guard case .text(let t) = edited.content else { Issue.record("not text"); return }
        #expect(t.fit == .shrinkToFit && t.backgroundFill?.alpha == 0.4)

        await s.clock.advance(by: 2.1)
        #expect(try await s.store.slides(of: s.id)[0].content.objects == [edited])        // written, all of it

        let copyID = try #require(s.editor.duplicate(id))
        let copy = try #require(s.editor.objects.first { $0.id == copyID })
        #expect(copy.id != id && copy.name == "Title" && copy.isHidden && copy.isLocked && copy.content == edited.content)

        s.editor.undo()                                                                     // the duplicate goes
        #expect(s.editor.objects == [edited])
        s.editor.undo()                                                                     // the whole edit (one coalesced step) goes
        let plain = try #require(s.editor.objects.first)
        #expect(plain.name == nil && !plain.isHidden && !plain.isLocked)
        s.editor.redo()
        #expect(s.editor.objects == [edited])
    }

    @Test func aVideoObjectInASlideSurvivesEditingTheOthers() async throws {
        let s = try await ready()
        var slide = try await s.store.slides(of: s.id)[0]
        let video = SlideObject(frame: NormalizedRect(x: 0.5, y: 0.5, width: 0.3, height: 0.3), content: .video(VideoObject(mediaID: UUID(), loops: false, muted: true)))
        slide.content.objects = [video]
        try await s.store.updateSlide(slide)
        await s.model.openPresentation(s.id)
        let box = try #require(s.editor.add(.rectangle))
        s.editor.edit(box) { $0.opacity = 0.5 }
        await s.clock.advance(by: 2.1)
        let stored = try await s.store.slides(of: s.id)[0].content.objects
        #expect(stored.count == 2 && stored[0] == video && stored[1].opacity == 0.5)
    }

    @Test func thePreviewDeckCarriesTheSectionNameOfEverySlide() async throws {
        let s = try await ready("Verse 1\nfirst\nsecond\n\nChorus\nthird")
        let deck = s.model.previewDeck()
        #expect(deck.slides.count == s.model.slides.count && deck.sectionNames.count == deck.slides.count)
        #expect(Set(deck.sectionNames.compactMap { $0 }).isSubset(of: ["Verse 1", "Chorus"]) && deck.sectionNames.contains("Chorus"))
        #expect(deck.sectionNames == s.model.slides.map { slide in s.model.groups.first { $0.id == slide.groupID }?.name })
        #expect(s.model.show.previewDeck?.sectionNames == deck.sectionNames)
    }
}
