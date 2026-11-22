// FIX-T item 4 (M2, SLIDE): deleting a slide is by the slide's id. The position is read before anything suspends, and the confirmation dialog
// keeps the id: a reorder, an insert, a delete or a reload between the question and the answer deletes the slide that was asked about, or
// nothing (with a message), never another slide and never a trap. This is the operator's own data, so the interleavings are tested.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXT_DeleteSlideTests {
    private func ready(_ text: String = "one\n\ntwo\n\nthree\n\nfour") async throws -> WorkspaceModel {
        let model = WorkspaceModel(store: try LibraryStore.inMemory(), clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: text, secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return model
    }
    private func titles(_ m: WorkspaceModel) -> [String] { m.slides.map(\.content.primary) }

    @Test func deletingByIdRemovesThatSlide() async throws {
        let m = try await ready()
        let id = m.slides[2].id
        await m.deleteSlide(id: id)
        #expect(titles(m) == ["one", "two", "four"])
        #expect(m.lastError == nil)
    }

    @Test func aReorderWhileTheDialogIsOpenStillDeletesTheSlideThatWasAskedAbout() async throws {
        let m = try await ready()
        let asked = m.slides[1].id                               // "two": the dialog was opened on it
        await m.moveSlide(from: 3, to: 0)                        // an edit while the dialog is open: "two" is now at position 2
        #expect(m.slides[1].content.primary == "one", "position 1 now holds another slide")
        await m.deleteSlide(id: asked)
        #expect(titles(m) == ["four", "one", "three"], "\"two\" went, not whatever sits at position 1 now")
    }

    @Test func aSlideThatIsAlreadyGoneIsANoOpWithAMessage() async throws {
        let m = try await ready()
        let asked = m.slides[1].id
        await m.deleteSlide(id: asked)                           // deleted elsewhere while the dialog was open
        let before = titles(m)
        await m.deleteSlide(id: asked)
        #expect(titles(m) == before, "nothing else was deleted")
        #expect(m.lastError?.contains("no longer") == true, Comment(rawValue: m.lastError ?? "nil"))
    }

    @Test func aSlideOfAnotherPresentationIsNotDeletedFromTheOpenOne() async throws {
        let m = try await ready()
        let asked = m.slides[0].id
        let other = try #require(await m.importLyrics(title: "Other", primaryText: "x1\n\nx2", secondaryText: nil, maxLines: 1))
        await m.openPresentation(other.id)                       // another song was opened while the dialog was open
        await m.deleteSlide(id: asked)
        #expect(titles(m) == ["x1", "x2"])
        #expect(m.lastError?.contains("no longer") == true)
    }

    @Test func twoDeletesByPositionRunningTogetherDoNotTrapAndEachRemovesTheSlideItNamed() async throws {
        let m = try await ready()
        // Both positions are turned into ids before either suspends. By position alone, the second would read a list that has shrunk.
        let last = Task { await m.deleteSlide(at: 3) }
        let first = Task { await m.deleteSlide(at: 0) }
        await last.value
        await first.value
        #expect(titles(m) == ["two", "three"])
    }

    @Test func aPositionThatIsOutOfRangeIsIgnored() async throws {
        let m = try await ready()
        await m.deleteSlide(at: 9)
        await m.deleteSlide(at: -1)
        #expect(titles(m).count == 4)
    }
}
