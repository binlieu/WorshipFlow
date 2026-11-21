// FIX-F item 3 (LIB-004c): a shown passage follows the library. A translation that was removed or replaced is not shown from
// stale text; the live deck is never changed by it. Written before the fix; invented text only.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_RemovedTranslationTests {
    private func replacement() -> TranslationFile {
        var file = L4C.english()
        file.setVerse("Replacement words for sixteen, invented for the test.", book: BookID("JHN"), chapter: 3, verse: 16)
        return file
    }

    @Test func removingThePrimaryTranslationOfTheShownPassageShowsTheNotInstalledState() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-17")
        #expect(r.scripture.passage?.spec.primaryCode == "en-test")
        let items = r.workspace.playlistItems.count
        r.scripture.requestRemoval("en-test")
        await r.scripture.confirmRemoval()
        #expect(r.scripture.passage == nil, "the old words are not kept on screen")
        #expect(r.scripture.problem?.contains("not installed") == true, Comment(rawValue: r.scripture.problem ?? "nil"))
        #expect(r.scripture.problem?.contains("en-test") == true)
        #expect(r.workspace.show.previewDeck?.slides.isEmpty ?? true)
        await r.scripture.addToPlaylist()
        #expect(r.workspace.playlistItems.count == items, "the missing code is not stored")
        #expect(!r.workspace.playlistItems.contains { $0.kind.stored.payload?.contains("en-test") == true })
    }

    @Test func removingTheSecondTranslationDropsItWithANotice() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("vi-test")
        await r.scripture.show("John 3:16-17")
        #expect(r.scripture.passage?.spec.secondaryCode == "vi-test")
        r.scripture.requestRemoval("vi-test")
        await r.scripture.confirmRemoval()
        let passage = try #require(r.scripture.passage, "the first translation is still there")
        #expect(passage.spec.primaryCode == "en-test" && passage.spec.secondaryCode == nil)
        #expect(passage.contents.allSatisfy { $0.secondary == nil })
        #expect(passage.messages.contains { $0.contains("vi-test") && $0.contains("no longer installed") }, Comment(rawValue: "\(passage.messages)"))
    }

    @Test func replacingATranslationShowsTheNewTextOfTheShownPassage() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16")
        #expect(r.scripture.passage?.contents.first?.primary.contains("quiet river") == true)
        await r.scripture.runImport(replacement(), replace: false)
        #expect(r.scripture.importState == .needsReplace(code: "en-test", name: "English test text"))
        await r.scripture.confirmReplace()
        let passage = try #require(r.scripture.passage)
        #expect(passage.contents.first?.primary.contains("Replacement words") == true, Comment(rawValue: passage.contents.first?.primary ?? ""))
        #expect(passage.contents.first?.primary.contains("quiet river") == false)
        #expect(r.workspace.show.previewDeck?.slides.first?.primary.contains("Replacement words") == true)
    }

    @Test func aTranslationTheShownPassageDoesNotUseLeavesItAlone() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16")
        let before = try #require(r.scripture.passage)
        r.scripture.requestRemoval("vi-test")
        await r.scripture.confirmRemoval()
        #expect(r.scripture.passage == before)
    }

    @Test func theLiveDeckIsNeverChangedByRemovingOrReplacing() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-17")
        await r.workspace.goLive()
        let live = try #require(r.workspace.show.liveDeck)
        let index = r.workspace.show.liveIndex
        await r.scripture.runImport(replacement(), replace: false)
        await r.scripture.confirmReplace()
        #expect(r.workspace.show.liveDeck == live && r.workspace.show.liveIndex == index, "replace: live text is as it was")
        r.scripture.requestRemoval("en-test")
        await r.scripture.confirmRemoval()
        #expect(r.workspace.show.liveDeck == live && r.workspace.show.liveIndex == index, "remove: live text is as it was")
        #expect(r.workspace.show.liveSlide?.primary.contains("quiet river") == true)
    }

    @Test func aPassageOpenedFromAPlaylistItemShowsTheStateOnTheItemWhenItsTranslationIsRemoved() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-17")
        await r.scripture.addToPlaylist()
        let id = try #require(r.workspace.playlistItems.last).id
        await r.workspace.openPlaylistItem(id)
        await r.workspace.goLive()
        let live = try #require(r.workspace.show.liveDeck)
        r.scripture.requestRemoval("en-test")
        await r.scripture.confirmRemoval()
        let open = try #require(r.workspace.openScripture)
        #expect(open.itemID == id && open.contents.isEmpty && open.problem?.contains("not installed") == true)
        #expect(r.workspace.selectedPlaylistItemID == id)
        #expect(r.workspace.show.liveDeck == live)
    }
}
