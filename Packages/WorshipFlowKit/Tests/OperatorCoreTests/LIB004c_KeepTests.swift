// LIB-004c items 5 and 7: keeping a passage (playlist item that survives relaunch, or an ordinary presentation) and what happens
// when the translation a playlist item uses is removed.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct LIB004c_KeepTests {
    @Test func aPassageAddedToThePlaylistIsThereAfterReopeningTheLibrary() async throws {
        let url = L4C.temp()
        let spec: ScriptureItemSpec
        let contents: [SlideContent]
        do {
            let r = try await L4C.rig(store: try LibraryStore.open(at: url))
            await r.scripture.show("John 3:16-18")
            await r.scripture.addToPlaylist()
            let item = try #require(r.workspace.playlistItems.last)
            guard case .scripture(let made) = item.kind else { Issue.record("not a scripture item: \(item.kind)"); return }
            spec = made
            contents = try #require(r.scripture.passage).contents
            #expect(item.title == made.label && made.primaryCode == "en-test")
            #expect(!made.label.isEmpty && made.ranges.count == 1)
            await r.workspace.flush()
        }
        let again = try await L4C.rig(install: [], store: try LibraryStore.open(at: url))
        let item = try #require(again.workspace.playlistItems.last)
        #expect(item.kind == .scripture(spec))
        // What is stored is the reference and the codes, not the words.
        let stored = try #require(item.kind.stored.payload)
        #expect(!stored.contains("quiet river") && !stored.contains("lantern"))
        await again.workspace.openPlaylistItem(item.id)
        #expect(again.workspace.openScripture?.contents == contents)
        #expect(again.workspace.show.previewDeck?.slides == contents)
        #expect(again.workspace.selectedPlaylistItemID == item.id)
    }

    @Test func aPlaylistItemShowsLiveMarkAndStepsLikeASong() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.scripture.show("Psalm 23:1-2")
        await r.scripture.addToPlaylist()
        await r.workspace.addToPlaylist(song.id)
        let ids = r.workspace.playlistItems.map(\.id)
        await r.workspace.openPlaylistItem(ids[0])
        await r.workspace.goLive(at: 1)                       // last slide of the passage
        #expect(r.workspace.liveItemID == ids[0])
        await r.workspace.next()                              // into the song after it
        #expect(r.workspace.show.liveSlide?.primary == "a1" && r.workspace.liveItemID == ids[1])
        await r.workspace.previous()                          // and back into the passage, on its last slide
        #expect(r.workspace.liveItemID == ids[0] && r.workspace.show.liveIndex == 1)
        #expect(r.workspace.show.liveDeck?.presentationID == ids[0], "the item is marked live in the playlist by its id")
    }

    @Test func removingATranslationAPlaylistItemUsesLeavesTheItemWithAPlainState() async throws {
        let r = try await L4C.rig()
        let song = try #require(await r.workspace.importLyrics(title: "A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 1))
        await r.workspace.addToPlaylist(song.id)
        await r.scripture.show("John 3:16-17")
        await r.scripture.addToPlaylist()
        let item = try #require(r.workspace.playlistItems.last)
        guard case .scripture(let spec) = item.kind else { Issue.record("not scripture"); return }
        #expect(r.scripture.availability(of: spec) == nil)

        r.scripture.requestRemoval("en-test")
        #expect(r.scripture.translations.map(\.code).contains("en-test"), "asked first: nothing is removed yet")
        #expect(r.scripture.pendingRemoval?.code == "en-test")
        await r.scripture.confirmRemoval()
        #expect(!r.scripture.translations.map(\.code).contains("en-test"))
        #expect(r.scripture.pendingRemoval == nil)

        #expect(r.workspace.playlistItems.count == 2 && r.workspace.playlistItems.last?.id == item.id)
        #expect(r.scripture.availability(of: spec)?.contains("not installed") == true)

        await r.workspace.openPlaylistItem(item.id)           // no crash, and a plain state
        let open = try #require(r.workspace.openScripture)
        #expect(open.problem?.contains("not installed") == true && open.contents.isEmpty)
        #expect(r.workspace.show.liveDeck == nil)

        // Next from the song into that item stops with a message and changes nothing.
        await r.workspace.openPlaylistItem(r.workspace.playlistItems[0].id)
        await r.workspace.goLive(at: 1)
        await r.workspace.next()
        #expect(r.workspace.show.liveSlide?.primary == "a2")
        #expect(r.workspace.lastError?.contains("not installed") == true, "\(String(describing: r.workspace.lastError))")
    }

    @Test func cancellingARemovalKeepsEverything() async throws {
        let r = try await L4C.rig()
        r.scripture.requestRemoval("vi-test")
        r.scripture.cancelRemoval()
        #expect(r.scripture.pendingRemoval == nil)
        #expect(r.scripture.translations.count == 2)
    }

    @Test func removingTheChosenTranslationMovesTheChoiceToAnInstalledOne() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("vi-test")
        r.scripture.requestRemoval("vi-test")
        await r.scripture.confirmRemoval()
        #expect(r.scripture.secondaryCode == nil && r.scripture.primaryCode == "en-test")
        r.scripture.requestRemoval("en-test")
        await r.scripture.confirmRemoval()
        #expect(r.scripture.primaryCode == nil && r.scripture.isEmpty)
    }

    @Test func saveAsPresentationMakesAnOrdinaryEditablePresentation() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1-3")
        let passage = try #require(r.scripture.passage)
        let made = try #require(await r.scripture.saveAsPresentation())
        #expect(made.kind == .scripture && made.title == passage.title)
        let slides = try await r.store.slides(of: made.id)
        #expect(slides.map(\.content) == passage.contents)
        #expect(r.workspace.presentations.contains { $0.id == made.id })
        // It is open as any song is, so it can be edited (and the scripture view gives way to it).
        #expect(r.workspace.openPresentationID == made.id && r.workspace.openScripture == nil)
        await r.workspace.updateSlide(at: 0, content: SlideContent(primary: "edited"))
        #expect(try await r.store.slides(of: made.id).first?.content.primary == "edited")
        #expect(r.scripture.passage != nil, "the passage itself is not changed by the copy")
    }

    @Test func savingWithNothingShownIsRefusedPlainly() async throws {
        let r = try await L4C.rig()
        #expect(await r.scripture.saveAsPresentation() == nil)
        #expect(r.scripture.problem?.contains("Show a passage first") == true)
        await r.scripture.addToPlaylist()
        #expect(r.workspace.playlistItems.isEmpty)
    }
}
