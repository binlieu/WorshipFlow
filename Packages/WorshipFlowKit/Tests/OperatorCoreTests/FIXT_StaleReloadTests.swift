// FIX-T item 3 (M1 audit): a reload that read "which presentation / which playlist is open" before it suspended must not write its result
// into the screen after another one was opened or selected during the read. The result of the older read is dropped. Written before the fix.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXT_StaleReloadTests {
    private func ready() async throws -> (WorkspaceModel, Presentation, Presentation) {
        let m = WorkspaceModel(store: try LibraryStore.inMemory(), clock: ManualSaveClock())
        await m.load()
        let a = try #require(await m.importLyrics(title: "A", primaryText: "a1\n\na2\n\na3", secondaryText: nil, maxLines: 1))
        let b = try #require(await m.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        await m.openPresentation(a.id)
        return (m, a, b)
    }

    @Test func aReloadOfTheOpenSongThatFinishesAfterAnotherSongWasOpenedDoesNotPutTheOldSlidesBack() async throws {
        let (m, _, b) = try await ready()
        let older = Task { await m.reloadOpen() }
        await m.openPresentation(b.id)
        await older.value
        #expect(m.openPresentationID == b.id)
        #expect(m.slides.map(\.content.primary) == ["b1", "b2"])
        #expect(m.show.previewDeck?.slides.map(\.primary) == ["b1", "b2"])
    }

    @Test func aPlaylistReloadThatFinishesAfterAnotherPlaylistWasSelectedDoesNotShowTheOldItems() async throws {
        let (m, a, _) = try await ready()
        await m.createPlaylist(name: "First")
        let first = try #require(m.selectedPlaylistID)
        await m.addToPlaylist(a.id)
        await m.createPlaylist(name: "Second")
        let second = try #require(m.selectedPlaylistID)
        #expect(second != first && m.playlistItems.isEmpty)
        await m.selectPlaylist(first)
        let older = Task { await m.reloadPlaylistItems() }       // reads "First"
        await m.selectPlaylist(second)
        await older.value
        #expect(m.selectedPlaylistID == second)
        #expect(m.playlistItems.isEmpty, "the items shown are the selected playlist's")
    }
}
