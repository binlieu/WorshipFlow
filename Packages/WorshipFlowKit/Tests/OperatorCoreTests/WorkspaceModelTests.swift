// OUT-004 / LIB-001 / LIB-002 / LIB-003 / SLIDE-005 acceptance tests: operator workspace logic
// (PRES-02, PRES-03, PRES-07, PRES-08, LIVE-06, LIVE-07, NFR-06, NFR-07). Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct WorkspaceModelTests {
    let grace = "Verse 1\nAmazing grace, how sweet the sound\nThat saved a wretch like me\n\nChorus\nMy chains are gone\nI've been set free"
    let graceVi = "Câu 1\nÂn điển lạ lùng thay\nĐã cứu vớt tôi\n\nĐiệp khúc\nXiềng xích đã tan\nTôi được tự do"

    func ready() async throws -> (WorkspaceModel, LibraryStore) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        return (model, store)
    }

    // MARK: First run and libraries (PRES-02)

    @Test func firstRunCreatesOneLibraryAndOnePlaylist() async throws {
        let (model, store) = try await ready()
        #expect(model.libraries.map(\.name) == ["Songs"])
        #expect(model.selectedLibraryID == model.libraries.first?.id)
        #expect(model.playlists.count == 1)
        #expect(model.show.isStopped && model.lastError == nil)
        let again = WorkspaceModel(store: store)            // a second launch does not seed again
        await again.load()
        #expect(again.libraries.count == 1 && again.playlists.count == 1)
    }

    @Test func libraryCreateRenameDeleteAndSelection() async throws {
        let (model, _) = try await ready()
        await model.createLibrary(name: "Sermons")
        #expect(model.libraries.map(\.name) == ["Songs", "Sermons"])
        let sermons = try #require(model.libraries.last)
        await model.selectLibrary(sermons.id)
        await model.renameLibrary(id: sermons.id, to: "Messages")
        #expect(model.libraries.map(\.name) == ["Songs", "Messages"])
        await model.deleteLibrary(id: sermons.id)
        #expect(model.libraries.map(\.name) == ["Songs"])
        #expect(model.selectedLibraryID == model.libraries.first?.id)     // selection falls back, never dangles
    }

    /// Errors are shown to the operator, never thrown at the interface and never fatal.
    @Test func invalidInputSetsLastError() async throws {
        let (model, _) = try await ready()
        await model.createLibrary(name: "   ")
        #expect(model.lastError != nil)
        #expect(model.libraries.count == 1)
        model.dismissError()
        #expect(model.lastError == nil)
    }

    // MARK: Import and open (PRES-05, PRES-10, LIVE-07)

    @Test func importLyricsCreatesAPresentationWithPairedSlides() async throws {
        let (model, store) = try await ready()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: grace, secondaryText: graceVi, maxLines: 2))
        #expect(model.presentations.map(\.title) == ["Amazing Grace"])
        let slides = try await store.slides(of: p.id)
        #expect(slides.count == 2)
        #expect(slides[0].content.secondary == "Ân điển lạ lùng thay\nĐã cứu vớt tôi")
        #expect(try await store.groups(of: p.id).map(\.name) == ["Verse 1", "Chorus"])
    }

    @Test func openingAPresentationFillsPreviewOnly() async throws {
        let (model, _) = try await ready()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: grace, secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        #expect(model.openPresentationID == p.id)
        #expect(model.slides.count == 2)
        #expect(model.show.previewDeck?.slides.count == 2)
        #expect(model.show.isStopped && model.show.liveSlide == nil)
    }

    @Test func goLiveNextClearStop() async throws {
        let (model, _) = try await ready()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: grace, secondaryText: nil, maxLines: 2))
        await model.openPresentation(p.id)
        model.selectSlide(1)
        #expect(model.show.liveSlide == nil)                       // selecting is preview only
        await model.goLive()
        #expect(model.show.liveSlide?.primary == "My chains are gone\nI've been set free")
        await model.previous()
        #expect(model.show.liveIndex == 0)
        model.clear()
        #expect(model.show.isCleared)
        model.stop()
        #expect(model.show.isStopped)
    }

    // MARK: Playlists (PRES-03)

    func twoSongPlaylist(_ model: WorkspaceModel) async throws -> (UUID, UUID) {
        let a = try #require(await model.importLyrics(title: "Song A", primaryText: "a1\n\na2", secondaryText: nil, maxLines: 2))
        let b = try #require(await model.importLyrics(title: "Song B", primaryText: "b1\n\nb2", secondaryText: nil, maxLines: 2))
        await model.addToPlaylist(a.id)
        await model.addToPlaylist(b.id)
        return (a.id, b.id)
    }

    @Test func playlistAddReorderRemove() async throws {
        let (model, _) = try await ready()
        _ = try await twoSongPlaylist(model)
        #expect(model.playlistItems.map(\.title) == ["Song A", "Song B"])
        await model.movePlaylistItem(id: model.playlistItems[1].id, to: 0)
        #expect(model.playlistItems.map(\.title) == ["Song B", "Song A"])
        await model.removePlaylistItem(id: model.playlistItems[0].id)
        #expect(model.playlistItems.map(\.title) == ["Song A"])
    }

    /// PRES-03: Next walks through the whole playlist; Previous walks back.
    @Test func nextStepsAcrossPlaylistItems() async throws {
        let (model, _) = try await ready()
        _ = try await twoSongPlaylist(model)
        await model.openPlaylistItem(model.playlistItems[0].id)
        await model.goLive()
        var seen = [model.show.liveSlide?.primary]
        for _ in 0..<4 { await model.next(); seen.append(model.show.liveSlide?.primary) }
        #expect(seen == ["a1", "a2", "b1", "b2", "b2"])            // stops at the very end
        #expect(model.selectedPlaylistItemID == model.playlistItems[1].id)
        await model.previous(); await model.previous()
        #expect(model.show.liveSlide?.primary == "a2")             // back into the previous item, at its last slide
        #expect(model.selectedPlaylistItemID == model.playlistItems[0].id)
    }

    /// Outside a playlist, Next stops at the end of the presentation.
    @Test func nextStopsAtEndWhenNotInAPlaylist() async throws {
        let (model, _) = try await ready()
        let (a, _) = try await twoSongPlaylist(model)
        await model.openPresentation(a)
        await model.goLive()
        await model.next(); await model.next(); await model.next()
        #expect(model.show.liveSlide?.primary == "a2")
    }

    @Test func playlistItemUsesItsArrangement() async throws {
        let (model, store) = try await ready()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: grace, secondaryText: nil, maxLines: 2))
        let groups = try await store.groups(of: p.id)
        let arr = try await store.createArrangement(for: p.id, name: "Chorus first", groupIDs: [groups[1].id, groups[0].id, groups[1].id])
        await model.addToPlaylist(p.id)
        let item = try #require(model.playlistItems.first)
        await model.setArrangement(arr.id, forPlaylistItem: item.id)
        await model.openPlaylistItem(item.id)
        #expect(model.slides.map(\.content.primary).map { $0.prefix(2) } == ["My", "Am", "My"])
        #expect(model.arrangements.map(\.name) == ["Chorus first"])
    }

    // MARK: Editing while live (LIVE-07, PRES-07)

    @Test func editingTheOpenPresentationNeverChangesLive() async throws {
        let (model, store) = try await ready()
        let (a, _) = try await twoSongPlaylist(model)
        await model.openPresentation(a)
        await model.goLive()
        await model.updateSlide(at: 0, content: SlideContent(primary: "a1 edited"))
        #expect(try await store.slides(of: a).first?.content.primary == "a1 edited")     // saved
        #expect(model.slides.first?.content.primary == "a1 edited")                        // editor shows it
        #expect(model.show.previewDeck?.slides.first?.primary == "a1 edited")              // preview has it
        #expect(model.show.liveSlide?.primary == "a1")                                     // live does not
        await model.goLive()                                                               // re-triggering takes the edit live
        #expect(model.show.liveSlide?.primary == "a1 edited")
    }

    @Test func quickEditChangesLiveAndStore() async throws {
        let (model, store) = try await ready()
        let (a, _) = try await twoSongPlaylist(model)
        await model.openPresentation(a)
        await model.goLive()
        await model.quickEditLiveSlide(SlideContent(primary: "a1 fixed", secondary: "sửa"))
        #expect(model.show.liveSlide == SlideContent(primary: "a1 fixed", secondary: "sửa"))
        #expect(try await store.slides(of: a).first?.content.primary == "a1 fixed")
        #expect(model.slides.first?.content.primary == "a1 fixed")
    }

    /// Deleting or re-flowing the presentation that is on screen does not blank the screen.
    @Test func deletingTheLivePresentationKeepsItOnScreen() async throws {
        let (model, _) = try await ready()
        let (a, _) = try await twoSongPlaylist(model)
        await model.openPresentation(a)
        await model.goLive()
        await model.deletePresentation(id: a)
        #expect(model.show.liveSlide?.primary == "a1")
        #expect(model.presentations.map(\.title) == ["Song B"])
        #expect(model.openPresentationID == nil && model.slides.isEmpty)
        await model.next()
        #expect(model.show.liveSlide?.primary == "a2")
    }

    @Test func slideAddMoveDeleteOnTheOpenPresentation() async throws {
        let (model, _) = try await ready()
        let (a, _) = try await twoSongPlaylist(model)
        await model.openPresentation(a)
        await model.addSlide(SlideContent(primary: "a3"))
        await model.moveSlide(from: 2, to: 0)
        #expect(model.slides.map(\.content.primary) == ["a3", "a1", "a2"])
        await model.deleteSlide(at: 1)
        #expect(model.slides.map(\.content.primary) == ["a3", "a2"])
        #expect(model.show.previewDeck?.slides.map(\.primary) == ["a3", "a2"])
    }

    // MARK: Search (PRES-08)

    @Test func searchFindsWithoutDiacriticsAndOpensAHit() async throws {
        let (model, _) = try await ready()
        let p = try #require(await model.importLyrics(title: "Amazing Grace", primaryText: grace, secondaryText: graceVi, maxLines: 2))
        await model.search("an dien la lung")
        #expect(model.searchResults.map(\.presentationID) == [p.id])
        await model.openSearchResult(model.searchResults[0])
        #expect(model.openPresentationID == p.id)
        await model.search("")
        #expect(model.searchResults.isEmpty)
    }

    // MARK: Restore (NFR-06)

    @Test func relaunchRestoresThePlaceToPreviewNeverToLive() async throws {
        let store = try LibraryStore.inMemory()
        let first = WorkspaceModel(store: store)
        await first.load()
        _ = try await twoSongPlaylist(first)
        await first.openPlaylistItem(first.playlistItems[1].id)
        first.selectSlide(1)
        await first.goLive()
        await first.flush()

        let second = WorkspaceModel(store: store)
        await second.load()
        #expect(second.selectedPlaylistID == first.selectedPlaylistID)
        #expect(second.selectedPlaylistItemID == first.playlistItems[1].id)
        #expect(second.slides.map(\.content.primary) == ["b1", "b2"])
        #expect(second.show.selectedIndex == 1)
        #expect(second.show.isStopped && second.show.liveSlide == nil)
    }

    /// A stored place that no longer exists is ignored quietly.
    @Test func restoreIgnoresDeletedItems() async throws {
        let store = try LibraryStore.inMemory()
        let first = WorkspaceModel(store: store)
        await first.load()
        let (a, _) = try await twoSongPlaylist(first)
        await first.openPlaylistItem(first.playlistItems[0].id)
        await first.flush()
        try await store.deletePresentation(id: a)
        let second = WorkspaceModel(store: store)
        await second.load()
        #expect(second.lastError == nil)
        #expect(second.openPresentationID == nil)
    }
}

