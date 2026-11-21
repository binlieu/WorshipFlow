// FIX-G item 3 (LIB-005): "use the imported one" cannot be overwritten by typing that was still waiting to be saved. The editor's
// drafts are written before the import is applied (so the backup the import makes holds them), and after it the open presentation
// is reloaded from what the import wrote.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXG_ProgramImportWorkspaceTests {
    private func openedSong() async throws -> (WorkspaceModel, LibraryStore, ManualSaveClock, Presentation) {
        let store = try LibraryStore.inMemory()
        let clock = ManualSaveClock()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let song = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await model.openPresentation(song.id)
        return (model, store, clock, song)
    }

    /// What an import that says "use the imported one" does to the stored rows: the slides keep their ids (the package's ids are the
    /// library's own when it came from the same program) and get the imported words.
    private func replaceStored(_ store: LibraryStore, _ id: UUID, with words: [String]) async throws {
        var slides = try await store.slides(of: id)
        for (i, word) in words.enumerated() where i < slides.count {
            slides[i].content.primary = word
            try await store.updateSlide(slides[i])
        }
        for slide in slides.dropFirst(words.count) { try await store.deleteSlide(id: slide.id) }
    }

    @Test func waitingTypingIsWrittenBeforeTheImportRuns() async throws {
        let (model, store, _, song) = try await openedSong()
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed, not yet saved"))
        #expect(try await store.slides(of: song.id)[0].content.primary != "typed, not yet saved", "still only a draft")
        var seenInside = ""
        _ = try await model.importingProgram {
            seenInside = try await store.slides(of: song.id)[0].content.primary
            return ProgramImportOutcome(playlistID: nil, replaced: [])
        }
        #expect(seenInside == "typed, not yet saved", "the draft reached the library before the import ran")
    }

    @Test func theImportedContentIsNotOverwrittenByATypedDraftAndTheOpenPresentationIsReloaded() async throws {
        let (model, store, clock, song) = try await openedSong()
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed, not yet saved"))
        let outcome = try await model.importingProgram {
            try await replaceStored(store, song.id, with: ["imported one", "imported two"])
            return ProgramImportOutcome(playlistID: nil, replaced: [song.id])
        }
        #expect(outcome.replaced == [song.id])
        #expect(model.slides.map(\.content.primary) == ["imported one", "imported two"], "the open presentation shows the import")
        // Whatever saves later must not bring the typing back.
        await clock.advance(by: 10)
        await model.flush()
        #expect(try await store.slides(of: song.id).map(\.content.primary) == ["imported one", "imported two"])
        #expect(model.slides.map(\.content.primary) == ["imported one", "imported two"])
    }

    @Test func typingDuringTheImportInAReplacedPresentationIsDroppedNotWrittenOverIt() async throws {
        let (model, store, clock, song) = try await openedSong()
        _ = try await model.importingProgram {
            // The operator types while the import is copying files.
            await MainActor.run { model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed during")) }
            try await replaceStored(store, song.id, with: ["imported only"])
            return ProgramImportOutcome(playlistID: nil, replaced: [song.id])
        }
        await clock.advance(by: 10)
        await model.flush()
        #expect(try await store.slides(of: song.id).map(\.content.primary) == ["imported only"])
    }

    @Test func aPresentationThatWasNotReplacedKeepsItsDraft() async throws {
        let (model, store, _, song) = try await openedSong()
        _ = try await model.importingProgram {
            // An import that replaced something else.
            await MainActor.run { model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed during")) }
            return ProgramImportOutcome(playlistID: nil, replaced: [UUID()])
        }
        await model.flush()
        #expect(try await store.slides(of: song.id)[0].content.primary == "typed during")
    }

    @Test func aFailedImportStillHasItsDraftsSaved() async throws {
        struct Boom: Error {}
        let (model, store, _, song) = try await openedSong()
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "typed"))
        await #expect(throws: Boom.self) {
            _ = try await model.importingProgram { throw Boom() }
        }
        #expect(try await store.slides(of: song.id)[0].content.primary == "typed")
    }

    @Test func theLivePresentationIsKnownToTheImport() async throws {
        let (model, _, _, song) = try await openedSong()
        #expect(model.livePresentationIDs.isEmpty)
        await model.goLive()
        #expect(model.livePresentationIDs == [song.id])
    }
}
