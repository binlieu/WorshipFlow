// SYS-001 acceptance tests. Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
@testable import Persistence

func temporaryStoreURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Library.sqlite")
}

@Suite struct MigrationTests {
    @Test func newStoreHasSchemaV1Tables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        for expected in ["library", "presentation", "slide", "playlist", "playlistItem", "appState"] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
        #expect(try await store.appliedMigrations().first == "v1")
    }

    @Test func openCreatesMissingDirectoriesAndFile() async throws {
        let url = temporaryStoreURL()
        let store = try LibraryStore.open(at: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
        try store.close()
    }

    /// ADR-0004 decision 7: rows written at v1 survive migration to the latest schema.
    @Test func v1RowsSurviveMigrationToLatest() async throws {
        let url = temporaryStoreURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v1")
        let lib = try await old.createLibrary(name: "Songs")
        let song = try await old.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        _ = try await old.appendSlide(to: song.id, content: SlideContent(primary: "Amazing grace", secondary: "Ân điển lạ lùng"))
        try old.close()

        let new = try LibraryStore.open(at: url)
        #expect(try await new.libraries().map(\.name) == ["Songs"])
        #expect(try await new.presentations(in: lib.id).map(\.title) == ["Amazing Grace"])
        #expect(try await new.slides(of: song.id).first?.content.secondary == "Ân điển lạ lùng")
        try new.close()
    }

    /// NFR-07 groundwork: a committed write is on disk without a clean shutdown.
    @Test func committedWriteSurvivesAbandonedConnection() async throws {
        let url = temporaryStoreURL()
        var libraryID: UUID?
        do {
            let store = try LibraryStore.open(at: url)
            libraryID = try await store.createLibrary(name: "Unsaved?").id
            // No close(): the store is simply dropped, as after a forced quit.
        }
        let reopened = try LibraryStore.open(at: url)
        #expect(try await reopened.libraries().map(\.id) == [libraryID])
        try reopened.close()
    }
}

@Suite struct LibraryTests {
    @Test func createRenameDeleteLibrary() async throws {
        let store = try LibraryStore.inMemory()
        let a = try await store.createLibrary(name: "Songs")
        let b = try await store.createLibrary(name: "Sermons")
        #expect(try await store.libraries().map(\.name) == ["Songs", "Sermons"])
        try await store.renameLibrary(id: a.id, to: "Hymns")
        #expect(try await store.libraries().map(\.name) == ["Hymns", "Sermons"])
        try await store.deleteLibrary(id: b.id)
        #expect(try await store.libraries().map(\.name) == ["Hymns"])
    }

    @Test func emptyNameIsRejected() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.self) { _ = try await store.createLibrary(name: "   ") }
    }

    @Test func deletingLibraryCascades() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let song = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        _ = try await store.appendSlide(to: song.id, content: SlideContent(primary: "Line"))
        let list = try await store.createPlaylist(name: "Sunday")
        _ = try await store.addPresentation(song.id, to: list.id)

        try await store.deleteLibrary(id: lib.id)
        #expect(try await store.presentations(in: lib.id).isEmpty)
        #expect(try await store.slides(of: song.id).isEmpty)
        #expect(try await store.playlistItems(of: list.id).isEmpty)
        #expect(try await store.playlists().count == 1)   // the playlist itself stays
    }

    @Test func movePresentationBetweenLibraries() async throws {
        let store = try LibraryStore.inMemory()
        let a = try await store.createLibrary(name: "A")
        let b = try await store.createLibrary(name: "B")
        let p = try await store.createPresentation(in: a.id, title: "Moved", kind: .other)
        try await store.movePresentation(id: p.id, to: b.id)
        #expect(try await store.presentations(in: a.id).isEmpty)
        #expect(try await store.presentations(in: b.id).map(\.title) == ["Moved"])
    }
}

@Suite struct SlideTests {
    func makeSong(_ store: LibraryStore) async throws -> Presentation {
        let lib = try await store.createLibrary(name: "Songs")
        return try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
    }

