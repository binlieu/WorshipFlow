// FIX-T item 3 (M1, UI-002 / LIB-004c): Next onto a Bible passage reads the passage (an await). The playlist may change during that read.
// The step finds its target again by item id afterwards, so it never indexes a list that has shrunk or moved. The scripture read is
// held and released through `readGate`; no wall-clock time. Written before the fix; invented text only.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXT_StepAcrossAwaitTests {
    /// [song A, passage, song B, song C]; A is open and live on its last slide. The scripture read is armed to park.
    private func setup() async throws -> (L4C.Rig, FIXF_Hold, [UUID]) {
        let r = try await L4C.rig()
        let hold = FIXF_Hold()
        r.scripture.readGate = { await hold.gate() }
        let a = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        let b = try #require(await r.workspace.importLyrics(title: "B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 1))
        let c = try #require(await r.workspace.importLyrics(title: "C", primaryText: "c1\n\nc2", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(a.id)
        await r.scripture.show("John 3:16-17")
        await r.scripture.addToPlaylist()
        await r.workspace.addToPlaylist(b.id)
        await r.workspace.addToPlaylist(c.id)
        let ids = r.workspace.playlistItems.map(\.id)
        await r.workspace.openPlaylistItem(ids[0])
        await r.workspace.goLive(at: 1)
        hold.arm()
        return (r, hold, ids)
    }

    @Test func aPlaylistThatShrinksWhileThePassageIsReadingDoesNotTrapTheStep() async throws {
        let (r, hold, ids) = try await setup()
        let step = Task { await r.workspace.next() }
        await hold.waitUntilParked()
        await r.workspace.removePlaylistItem(id: ids[3])
        await r.workspace.removePlaylistItem(id: ids[2])
        await r.workspace.removePlaylistItem(id: ids[1])         // the passage too: its old index is now past the end of the list
        hold.release()
        await step.value
        #expect(r.workspace.playlistItems.count == 1)
        #expect(r.workspace.liveItemID == ids[0])
    }

    @Test func aPassageThatIsRemovedWhileItIsReadingIsNeverShownAsAnotherItem() async throws {
        let (r, hold, ids) = try await setup()
        let step = Task { await r.workspace.next() }
        await hold.waitUntilParked()
        await r.workspace.removePlaylistItem(id: ids[1])         // the passage itself; B slides into its place
        hold.release()
        await step.value
        #expect(r.workspace.openScripture?.itemID != ids[2], "song B must not be taken for the passage")
        #expect(r.workspace.liveItemID == ids[0], "the step stopped: the item it was going to is gone")
        #expect(r.workspace.lastError?.contains("changed") == true, Comment(rawValue: r.workspace.lastError ?? "nil"))
    }

    @Test func aPlaylistThatGainsAnItemBeforeThePassageStillStepsOntoThePassage() async throws {
        let (r, hold, ids) = try await setup()
        let step = Task { await r.workspace.next() }
        await hold.waitUntilParked()
        let extra = try #require(await r.workspace.importLyrics(title: "X", primaryText: "x1", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(extra.id)                 // appended: the passage keeps its place
        hold.release()
        await step.value
        #expect(r.workspace.liveItemID == ids[1], "the passage went live")
        #expect(r.workspace.openScripture?.itemID == ids[1])
    }

    @Test func anUnchangedPlaylistStepsOntoThePassageAsBefore() async throws {
        let (r, hold, ids) = try await setup()
        let step = Task { await r.workspace.next() }
        await hold.waitUntilParked()
        hold.release()
        await step.value
        #expect(r.workspace.liveItemID == ids[1])
        #expect(r.workspace.lastError == nil)
    }
}