@MainActor
@Suite struct DebouncedSaverTests {
    /// NFR-07: edits are written within two seconds, coalesced, and flushed at once on demand.
    @Test func coalescesAndFlushes() async throws {
        let clock = ManualSaveClock()
        var saved: [String] = []
        let saver = DebouncedSaver<String>(delay: 2, clock: clock) { saved.append($0) }
        saver.schedule("a"); saver.schedule("ab"); saver.schedule("abc")
        await clock.advance(by: 1.9)
        #expect(saved.isEmpty)
        await clock.advance(by: 0.2)
        #expect(saved == ["abc"])
        saver.schedule("abcd")
        await saver.flush()
        #expect(saved == ["abc", "abcd"])
        await saver.flush()                                  // nothing pending: no second write
        #expect(saved == ["abc", "abcd"])
        await clock.advance(by: 5)
        #expect(saved == ["abc", "abcd"])
    }

    /// A second edit restarts the wait but never beyond a hard cap, so continuous typing still saves.
    @Test func continuousTypingStillSavesWithinTheCap() async throws {
        let clock = ManualSaveClock()
        var saved: [Int] = []
        let saver = DebouncedSaver<Int>(delay: 2, maximumDelay: 5, clock: clock) { saved.append($0) }
        for i in 0..<6 { saver.schedule(i); await clock.advance(by: 1) }     // an edit every second for six seconds
        #expect(saved.isEmpty == false)
        #expect((saved.first ?? 0) >= 3)
    }
}
