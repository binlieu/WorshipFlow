// FIX-P item 6 (review of FIX-M, L4 and L5): a failed drop restores the order of the list it was made in, also when the operator opened another
// presentation while an earlier drop was still being written; and typed text that has not been saved yet is not lost to a reload that a drop causes.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXP_ReorderScopeTests {
    @MainActor final class Gate {
        var waiting: [CheckedContinuation<Void, Never>] = []
        var isOpen = false
        func hold() async { if isOpen { return }; await withCheckedContinuation { waiting.append($0) } }
        func release() { isOpen = true; let w = waiting; waiting = []; w.forEach { $0.resume() } }
    }
    struct Boom: Error {}
    func spin() async { for _ in 0..<20 { await Task.yield() } }

    func twoSongs() async throws -> (WorkspaceModel, LibraryStore, UUID, UUID) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let a = try #require(await model.importLyrics(title: "A", primaryText: (1...6).map { "A\($0)" }.joined(separator: "\n\n"), secondaryText: nil, maxLines: 1))
        let b = try #require(await model.importLyrics(title: "B", primaryText: (1...6).map { "B\($0)" }.joined(separator: "\n\n"), secondaryText: nil, maxLines: 1))
        return (model, store, a.id, b.id)
    }

    @Test func aFailedDropInAnotherPresentationRestoresThatPresentationsOrder() async throws {
        let (model, _, a, b) = try await twoSongs()
        let gate = Gate()
        var calls = 0
        model.slideMoveWriter = { _, _ in calls += 1; if calls == 1 { await gate.hold() } else { throw Boom() } }
        await model.openPresentation(a)
        let dropA = Task { await model.moveSlide(from: 4, to: 0) }
        await spin()
        await model.openPresentation(b)
        let original = model.slides.map(\.content.primary)
        #expect(original == (1...6).map { "B\($0)" })
        let dropB = Task { await model.moveSlide(from: 5, to: 0) }
        await spin()
        #expect(model.slides.map(\.content.primary) != original)
        gate.release()
        await dropA.value; await dropB.value
        #expect(model.slides.map(\.content.primary) == original, "the failed drop in B puts B's own order back")
        #expect(model.lastError?.hasPrefix("Could not move the slide") == true)
    }

    @Test func aFailedPlaylistDropInAnotherPlaylistRestoresThatPlaylistsOrder() async throws {
        let (model, _, a, b) = try await twoSongs()
        let c = try #require(await model.importLyrics(title: "C", primaryText: "x", secondaryText: nil, maxLines: 1))
        let d = try #require(await model.importLyrics(title: "D", primaryText: "x", secondaryText: nil, maxLines: 1))
        await model.createPlaylist(name: "First")
        let first = try #require(model.selectedPlaylistID)
        await model.addToPlaylist(a); await model.addToPlaylist(b); await model.addToPlaylist(c.id)
        let firstOrder = model.playlistItems.map(\.id)
        await model.createPlaylist(name: "Second")
        let second = try #require(model.selectedPlaylistID)
        #expect(second != first)
        await model.addToPlaylist(a); await model.addToPlaylist(b); await model.addToPlaylist(d.id)
        let secondOrder = model.playlistItems.map(\.id)
        await model.selectPlaylist(first)
        let gate = Gate()
        var calls = 0
        model.playlistMoveWriter = { _, _ in calls += 1; if calls == 1 { await gate.hold() } else { throw Boom() } }
        let dropFirst = Task { await model.movePlaylistItem(id: firstOrder[0], to: 2) }
        await spin()
        await model.selectPlaylist(second)
        #expect(model.playlistItems.map(\.id) == secondOrder)
        let dropSecond = Task { await model.movePlaylistItem(id: secondOrder[2], to: 0) }
        await spin()
        #expect(model.playlistItems.map(\.id) != secondOrder)
        gate.release()
        await dropFirst.value; await dropSecond.value
        #expect(model.playlistItems.map(\.id) == secondOrder, "the failed drop in the second playlist puts its own order back")
        #expect(model.lastError?.hasPrefix("Could not move the item") == true)
    }

    @Test func typedTextWaitingToBeSavedSurvivesTheReloadAfterADrop() async throws {
        let (model, _, a, _) = try await twoSongs()
        await model.openPresentation(a)
        var content = model.slides[1].content
        content.primary = "typed, not yet saved"
        model.editSlide(id: model.slides[1].id, content: content)         // a draft the manual clock never writes
        #expect(model.hasUnsavedDrafts)
        await model.moveSlide(from: 5, to: 0)
        await model.setPreviewArrangement(nil)                              // any reload of the open presentation
        #expect(model.slides.contains { $0.content.primary == "typed, not yet saved" })
        #expect(!model.slides.contains { $0.content.primary == "A2" }, "the old text of that slide is not shown")
    }
}
