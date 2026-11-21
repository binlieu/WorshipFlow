// SLIDE-003 / SLIDE-004 acceptance tests, persistence half (schema v2). Owned by the coordinator: do not modify.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct SongStructureStoreTests {
    func storeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }
    func song(_ store: LibraryStore) async throws -> Presentation {
        let lib = try await store.createLibrary(name: "Songs")
        return try await store.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
    }
    func reflowed(_ text: String, max: Int = 2) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: max) }

    @Test func schemaV2AddsStructureTables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        for expected in ["slideGroup", "arrangement", "arrangementItem"] { #expect(tables.contains(expected)) }
        #expect(Array(try await store.appliedMigrations().prefix(2)) == ["v1", "v2"])   // coordinator fix: later migrations may follow
    }

    /// Rows written under v1 survive v2, ungrouped and in order.
    @Test func v1SlidesSurviveV2Ungrouped() async throws {
        let url = storeURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v1")
        let p = try await song(old)
        for line in ["one", "two"] { _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: line)) }
        try old.close()
        let new = try LibraryStore.open(at: url)
        let slides = try await new.slides(of: p.id)
        #expect(slides.map(\.content.primary) == ["one", "two"])
        #expect(slides.allSatisfy { $0.groupID == nil })
        #expect(try await new.groups(of: p.id).isEmpty)
        try new.close()
    }

    @Test func replaceContentCreatesGroupsAndSlides() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "old slide"))
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\nc\n\nChorus\nd\n\ne"))
        let groups = try await store.groups(of: p.id)
        let slides = try await store.slides(of: p.id)
        #expect(groups.map(\.name) == ["Verse 1", "Chorus"])
        #expect(slides.map(\.content.primary) == ["a\nb", "c", "d", "e"])
        #expect(slides.map(\.sortOrder) == [0, 1, 2, 3])
        #expect(slides.map(\.groupID) == [groups[0].id, groups[0].id, groups[1].id, nil])
        #expect(try await store.search("old slide", limit: 5).isEmpty)        // search follows the replacement
        #expect(try await store.search("verse", limit: 5).isEmpty)            // labels are not lyrics
    }

    /// Re-flowing keeps group identity by name, so arrangements survive an edit.
    @Test func replaceContentKeepsGroupsWithTheSameName() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\n\nChorus\nb"))
        let before = try await store.groups(of: p.id)
        let arr = try await store.createArrangement(for: p.id, name: "Sunday", groupIDs: [before[1].id, before[0].id, before[1].id])
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na fixed\n\nChorus\nb\n\nBridge\nc"))
        let after = try await store.groups(of: p.id)
        #expect(after.map(\.name) == ["Verse 1", "Chorus", "Bridge"])
        #expect(after[0].id == before[0].id && after[1].id == before[1].id)
        #expect(try await store.arrangements(of: p.id).first?.groupIDs == arr.groupIDs)
        #expect(try await store.resolvedSlides(of: p.id, arrangementID: arr.id).map(\.content.primary) == ["b", "a fixed", "b"])
    }

    @Test func arrangementCrud() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\n\nChorus\nb"))
        let g = try await store.groups(of: p.id)
        let arr = try await store.createArrangement(for: p.id, name: "Full", groupIDs: [g[0].id, g[1].id, g[1].id])
        #expect(try await store.arrangements(of: p.id).map(\.name) == ["Full"])
        try await store.updateArrangement(id: arr.id, name: "Short", groupIDs: [g[1].id])
        let updated = try await store.arrangements(of: p.id)
        #expect(updated.map(\.name) == ["Short"] && updated[0].groupIDs == [g[1].id])
        #expect(try await store.resolvedSlides(of: p.id, arrangementID: nil).map(\.content.primary) == ["a", "b"])
        try await store.deleteArrangement(id: arr.id)
        #expect(try await store.arrangements(of: p.id).isEmpty)
        await #expect(throws: StoreError.notFound) { try await store.deleteArrangement(id: arr.id) }
    }

    /// An arrangement may only name groups of its own presentation.
    @Test func arrangementRejectsForeignGroups() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na"))
        await #expect(throws: StoreError.self) { _ = try await store.createArrangement(for: p.id, name: "Bad", groupIDs: [UUID()]) }
    }

    @Test func removingASectionUpdatesArrangements() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\n\nChorus\nb"))
        let g = try await store.groups(of: p.id)
        _ = try await store.createArrangement(for: p.id, name: "Full", groupIDs: [g[0].id, g[1].id, g[0].id])
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na"))     // Chorus is gone
        #expect(try await store.arrangements(of: p.id).first?.groupIDs == [g[0].id, g[0].id])
    }

    @Test func deletingPresentationRemovesItsStructure() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na"))
        let g = try await store.groups(of: p.id)
        _ = try await store.createArrangement(for: p.id, name: "Full", groupIDs: [g[0].id])
        try await store.deletePresentation(id: p.id)
        #expect(try await store.groups(of: p.id).isEmpty)
        #expect(try await store.arrangements(of: p.id).isEmpty)
    }

    /// A playlist item can carry an arrangement; removing the arrangement falls back to natural order.
    @Test func playlistItemArrangement() async throws {
        let store = try LibraryStore.inMemory()
        let p = try await song(store)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\n\nChorus\nb"))
        let g = try await store.groups(of: p.id)
        let arr = try await store.createArrangement(for: p.id, name: "Chorus first", groupIDs: [g[1].id, g[0].id])
        let list = try await store.createPlaylist(name: "Sunday")
        let item = try await store.addPresentation(p.id, to: list.id)
        #expect(try await store.slides(forPlaylistItem: item.id).map(\.content.primary) == ["a", "b"])
        try await store.setArrangement(arr.id, forPlaylistItem: item.id)
        #expect(try await store.playlistItems(of: list.id).first?.arrangementID == arr.id)
        #expect(try await store.slides(forPlaylistItem: item.id).map(\.content.primary) == ["b", "a"])
        try await store.deleteArrangement(id: arr.id)
        #expect(try await store.playlistItems(of: list.id).first?.arrangementID == nil)
        #expect(try await store.slides(forPlaylistItem: item.id).map(\.content.primary) == ["a", "b"])
    }
}
