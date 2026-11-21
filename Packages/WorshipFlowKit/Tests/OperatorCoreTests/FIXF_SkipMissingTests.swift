// FIX-F item 8 (LIB-004c): a scripture item whose translation is missing stops Next the first time (with the message); a second Next
// on the same item in the same stay skips to the next playable item and says so. Next, the keyboard, MIDI and the remote all end in
// `WorkspaceModel.next()` (`CueModel` calls it through its transport port). Written before the fix; invented text only.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_SkipMissingTests {
    /// [song A, passage (translation removed), song B]; A is open and on its last slide, live.
    private func setup() async throws -> (L4C.Rig, [UUID]) {
        let r = try await L4C.rig()
        let a = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await r.workspace.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(a.id)
        await r.scripture.show("John 3:16-17")
        await r.scripture.addToPlaylist()
        await r.workspace.addToPlaylist(b.id)
        let ids = r.workspace.playlistItems.map(\.id)
        r.scripture.requestRemoval("en-test")
        await r.scripture.confirmRemoval()
        await r.workspace.openPlaylistItem(ids[0])
        await r.workspace.goLive(at: 1)
        return (r, ids)
    }

    @Test func theFirstNextStopsAtTheMissingItemWithTheMessage() async throws {
        let (r, ids) = try await setup()
        await r.workspace.next()
        #expect(r.workspace.liveItemID == ids[0], "still on the song: Next stopped")
        #expect(r.workspace.lastError?.contains("Next stopped") == true && r.workspace.lastError?.contains("not installed") == true,
                Comment(rawValue: r.workspace.lastError ?? "nil"))
    }

    @Test func aSecondNextOnTheSameItemInTheSameStaySkipsToTheNextPlayableItemAndSaysSo() async throws {
        let (r, ids) = try await setup()
        await r.workspace.next()
        r.workspace.dismissError()
        await r.workspace.next()
        #expect(r.workspace.liveItemID == ids[2], "skipped the passage")
        #expect(r.workspace.show.liveSlide?.primary == "b1")
        let said = try #require(r.workspace.lastError, "the skip is said")
        #expect(said.contains("skipped") && said.contains("John"), Comment(rawValue: said))
    }

    @Test func aNewStayStopsAgain() async throws {
        let (r, ids) = try await setup()
        await r.workspace.next()                                // stops
        await r.workspace.goLive(at: 0)                         // the operator did something else: a new stay
        await r.workspace.goLive(at: 1)
        r.workspace.dismissError()
        await r.workspace.next()
        #expect(r.workspace.liveItemID == ids[0], "stopped again, not skipped")
        #expect(r.workspace.lastError?.contains("Next stopped") == true)
    }

    @Test func previousStopsAndSkipsTheSameWay() async throws {
        let (r, ids) = try await setup()
        await r.workspace.openPlaylistItem(ids[2])
        await r.workspace.goLive(at: 0)
        await r.workspace.previous()
        #expect(r.workspace.liveItemID == ids[2], "first Previous stops at the passage")
        await r.workspace.previous()
        #expect(r.workspace.liveItemID == ids[0], "second Previous skips to the song before it")
        #expect(r.workspace.lastError?.contains("skipped") == true)
    }

    @Test func aSkipTriedAtTheEndOfThePlaylistStaysPut() async throws {
        let (r, ids) = try await setup()
        await r.workspace.removePlaylistItem(id: ids[2])         // the passage is now the last item
        await r.workspace.openPlaylistItem(ids[0])
        await r.workspace.goLive(at: 1)
        await r.workspace.next()
        await r.workspace.next()
        #expect(r.workspace.liveItemID == ids[0], "nothing playable after it: live stays")
        #expect(r.workspace.lastError != nil)
    }

    @Test func aSuccessfulStepClearsTheStop() async throws {
        let (r, ids) = try await setup()
        await r.workspace.next()                                // stop
        await r.workspace.previous()                            // slide 1 -> slide 0 of A (not a step into the passage)
        await r.workspace.next()                                // back to slide 1
        r.workspace.dismissError()
        await r.workspace.next()                                // a first Next at the passage again: stops, not skips
        #expect(r.workspace.liveItemID == ids[0])
        #expect(r.workspace.lastError?.contains("Next stopped") == true)
    }
}
