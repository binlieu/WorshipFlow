// FIX-F item 2 (LIB-004c): changing a translation or the verses per slide refreshes the shown passage from its own reference. It
// keeps its playlist item and leaves text the operator typed but did not submit alone. Written before the fix; invented text only.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_RefreshTests {
    @Test func changingTheSecondTranslationKeepsThePlaylistItemAndNextStillAdvances() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.scripture.show("John 3:16-18")
        await r.scripture.addToPlaylist()
        await r.workspace.addToPlaylist(song.id)
        let ids = r.workspace.playlistItems.map(\.id)           // [passage, song]
        await r.workspace.openPlaylistItem(ids[0])
        #expect(r.workspace.openPlaylistItemID == ids[0])

        await r.scripture.setSecondary("vi-test")
        #expect(r.scripture.secondaryCode == "vi-test")
        #expect(r.workspace.openPlaylistItemID == ids[0], "the passage is still the playlist item's")
        #expect(r.workspace.selectedPlaylistItemID == ids[0])
        #expect(r.workspace.openScripture?.itemID == ids[0] && r.workspace.openScripture?.deckID == ids[0])
        #expect(r.scripture.passage?.spec.secondaryCode == "vi-test", "the second translation is now shown")

        await r.workspace.goLive()
        #expect(r.workspace.liveItemID == ids[0])
        let count = try #require(r.workspace.show.liveDeck?.slides.count)
        await r.workspace.goLive(at: count - 1)
        await r.workspace.next()                                 // past the last slide: the song
        #expect(r.workspace.liveItemID == ids[1])
        #expect(r.workspace.show.liveSlide?.primary == "a1")
    }

    @Test func changingTheVersesPerSlideKeepsThePlaylistItem() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-18")
        await r.scripture.addToPlaylist()
        let id = try #require(r.workspace.playlistItems.last).id
        await r.workspace.openPlaylistItem(id)
        await r.scripture.setVersesPerSlide(2)
        #expect(r.workspace.openPlaylistItemID == id && r.workspace.selectedPlaylistItemID == id)
        #expect(r.workspace.openScripture?.deckID == id)
    }

    @Test func textTypedButNotSubmittedIsNotShownByARefreshAndStaysInTheField() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16")
        let before = try #require(r.scripture.passage)
        r.scripture.referenceText = "Psalm 23"                  // typed, Return not pressed
        await r.scripture.setVersesPerSlide(2)
        #expect(r.scripture.referenceText == "Psalm 23", "the operator's typing is left alone")
        let after = try #require(r.scripture.passage)
        #expect(after.spec.ranges == before.spec.ranges, "still John 3:16, not Psalm 23")
        #expect(after.contents.contains { $0.primary.contains("Verse 16") })
        #expect(!after.contents.contains { $0.primary.contains("lamp is lit") })
    }

    @Test func aTypedPassageKeepsItsIdentityThroughARefresh() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-17")
        let before = try #require(r.scripture.passage)
        await r.scripture.setSecondary("vi-test")
        let after = try #require(r.scripture.passage)
        #expect(after.id == before.id)
        #expect(r.workspace.openScripture?.deckID == before.id)
    }
}
