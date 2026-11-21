// UI-002 Part 5: schema v8 gives playlist items a kind and a small JSON payload, and lets an item have no presentation.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct UI002_PlaylistKindStoreTests {
    func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    static func song(_ store: LibraryStore) async throws -> Presentation {
        let lib = try await store.createLibrary(name: "L")
        return try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
    }

    @Test func migrationV8FollowsV7AndKeepsTheEarlierOnesInOrder() async throws {
        let store = try LibraryStore.inMemory()
        let applied = try await store.appliedMigrations()
        #expect(Array(applied.prefix(8)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8"])
    }

    @Test func rowsWrittenBeforeV8BecomePresentationItems() async throws {
        let url = storeURL()
        var playlist = UUID(), presentation = UUID()
        let item = UUID()
        do {
            let old = try LibraryStore.open(at: url, migratingUpTo: "v7")
            let lib = try await old.createLibrary(name: "L")
            presentation = try await old.createPresentation(in: lib.id, title: "Song", kind: .song).id
            playlist = try await old.createPlaylist(name: "Service").id
            // Written as a v7 build would have: no kind column.
            try await old.writer.write { [playlist, presentation, item] db in
                try db.execute(sql: "INSERT INTO playlistItem (id, playlistID, presentationID, sortOrder, createdAt) VALUES (?, ?, ?, 0, ?)",
                               arguments: [item.dbText, playlist.dbText, presentation.dbText, Date()])
            }
        }
        let store = try LibraryStore.open(at: url)
        let items = try await store.playlistItems(of: playlist)
        #expect(items.count == 1 && items[0].id == item && items[0].kind == .presentation && items[0].title == "Song")
        #expect(items[0].presentationID == presentation)
    }

    @Test func headersAndCountdownsAreStoredBetweenPresentationsInOrder() async throws {
        let store = try LibraryStore.inMemory()
        let playlist = try await store.createPlaylist(name: "Service")
        let song = try await Self.song(store)
        _ = try await store.addPresentation(song.id, to: playlist.id)
        let header = try await store.addPlaylistHeader("Worship", to: playlist.id)
        let spec = CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300))
        let countdown = try await store.addPlaylistCountdown(spec, to: playlist.id)
        let items = try await store.playlistItems(of: playlist.id)
        #expect(items.map(\.kind) == [.presentation, .header(label: "Worship"), .countdown(spec)])
        #expect(items.map(\.sortOrder) == [0, 1, 2])
        #expect(items[1].title == "Worship" && items[2].title == "Starting soon")
        #expect(header.id == items[1].id && countdown.id == items[2].id)
    }

    @Test func movingAndRemovingWorkAcrossKinds() async throws {
        let store = try LibraryStore.inMemory()
        let playlist = try await store.createPlaylist(name: "S")
        let song = try await Self.song(store)
        let a = try await store.addPlaylistHeader("A", to: playlist.id)
        _ = try await store.addPresentation(song.id, to: playlist.id)
        try await store.movePlaylistItem(id: a.id, to: 1)
        #expect(try await store.playlistItems(of: playlist.id).map(\.kind) == [.presentation, .header(label: "A")])
        try await store.removePlaylistItem(id: a.id)
        let left = try await store.playlistItems(of: playlist.id)
        #expect(left.count == 1 && left[0].sortOrder == 0)
    }

    @Test func aHeaderHasNoSlidesAndDeletingASongLeavesHeadersAlone() async throws {
        let store = try LibraryStore.inMemory()
        let playlist = try await store.createPlaylist(name: "S")
        let song = try await Self.song(store)
        _ = try await store.addPresentation(song.id, to: playlist.id)
        let h = try await store.addPlaylistHeader("Worship", to: playlist.id)
        #expect(try await store.slides(forPlaylistItem: h.id).isEmpty)
        try await store.deletePresentation(id: song.id)
        #expect(try await store.playlistItems(of: playlist.id).map(\.kind) == [.header(label: "Worship")])
    }

    @Test func aCountdownCanBeEditedInPlace() async throws {
        let store = try LibraryStore.inMemory()
        let playlist = try await store.createPlaylist(name: "S")
        let c = try await store.addPlaylistCountdown(CountdownSpec(label: "A", mode: .duration(seconds: 60)), to: playlist.id)
        let spec = CountdownSpec(label: "B", mode: .targetTime(hour: 9, minute: 30))
        try await store.updatePlaylistItem(id: c.id, kind: .countdown(spec))
        #expect(try await store.playlistItems(of: playlist.id).first?.kind == .countdown(spec))
    }
}
