// OUT-004: extra cases for the workspace model beyond the coordinator's tests.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct WorkspaceModelExtraTests {
    func ready(clock: any SaveClock = RealSaveClock()) async throws -> (WorkspaceModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        return (model, store)
    }

    @Test func typedTextIsSavedWithinTwoSecondsButShownAtOnce() async throws {
        let clock = ManualSaveClock()
        let (model, store) = try await ready(clock: clock)
        let p = try #require(await model.importLyrics(title: "S", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        let id = model.slides[0].id
        model.editSlide(id: id, content: SlideContent(primary: "ONE"))
        #expect(model.show.previewDeck?.slides[0].primary == "ONE")
        #expect(try await store.slides(of: p.id)[0].content.primary == "one")       // not written yet
        await clock.advance(by: 1.9)
        #expect(try await store.slides(of: p.id)[0].content.primary == "one")
        await clock.advance(by: 0.2)
        #expect(try await store.slides(of: p.id)[0].content.primary == "ONE")
    }

    @Test func flushWritesPendingTypingAtOnce() async throws {
        let (model, store) = try await ready(clock: ManualSaveClock())
        let p = try #require(await model.importLyrics(title: "S", primaryText: "one", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "uno"), notes: "slow")
        await model.flush()
        let saved = try await store.slides(of: p.id)[0]
        #expect(saved.content.primary == "uno" && saved.notes == "slow")
    }

    @Test func switchingSongsSavesTheOldSongFirst() async throws {
        let (model, store) = try await ready(clock: ManualSaveClock())
        let a = try #require(await model.importLyrics(title: "A", primaryText: "a", secondaryText: nil, maxLines: 1))
        let b = try #require(await model.importLyrics(title: "B", primaryText: "b", secondaryText: nil, maxLines: 1))
        await model.openPresentation(a.id)
        model.editSlide(id: model.slides[0].id, content: SlideContent(primary: "a!"))
        await model.openPresentation(b.id)
        #expect(try await store.slides(of: a.id)[0].content.primary == "a!")
        #expect(model.slides.map(\.content.primary) == ["b"])
    }

    @Test func importWithNoTextCreatesNothing() async throws {
        let (model, _) = try await ready()
        let p = await model.importLyrics(title: "Empty", primaryText: "  \n ", secondaryText: nil, maxLines: 2)
        #expect(p == nil && model.presentations.isEmpty && model.lastError != nil)
    }

    @Test func importWithBlankTitleLeavesNothingBehind() async throws {
        let (model, _) = try await ready()
        let p = await model.importLyrics(title: " ", primaryText: "words", secondaryText: nil, maxLines: 2)
        #expect(p == nil && model.presentations.isEmpty && model.lastError != nil)
    }

    @Test func reflowReplacesSlidesAndKeepsLiveOnScreen() async throws {
        let (model, _) = try await ready()
        let p = try #require(await model.importLyrics(title: "S", primaryText: "l1\nl2\nl3\nl4", secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        await model.goLive()
        let ok = await model.reflowPresentation(id: p.id, primaryText: "l1\nl2\nl3\nl4", secondaryText: nil, maxLines: 4)
        #expect(ok && model.slides.count == 1)
        #expect(model.show.liveSlide?.primary == "l1\nl2")
        let text = await model.lyricsText(of: p.id)
        #expect(text.primary == "l1\nl2\nl3\nl4")
    }

    @Test func theLastLibraryCannotBeDeleted() async throws {
        let (model, _) = try await ready()
        await model.deleteLibrary(id: model.libraries[0].id)
        #expect(model.libraries.count == 1 && model.lastError != nil)
    }

    @Test func searchHitInAnotherLibrarySwitchesToIt() async throws {
        let (model, _) = try await ready()
        await model.createLibrary(name: "Other")
        let p = try #require(await model.importLyrics(title: "Hidden Song", primaryText: "words here", secondaryText: nil, maxLines: 2))
        await model.selectLibrary(model.libraries[0].id)
        #expect(model.presentations.isEmpty)
        await model.search("hidden")
        await model.openSearchResult(try #require(model.searchResults.first))
        #expect(model.openPresentationID == p.id && model.selectedLibraryID == model.libraries[1].id)
    }

    @Test func structuralEditsAreRefusedWhileACustomOrderPlays() async throws {
        let (model, store) = try await ready()
        let p = try #require(await model.importLyrics(title: "S", primaryText: "Verse 1\nv\n\nChorus\nc", secondaryText: nil, maxLines: 1))
        let groups = try await store.groups(of: p.id)
        let arr = try #require(await {
            await model.addToPlaylist(p.id)
            await model.openPresentation(p.id)
            return await model.createArrangement(name: "x", groupIDs: [groups[1].id])
        }())
        let item = try #require(model.playlistItems.first)
        await model.setArrangement(arr.id, forPlaylistItem: item.id)
        await model.openPlaylistItem(item.id)
        await model.deleteSlide(at: 0)
        #expect(model.lastError != nil)
        #expect(try await store.slides(of: p.id).count == 2)
    }

    @Test func quickEditWithNothingLiveExplainsItself() async throws {
        let (model, _) = try await ready()
        await model.quickEditLiveSlide(SlideContent(primary: "x"))
        #expect(model.lastError != nil && model.show.isStopped)
    }

    @Test func showChangesAreAnnounced() async throws {
        let (model, _) = try await ready()
        var seen: [Bool] = []
        model.onShowChange = { seen.append($0.isStopped) }
        let p = try #require(await model.importLyrics(title: "S", primaryText: "a", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        await model.goLive()
        model.stop()
        #expect(seen == [true, false, true])
    }
}
