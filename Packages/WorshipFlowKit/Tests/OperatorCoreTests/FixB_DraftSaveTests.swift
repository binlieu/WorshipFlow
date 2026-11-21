// FIX-B R3: a failed draft write is retried with back-off, shown to the operator, and never silently discarded.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

private struct DiskFull: LocalizedError {
    var errorDescription: String? { "The disk is full." }
}

/// Counts attempts and fails the first `failures` of them, then writes to the real store.
@MainActor
private final class FlakyWriter {
    var failures: Int
    private(set) var attempts = 0
    let store: LibraryStore
    init(store: LibraryStore, failures: Int) { self.store = store; self.failures = failures }
    func write(_ slide: Slide) async throws {
        attempts += 1
        if failures > 0 { failures -= 1; throw DiskFull() }
        try await store.updateSlide(slide)
    }
}

@MainActor
@Suite struct DraftSaveRetryTests {
    fileprivate struct Fixture {
        let model: WorkspaceModel
        let store: LibraryStore
        let clock: ManualSaveClock
        let writer: FlakyWriter
        let presentation: Presentation
    }

    private func fixture(failures: Int) async throws -> Fixture {
        let store = try LibraryStore.inMemory()
        let clock = ManualSaveClock()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        let writer = FlakyWriter(store: store, failures: failures)
        model.draftWriter = { try await writer.write($0) }
        return Fixture(model: model, store: store, clock: clock, writer: writer, presentation: p)
    }

    private func storedText(_ f: Fixture, slide: Int = 0) async throws -> String {
        try await f.store.slides(of: f.presentation.id)[slide].content.primary
    }

    @Test func aFailedWriteIsRetriedWithBackOffUntilItSucceeds() async throws {
        let f = try await fixture(failures: 2)
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed"))
        await f.clock.advance(by: 2)                      // the normal save: fails
        #expect(f.writer.attempts == 1)
        #expect(f.model.draftSaveProblem != nil)
        await f.clock.advance(by: 1)
        #expect(f.writer.attempts == 1)                   // first retry is two seconds after the failure, not sooner
        await f.clock.advance(by: 1.5)
        #expect(f.writer.attempts == 2)                   // fails again
        #expect(f.model.draftSaveProblem != nil)
        await f.clock.advance(by: 3)
        #expect(f.writer.attempts == 2)                   // the wait doubled to four seconds
        await f.clock.advance(by: 1.5)
        #expect(f.writer.attempts == 3)                   // succeeds
        #expect(try await storedText(f) == "typed")
        #expect(f.model.draftSaveProblem == nil)
        #expect(!f.model.hasUnsavedDrafts)
        await f.clock.advance(by: 120)
        #expect(f.writer.attempts == 3)                   // nothing left to retry
    }

    @Test func theIndicatorNamesTheReasonAndStaysUntilTheWriteSucceeds() async throws {
        let f = try await fixture(failures: 1)
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed"))
        await f.model.flush()
        let problem = try #require(f.model.draftSaveProblem)
        #expect(problem.contains("disk is full"))
        f.model.dismissError()
        #expect(f.model.draftSaveProblem != nil)          // dismissing the error bar does not hide an unsaved-typing warning
        await f.model.flush()
        #expect(f.model.draftSaveProblem == nil)
    }

    @Test func flushWritesADraftWhoseEarlierWriteFailed() async throws {
        let f = try await fixture(failures: 1)
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed"))
        await f.model.flush()                             // fails: the saver has nothing scheduled any more
        #expect(try await storedText(f) == "one")
        await f.model.flush()                             // must still try again
        #expect(try await storedText(f) == "typed")
        #expect(!f.model.hasUnsavedDrafts)
    }

    @Test func newerTypingIsNotLostWhenAnOlderWriteSucceeds() async throws {
        let f = try await fixture(failures: 0)
        let id = f.model.slides[0].id
        f.model.editSlide(id: id, content: SlideContent(primary: "first"))
        f.model.editSlide(id: id, content: SlideContent(primary: "second"))
        await f.model.flush()
        #expect(try await storedText(f) == "second")
    }

    @Test func closingTheOpenPresentationDoesNotThrowAwayAnotherSongsUnsavedTyping() async throws {
        let f = try await fixture(failures: 100)          // nothing can be written
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed in A"))
        let other = try #require(await f.model.importLyrics(title: "B", primaryText: "b1", secondaryText: nil, maxLines: 2))
        await f.model.openPresentation(other.id)
        await f.model.deletePresentation(id: other.id)    // closes B
        #expect(f.model.hasUnsavedDrafts)                 // A's typing is still waiting
        #expect(f.model.draftSaveProblem != nil)
        f.writer.failures = 0
        await f.model.flush()
        #expect(try await storedText(f) == "typed in A")
    }

    @Test func deletingAPresentationAttemptsTheWriteFirstThenDropsItsDraftKnowingly() async throws {
        let f = try await fixture(failures: 100)
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed"))
        await f.model.deletePresentation(id: f.presentation.id)
        #expect(f.writer.attempts >= 1)                   // it tried to save before deleting
        #expect(!f.model.hasUnsavedDrafts)                // the row is gone: nothing left to retry
        #expect(f.model.draftSaveProblem == nil)
        await f.clock.advance(by: 120)
        #expect(f.writer.attempts == 1)                   // and no retry loop for a deleted song
    }

    @Test func aDraftForASlideThatNoLongerExistsIsDroppedWithAMessage() async throws {
        let f = try await fixture(failures: 0)
        let id = f.model.slides[0].id
        f.model.draftWriter = { [store = f.store] slide in try await store.updateSlide(slide) }
        f.model.editSlide(id: id, content: SlideContent(primary: "typed"))
        try await f.store.deleteSlide(id: id)             // removed behind the model's back
        await f.model.flush()
        #expect(!f.model.hasUnsavedDrafts)
        #expect(f.model.draftSaveProblem == nil)
        #expect(f.model.lastError?.contains("no longer exists") == true)
    }

    @Test func reopeningASongShowsTypingThatIsStillWaitingToBeSaved() async throws {
        let f = try await fixture(failures: 100)
        f.model.editSlide(id: f.model.slides[0].id, content: SlideContent(primary: "typed"))
        await f.model.openPresentation(f.presentation.id)
        #expect(f.model.slides[0].content.primary == "typed")
    }
}