    @Test func slidesKeepOrderAndContent() async throws {
        let store = try LibraryStore.inMemory()
        let song = try await makeSong(store)
        for line in ["one", "two", "three"] { _ = try await store.appendSlide(to: song.id, content: SlideContent(primary: line)) }
        let slides = try await store.slides(of: song.id)
        #expect(slides.map(\.content.primary) == ["one", "two", "three"])
        #expect(slides.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func moveSlideKeepsDenseOrder() async throws {
        let store = try LibraryStore.inMemory()
        let song = try await makeSong(store)
        var ids: [UUID] = []
        for line in ["a", "b", "c", "d"] { ids.append(try await store.appendSlide(to: song.id, content: SlideContent(primary: line)).id) }
        try await store.moveSlide(id: ids[3], to: 0)
        try await store.moveSlide(id: ids[0], to: 3)
        var slides = try await store.slides(of: song.id)
        #expect(slides.map(\.content.primary) == ["d", "b", "c", "a"])
        #expect(slides.map(\.sortOrder) == [0, 1, 2, 3])
        try await store.deleteSlide(id: ids[1])
        slides = try await store.slides(of: song.id)
        #expect(slides.map(\.content.primary) == ["d", "c", "a"])
        #expect(slides.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func moveSlideClampsIndex() async throws {
        let store = try LibraryStore.inMemory()
        let song = try await makeSong(store)
        var ids: [UUID] = []
        for line in ["a", "b", "c"] { ids.append(try await store.appendSlide(to: song.id, content: SlideContent(primary: line)).id) }
        try await store.moveSlide(id: ids[0], to: 99)
        #expect(try await store.slides(of: song.id).map(\.content.primary) == ["b", "c", "a"])
    }

    @Test func updateSlideChangesContentOnly() async throws {
        let store = try LibraryStore.inMemory()
        let song = try await makeSong(store)
        var slide = try await store.appendSlide(to: song.id, content: SlideContent(primary: "tpyo"))
        _ = try await store.appendSlide(to: song.id, content: SlideContent(primary: "second"))
        slide.content = SlideContent(primary: "typo", secondary: "sửa")
        slide.notes = "fixed"
        try await store.updateSlide(slide)
        let slides = try await store.slides(of: song.id)
        #expect(slides[0].content == SlideContent(primary: "typo", secondary: "sửa"))
        #expect(slides[0].notes == "fixed")
        #expect(slides[1].content.primary == "second")
    }

    @Test func unknownIDsThrowNotFound() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: StoreError.notFound) { try await store.deleteSlide(id: UUID()) }
        await #expect(throws: StoreError.notFound) { try await store.renameLibrary(id: UUID(), to: "x") }
        await #expect(throws: StoreError.notFound) { _ = try await store.createPresentation(in: UUID(), title: "x", kind: .song) }
    }
}

@Suite struct PlaylistTests {
    @Test func playlistOrderAndReorder() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let list = try await store.createPlaylist(name: "Sunday")
        var items: [PlaylistItem] = []
        for title in ["Welcome", "Song 1", "Sermon"] {
            let p = try await store.createPresentation(in: lib.id, title: title, kind: .other)
            items.append(try await store.addPresentation(p.id, to: list.id))
        }
        #expect(try await store.playlistItems(of: list.id).map(\.title) == ["Welcome", "Song 1", "Sermon"])
        try await store.movePlaylistItem(id: items[2].id, to: 0)
        let after = try await store.playlistItems(of: list.id)
        #expect(after.map(\.title) == ["Sermon", "Welcome", "Song 1"])
        #expect(after.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func samePresentationCanAppearTwice() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let list = try await store.createPlaylist(name: "Sunday")
        let p = try await store.createPresentation(in: lib.id, title: "Doxology", kind: .song)
        _ = try await store.addPresentation(p.id, to: list.id)
        _ = try await store.addPresentation(p.id, to: list.id)
        #expect(try await store.playlistItems(of: list.id).count == 2)
    }

    @Test func deletingPresentationRemovesItFromPlaylists() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let list = try await store.createPlaylist(name: "Sunday")
        let keep = try await store.createPresentation(in: lib.id, title: "Keep", kind: .song)
        let drop = try await store.createPresentation(in: lib.id, title: "Drop", kind: .song)
        _ = try await store.addPresentation(drop.id, to: list.id)
        _ = try await store.addPresentation(keep.id, to: list.id)
        try await store.deletePresentation(id: drop.id)
        let items = try await store.playlistItems(of: list.id)
        #expect(items.map(\.title) == ["Keep"])
        #expect(items.map(\.sortOrder) == [0])
    }
}

