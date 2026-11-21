// LIB-004c: a playlist item can be a scripture passage. It is stored in the existing `kind` and `payload` columns of schema v8
// (reference and translation codes, never verse text), so no new migration is needed and every older row is untouched.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct LIB004c_ScripturePlaylistItemTests {
    static let spec = ScriptureItemSpec(
        label: "John 3:16\u{2013}18 (ENT)",
        ranges: [ScriptureItemSpec.Range(book: "JHN", startChapter: 3, startVerse: 16, endChapter: 3, endVerse: 18)],
        primaryCode: "en-test", secondaryCode: "vi-test")

    func storeURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    @Test func noNewMigrationWasNeeded() async throws {
        let store = try LibraryStore.inMemory()
        let applied = try await store.appliedMigrations()
        #expect(Array(applied.prefix(10)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9", "v10"])
        #expect(applied.count == 10)
    }

    @Test func theKindIsStoredAsAWordAndAReferenceNotAsText() throws {
        let stored = PlaylistItemKind.scripture(Self.spec).stored
        #expect(stored.kind == "scripture")
        let payload = try #require(stored.payload)
        #expect(payload.contains("en-test") && payload.contains("JHN"))
        #expect(PlaylistItemKind(storedKind: stored.kind, payload: stored.payload) == .scripture(Self.spec))
        #expect(PlaylistItemKind.scripture(Self.spec).isSelectableLive)
    }

    @Test func aDamagedPayloadReadsAsAHeaderSoThePlaylistStillLoads() {
        let kind = PlaylistItemKind(storedKind: "scripture", payload: "{not json")
        #expect(kind.isHeader)
    }

    @Test func anItemSurvivesReopeningTheFileAndOlderRowsAreUntouched() async throws {
        let url = storeURL()
        let playlist: UUID
        do {
            let store = try LibraryStore.open(at: url)
            let lib = try await store.createLibrary(name: "L")
            let song = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
            let p = try await store.createPlaylist(name: "Service")
            playlist = p.id
            _ = try await store.addPresentation(song.id, to: p.id)
            _ = try await store.addPlaylistHeader("Worship", to: p.id)
            let added = try await store.addPlaylistScripture(Self.spec, to: p.id)
            #expect(added.title == Self.spec.label && added.kind == .scripture(Self.spec))
            #expect(added.presentationID == PlaylistItem.noPresentationID)
        }
        let again = try LibraryStore.open(at: url)
        let items = try await again.playlistItems(of: playlist)
        #expect(items.map(\.title) == ["Song", "Worship", Self.spec.label])
        #expect(items.map(\.kind) == [.presentation, .header(label: "Worship"), .scripture(Self.spec)])
        #expect(try await again.slides(forPlaylistItem: items[2].id).isEmpty)
    }

    @Test func aScriptureItemCanBeChangedAndRemovedLikeAnyOther() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await store.createPlaylist(name: "Service")
        let item = try await store.addPlaylistScripture(Self.spec, to: p.id)
        var changed = Self.spec
        changed.secondaryCode = nil
        changed.label = "John 3:16\u{2013}18 (ENT)"
        try await store.updatePlaylistItem(id: item.id, kind: .scripture(changed))
        #expect(try await store.playlistItems(of: p.id).first?.kind == .scripture(changed))
        try await store.removePlaylistItem(id: item.id)
        #expect(try await store.playlistItems(of: p.id).isEmpty)
    }
}
