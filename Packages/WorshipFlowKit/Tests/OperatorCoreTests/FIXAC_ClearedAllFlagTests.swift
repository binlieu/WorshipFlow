// FIX-AC item A (KI-286): the workspace remembers that Clear all (not Clear words) is what hides the show, so a video object's sound can follow it.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXAC_ClearedAllFlagTests {
    private func liveWorkspace() async throws -> WorkspaceModel {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        return workspace
    }

    @Test func clearAllSetsTheFlagAndClearWordsDoesNot() async throws {
        let w = try await liveWorkspace()
        #expect(!w.isClearedAll)
        w.clear()
        #expect(w.show.isCleared && !w.isClearedAll)
        w.apply(.trigger(index: 0))                                         // a slide goes live: Clear ends
        #expect(!w.show.isCleared && !w.isClearedAll)
        w.clearAll()
        #expect(w.show.isCleared && w.isClearedAll)
    }

    @Test func theFlagIsSeenByTheShowChangeHandlerOfTheSameCommand() async throws {
        let w = try await liveWorkspace()
        var seen: [Bool] = []
        w.onShowChange = { _ in seen.append(w.isClearedAll) }
        w.clearAll()
        #expect(seen == [true])
    }

    @Test func theFlagStaysWhileClearedAndEndsWhenTheShowIsNoLongerCleared() async throws {
        let w = try await liveWorkspace()
        w.clearAll()
        w.clear()                                                           // Clear words over Clear all: still silent
        #expect(w.isClearedAll)
        w.apply(.liftHolds)
        #expect(!w.isClearedAll)
        w.clearAll()
        w.apply(.stop)
        #expect(!w.isClearedAll)
        w.apply(.trigger(index: 0))
        #expect(!w.isClearedAll)
    }
}
