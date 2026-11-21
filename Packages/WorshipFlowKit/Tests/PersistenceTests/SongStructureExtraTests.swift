// SLIDE-003: extra persistence cases (written by the implementer).
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct SongStructureExtraTests {
    func setUp() async throws -> (LibraryStore, Presentation) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        return (store, try await store.createPresentation(in: lib.id, title: "Song", kind: .song))
    }

    @Test func arrangementOfAnotherPresentationIsRejectedForAPlaylistItem() async throws {
        let (store, p) = try await setUp()
        let lib = try #require(try await store.libraries().first)
        let other = try await store.createPresentation(in: lib.id, title: "Other", kind: .song)
        try await store.replaceContent(of: other.id, with: Reflow.contents(primary: "Verse 1\nx", secondary: nil, maxLines: 2))
        let g = try await store.groups(of: other.id)
        let arr = try await store.createArrangement(for: other.id, name: "A", groupIDs: [g[0].id])
        let list = try await store.createPlaylist(name: "L")
        let item = try await store.addPresentation(p.id, to: list.id)
        await #expect(throws: StoreError.invalidReference) { try await store.setArrangement(arr.id, forPlaylistItem: item.id) }
    }

    @Test func groupsCannotBeUsedAcrossPresentations() async throws {
        let (store, p) = try await setUp()
        let lib = try #require(try await store.libraries().first)
        let other = try await store.createPresentation(in: lib.id, title: "Other", kind: .song)
        try await store.replaceContent(of: other.id, with: Reflow.contents(primary: "Verse 1\nx", secondary: nil, maxLines: 2))
        let foreign = try await store.groups(of: other.id)[0].id
        await #expect(throws: StoreError.invalidReference) { _ = try await store.createArrangement(for: p.id, name: "A", groupIDs: [foreign]) }
    }

    @Test func replacingWithNothingClearsEverything() async throws {
        let (store, p) = try await setUp()
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "Verse 1\na", secondary: nil, maxLines: 2))
        try await store.replaceContent(of: p.id, with: [])
        #expect(try await store.slides(of: p.id).isEmpty)
        #expect(try await store.groups(of: p.id).isEmpty)
    }

    @Test func reorderedSectionsRenumberKeptGroups() async throws {
        let (store, p) = try await setUp()
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "Verse 1\na\n\nChorus\nb", secondary: nil, maxLines: 2))
        let before = try await store.groups(of: p.id)
        try await store.replaceContent(of: p.id, with: Reflow.contents(primary: "Chorus\nb\n\nVerse 1\na", secondary: nil, maxLines: 2))
        let after = try await store.groups(of: p.id)
        #expect(after.map(\.id) == [before[1].id, before[0].id])
        #expect(after.map(\.sortOrder) == [0, 1])
    }

    @Test func unknownIDsThrowNotFound() async throws {
        let (store, _) = try await setUp()
        await #expect(throws: StoreError.notFound) { try await store.updateArrangement(id: UUID(), name: "x", groupIDs: []) }
        await #expect(throws: StoreError.notFound) { _ = try await store.slides(forPlaylistItem: UUID()) }
        await #expect(throws: StoreError.notFound) { try await store.setArrangement(nil, forPlaylistItem: UUID()) }
    }
}
