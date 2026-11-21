// SYS-001: search behaves the same on the FTS5 and LIKE paths; records which path the system SQLite gives.
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct SearchBackendTests {
    @Test func reportsBackendAndTimesTwoThousandSongs() async throws {
        let store = try LibraryStore.inMemory()
        print("SYS-001 search backend in system SQLite: \(store.searchBackend)")
        let lib = try await store.createLibrary(name: "Big")
        try await store.importForTesting(libraryID: lib.id, count: 2000) { i in
            ("Song number \(i)", ["Verse line \(i) of praise", "Chorus line \(i) lạ lùng", "Bridge \(i)"])
        }
        let clock = ContinuousClock()
        var hits: [SearchHit] = []
        let elapsed = try await clock.measure { hits = try await store.search("chorus 1234", limit: 20) }
        print("SYS-001 2000-song search (\(store.searchBackend)): \(elapsed)")
        #expect(hits.first?.title == "Song number 1234")
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func backendBehaviour(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try LibraryStore.inMemory(forcing: backend)
        #expect(store.searchBackend == backend)
        let lib = try await store.createLibrary(name: "Songs")
        let grace = try await store.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        _ = try await store.appendSlide(to: grace.id, content: SlideContent(primary: "how sweet", secondary: "Ân điển lạ lùng"))
        let note = try await store.createPresentation(in: lib.id, title: "Sermon notes", kind: .sermon)
        _ = try await store.appendSlide(to: note.id, content: SlideContent(primary: "Saved by grace"))

        #expect(try await store.search("an dien la lung", limit: 10).map(\.presentationID) == [grace.id])
        let hits = try await store.search("grace", limit: 10)
        #expect(hits.map(\.presentationID) == [grace.id, note.id])
        #expect(hits.map(\.matchedTitle) == [true, false])
        #expect(try await store.search("amaz", limit: 10).map(\.presentationID) == [grace.id])
        #expect(try await store.search("mazing", limit: 10).isEmpty)          // prefix only, not substring
        #expect(try await store.search("grace sermon", limit: 10).map(\.presentationID) == [note.id])
        #expect(try await store.search("\"'; DROP TABLE slide; -- * ( ) OR NEAR", limit: 10).isEmpty)
        try await store.renamePresentation(id: note.id, to: "Grace alone")
        #expect(try await store.search("alone", limit: 10).map(\.presentationID) == [note.id])
        try await store.deleteLibrary(id: lib.id)
        #expect(try await store.search("grace", limit: 10).isEmpty)
    }
}