@Suite struct SearchTests {
    func seeded() async throws -> (LibraryStore, UUID) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let grace = try await store.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        _ = try await store.appendSlide(to: grace.id, content: SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay"))
        let holy = try await store.createPresentation(in: lib.id, title: "Holy, Holy, Holy", kind: .song)
        _ = try await store.appendSlide(to: holy.id, content: SlideContent(primary: "Lord God Almighty", secondary: "Đức Chúa Trời toàn năng"))
        let graceNote = try await store.createPresentation(in: lib.id, title: "Sermon notes", kind: .sermon)
        _ = try await store.appendSlide(to: graceNote.id, content: SlideContent(primary: "Saved by grace through faith"))
        return (store, grace.id)
    }

    @Test func findsVietnameseWithoutDiacritics() async throws {
        let (store, graceID) = try await seeded()
        #expect(try await store.search("an dien la lung", limit: 10).map(\.presentationID) == [graceID])
        #expect(try await store.search("duc chua troi", limit: 10).map(\.title) == ["Holy, Holy, Holy"])
        #expect(try await store.search("ĐIỂN", limit: 10).map(\.presentationID) == [graceID])
    }

    @Test func titleMatchesRankFirst() async throws {
        let (store, graceID) = try await seeded()
        let hits = try await store.search("grace", limit: 10)
        #expect(hits.count == 2)
        #expect(hits.first?.presentationID == graceID)
        #expect(hits.first?.matchedTitle == true)
        #expect(hits.last?.matchedTitle == false)
    }

    @Test func prefixOfLastWordMatches() async throws {
        let (store, graceID) = try await seeded()
        #expect(try await store.search("amaz", limit: 10).map(\.presentationID) == [graceID])
    }

    @Test func searchReflectsEditsAndDeletes() async throws {
        let (store, graceID) = try await seeded()
        var slide = try #require(try await store.slides(of: graceID).first)
        slide.content = SlideContent(primary: "Completely different words")
        try await store.updateSlide(slide)
        #expect(try await store.search("sweet sound", limit: 10).isEmpty)
        #expect(try await store.search("different words", limit: 10).map(\.presentationID) == [graceID])
        try await store.deletePresentation(id: graceID)
        #expect(try await store.search("different", limit: 10).isEmpty)
    }

    @Test func emptyAndHostileQueriesAreSafe() async throws {
        let (store, _) = try await seeded()
        #expect(try await store.search("   ", limit: 10).isEmpty)
        #expect(try await store.search("\"'; DROP TABLE slide; -- * ( ) OR NEAR", limit: 10).isEmpty)
        #expect(try await store.libraries().count == 1)
    }

    /// PRES-08: 2,000 songs, result within 200 ms.
    @Test func searchIsFastOnTwoThousandSongs() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Big")
        try await store.importForTesting(libraryID: lib.id, count: 2000) { i in
            ("Song number \(i)", ["Verse line \(i) of praise", "Chorus line \(i) lạ lùng", "Bridge \(i)"])
        }
        let clock = ContinuousClock()
        var hits: [SearchHit] = []
        let elapsed = try await clock.measure { hits = try await store.search("chorus 1234", limit: 20) }
        #expect(hits.first?.title == "Song number 1234")
        #expect(elapsed < .milliseconds(200))
    }
}

@Suite struct AppStateTests {
    @Test func stateRoundTripsAndClears() async throws {
        let store = try LibraryStore.inMemory()
        #expect(try await store.state(for: "openPlaylist") == nil)
        try await store.setState("abc", for: "openPlaylist")
        try await store.setState("def", for: "openPlaylist")
        #expect(try await store.state(for: "openPlaylist") == "def")
        try await store.setState(nil, for: "openPlaylist")
        #expect(try await store.state(for: "openPlaylist") == nil)
    }
}
