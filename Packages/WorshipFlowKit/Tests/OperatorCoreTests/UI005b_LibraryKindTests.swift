// UI-005b item 3: a library has a kind (songs, scripture, sermons, announcements). The first library of a new store is songs, the
// kind is stored and can be changed, and the sidebar lists libraries in the design's order with the Scripture entry after the songs.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI005b_LibraryKindTests {
    @Test func aFirstRunLibraryIsSongsAndANewOneTakesTheKindItWasMadeWith() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        #expect(model.libraries.map(\.kind) == [.songs])
        await model.createLibrary(name: "Sermons", kind: .sermons)
        await model.createLibrary(name: "Notices", kind: .announcements)
        #expect(model.libraries.map(\.kind) == [.songs, .sermons, .announcements])
        #expect(try await store.libraries().map(\.kind) == [.songs, .sermons, .announcements])     // stored, not only held
        await model.createLibrary(name: "Plain")
        #expect(model.libraries.last?.kind == .songs)                                              // no kind given: songs
    }

    @Test func theKindCanBeChangedAndTheLibraryKeepsItsPresentations() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store)
        await model.load()
        let song = try #require(await model.importLyrics(title: "S", primaryText: "words", secondaryText: nil, maxLines: 2))
        let id = try #require(model.libraries.first?.id)
        await model.setLibraryKind(id: id, to: .sermons)
        #expect(model.libraries.first?.kind == .sermons)
        #expect(model.libraries.first?.name == "Songs")
        #expect(model.presentations.map(\.id) == [song.id])
        #expect(model.libraryCounts[id] == 1)
    }

    @Test func theSidebarOrderIsSongsThenScriptureThenSermonsThenAnnouncements() {
        func lib(_ name: String, _ kind: LibraryKind, _ order: Int) -> Library { Library(name: name, sortOrder: order, kind: kind) }
        let all = [lib("Notices", .announcements, 0), lib("Talks", .sermons, 1), lib("Hymns", .songs, 2), lib("Kept verses", .scripture, 3), lib("Songs", .songs, 4)]
        #expect(LibraryListing.sidebarOrder(all).map(\.name) == ["Hymns", "Songs", "Kept verses", "Talks", "Notices"])
        // The Scripture entry (the Bible view) sits after the songs libraries.
        #expect(LibraryListing.scriptureEntryPosition(in: LibraryListing.sidebarOrder(all)) == 2)
        #expect(LibraryListing.scriptureEntryPosition(in: LibraryListing.sidebarOrder([lib("Talks", .sermons, 0)])) == 0)
        #expect(LibraryListing.scriptureEntryPosition(in: []) == 0)
    }

    @Test func everyKindHasAWordForVoiceOver() {
        #expect(LibraryKind.allCases.map(\.title) == ["Songs", "Scripture", "Sermons", "Announcements"])
    }
}
