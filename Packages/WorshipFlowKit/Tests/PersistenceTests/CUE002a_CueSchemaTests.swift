// CUE-002a: the cue tables (migration v9), the narrow accessor CueStore uses, and slide actions across a reflow.
// Written by the implementer. Rows are written with raw SQL here; the CueStore tests cover the API on top.
import Testing
import Foundation
import GRDB
import Domain
@testable @_spi(CueStore) import Persistence

@Suite struct CueSchemaTests {
    func tempURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wf-cue002a-\(UUID().uuidString)/Library.sqlite")
    }

    func reflowed(_ text: String, max: Int = 1) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: max) }

    func setActions(_ store: LibraryStore, slide: UUID, _ definition: String) async throws {
        try await store.cueWrite { db in
            try db.execute(sql: "INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?)",
                           arguments: [slide.uuidString, definition, Date(), Date()])
        }
    }

    func actionRows(_ store: LibraryStore) async throws -> [String: String] {
        try await store.cueRead { db in
            Dictionary(uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT slideID, definition FROM cueSlideActions").map { ($0["slideID"] as String, $0["definition"] as String) })
        }
    }

    @Test func v9CreatesTheFiveCueTables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        for t in ["cueMacro", "cueSlideActions", "cueScheduledEvent", "cueScheduleState", "cueMIDIBinding"] {
            #expect(tables.contains(t), "missing \(t)")
        }
        #expect(Array(try await store.appliedMigrations().prefix(9)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "v9"])
    }

    @Test func aLibraryWrittenAtV8KeepsItsRowsWhenV9Arrives() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let presentationID: UUID
        do {
            let old = try LibraryStore.open(at: url, migratingUpTo: "v8")
            #expect(!(try await old.tableNames()).contains("cueMacro"))
            let lib = try await old.createLibrary(name: "Songs")
            let p = try await old.createPresentation(in: lib.id, title: "Amazing", kind: .song)
            _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: "a"))
            try await old.setState("kept", for: "k")
            presentationID = p.id
            try old.close()
        }
        let new = try LibraryStore.open(at: url)
        #expect(Array(try await new.appliedMigrations().prefix(9).suffix(1)) == ["v9"])
        #expect(try await new.slides(of: presentationID).map(\.content.primary) == ["a"])
        #expect(try await new.state(for: "k") == "kept")
        #expect(try await new.cueRead { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM cueMacro") } == 0)
        try new.close()
    }

    @Test func openingTwiceDoesNotRunV9Twice() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try LibraryStore.open(at: url).close()
        let second = try LibraryStore.open(at: url)
        #expect(try await second.appliedMigrations().filter { $0 == "v9" }.count == 1)
        try second.close()
    }

    @Test func slideActionsGoWhenTheirSlideIsDeletedAndWhenThePresentationIs() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "P", kind: .song)
        let s1 = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one"))
        let s2 = try await store.appendSlide(to: p.id, content: SlideContent(primary: "two"))
        try await setActions(store, slide: s1.id, "{\"version\":1}")
        try await setActions(store, slide: s2.id, "{\"version\":1}")
        try await store.deleteSlide(id: s1.id)
        #expect(Set(try await actionRows(store).keys) == [s2.id.uuidString])
        try await store.deletePresentation(id: p.id)
        #expect(try await actionRows(store).isEmpty)
    }

    @Test func aSlideAnActionsRowDoesNotMatchCannotBeInserted() async throws {
        let store = try LibraryStore.inMemory()
        await #expect(throws: (any Error).self) { try await setActions(store, slide: UUID(), "{}") }
    }

    @Test func slideActionsFollowASlideWhoseWordsDidNotChangeAcrossAReflow() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc"))
        let before = try await store.slides(of: p.id)
        let byWords = Dictionary(uniqueKeysWithValues: before.map { ($0.content.primary, $0.id) })
        try await setActions(store, slide: try #require(byWords["a"]), "{\"v\":\"a\"}")
        try await setActions(store, slide: try #require(byWords["b"]), "{\"v\":\"b\"}")
        try await setActions(store, slide: try #require(byWords["c"]), "{\"v\":\"c\"}")

        // a is edited, b and c are untouched, a new Bridge section is added.
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na edited\nb\n\nChorus\nc\n\nBridge\nd"))
        let after = try await store.slides(of: p.id)
        #expect(after.map(\.content.primary) == ["a edited", "b", "c", "d"])
        let rows = try await actionRows(store)
        #expect(rows[after[1].id.uuidString] == "{\"v\":\"b\"}")
        #expect(rows[after[2].id.uuidString] == "{\"v\":\"c\"}")
        #expect(rows[after[0].id.uuidString] == nil && rows[after[3].id.uuidString] == nil)
        #expect(rows.count == 2, "the edited slide's actions are gone, nothing is left pointing at a vanished slide")
    }

    @Test func reflowingTheSameTextKeepsEveryActionRowAndItsCreatedTime() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        let text = "Verse 1\na\n\nChorus\nb"
        try await store.replaceContent(of: p.id, with: reflowed(text))
        for s in try await store.slides(of: p.id) { try await setActions(store, slide: s.id, "{\"v\":\"\(s.content.primary)\"}") }
        let created = try await store.cueRead { try String.fetchAll($0, sql: "SELECT createdAt FROM cueSlideActions ORDER BY slideID") }
        try await store.replaceContent(of: p.id, with: reflowed(text))
        let slides = try await store.slides(of: p.id)
        let rows = try await actionRows(store)
        #expect(rows[slides[0].id.uuidString] == "{\"v\":\"a\"}" && rows[slides[1].id.uuidString] == "{\"v\":\"b\"}")
        let createdAfter = try await store.cueRead { try String.fetchAll($0, sql: "SELECT createdAt FROM cueSlideActions ORDER BY slideID") }
        #expect(created.sorted() == createdAfter.sorted())
    }

    @Test func twoSlidesWithTheSameWordsEachKeepTheirOwnActionsInOrder() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await store.replaceContent(of: p.id, with: reflowed("Chorus\nsame\nsame"))
        let before = try await store.slides(of: p.id)
        try await setActions(store, slide: before[0].id, "{\"n\":1}")
        try await setActions(store, slide: before[1].id, "{\"n\":2}")
        try await store.replaceContent(of: p.id, with: reflowed("Chorus\nsame\nsame"))
        let after = try await store.slides(of: p.id)
        let rows = try await actionRows(store)
        #expect(rows[after[0].id.uuidString] == "{\"n\":1}" && rows[after[1].id.uuidString] == "{\"n\":2}")
    }

    @Test func aReflowOnAStoreWithoutTheCueTablesStillWorks() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = try LibraryStore.open(at: url, migratingUpTo: "v8")
        let lib = try await old.createLibrary(name: "L")
        let p = try await old.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await old.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb"))
        #expect(try await old.slides(of: p.id).count == 2)
        try old.close()
    }

    @Test func aReflowOfAnUnknownPresentationLeavesTheActionsAlone() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "L")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na"))
        let slide = try #require(try await store.slides(of: p.id).first)
        try await setActions(store, slide: slide.id, "{\"v\":1}")
        await #expect(throws: (any Error).self) { try await store.replaceContent(of: UUID(), with: reflowed("x")) }   // unknown presentation
        #expect(Set(try await actionRows(store).keys) == [slide.id.uuidString])
    }
}
