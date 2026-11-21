// LIB-004b: schema v7 (translations and verses) and the accessor ScriptureStore uses. Synthetic text only.
import Testing
import Foundation
import GRDB
import Domain
@_spi(ScriptureStore) @testable import Persistence

@Suite struct ScriptureSchemaTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wf-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Library.sqlite")
    }

    @Test func v7CreatesTheScriptureTables() async throws {
        let store = try LibraryStore.inMemory()
        let tables = try await store.tableNames()
        #expect(tables.contains("scriptureTranslation") && tables.contains("scriptureVerse"))
        let applied = try await store.appliedMigrations()
        #expect(Array(applied.prefix(7)) == ["v1", "v2", "v3", "v4", "v5", "v6", "v7"])
    }

    @Test func columnsMatchTheDataDictionary() async throws {
        let store = try LibraryStore.inMemory()
        let (translation, verse) = try await store.scriptureRead { db -> ([String], [String]) in
            (try db.columns(in: "scriptureTranslation").map(\.name), try db.columns(in: "scriptureVerse").map(\.name))
        }
        for name in ["id", "code", "name", "language", "abbreviation", "copyright", "licence", "sourceDescription",
                     "isPublicDomain", "ownerApprovalJSON", "versificationID", "versificationJSON", "versificationNote",
                     "verseCount", "importedAt"] { #expect(translation.contains(name), "scriptureTranslation.\(name)") }
        for name in ["translationID", "bookOrder", "chapter", "verse", "text", "textFolded"] { #expect(verse.contains(name), "scriptureVerse.\(name)") }
    }

    /// Rows written under v6 are untouched by v7, and v7 adds the tables to that file.
    @Test func v6RowsSurviveV7() async throws {
        let url = tempURL()
        let old = try LibraryStore.open(at: url, migratingUpTo: "v6")
        #expect(!(try await old.tableNames()).contains("scriptureVerse"))
        let lib = try await old.createLibrary(name: "Songs")
        let song = try await old.createPresentation(in: lib.id, title: "Amazing Grace", kind: .song)
        _ = try await old.appendSlide(to: song.id, content: SlideContent(primary: "how sweet", secondary: "Ân điển lạ lùng"))
        try old.close()

        let new = try LibraryStore.open(at: url)
        #expect(Array(try await new.appliedMigrations().suffix(1)) == ["v7"])
        #expect(try await new.slides(of: song.id).map(\.content.primary) == ["how sweet"])
        #expect(try await new.search("an dien", limit: 5).map(\.presentationID) == [song.id])
        #expect(try await new.tableNames().contains("scriptureTranslation"))
        try new.close()
    }

    @Test func reopeningDoesNotRerunV7() async throws {
        let url = tempURL()
        let first = try LibraryStore.open(at: url)
        try first.close()
        let second = try LibraryStore.open(at: url)
        #expect(try await second.appliedMigrations().filter { $0 == "v7" }.count == 1)
        try second.close()
    }

    @Test func versesCascadeWithTheirTranslationAndKeysAreUnique() async throws {
        let store = try LibraryStore.inMemory()
        try await store.scriptureWrite { db in
            try db.execute(sql: """
                INSERT INTO scriptureTranslation (id, code, name, language, abbreviation, isPublicDomain, versificationID, verseCount, importedAt)
                VALUES ('T1', 'syn', 'Synthetic', 'en', 'SYN', 0, 'KJV', 1, ?)
                """, arguments: [Date()])
            try db.execute(sql: "INSERT INTO scriptureVerse (translationID, bookOrder, chapter, verse, text, textFolded) VALUES ('T1', 43, 3, 16, 'x', 'x')")
        }
        // The same position twice is refused.
        await #expect(throws: (any Error).self) {
            try await store.scriptureWrite { db in
                try db.execute(sql: "INSERT INTO scriptureVerse (translationID, bookOrder, chapter, verse, text, textFolded) VALUES ('T1', 43, 3, 16, 'y', 'y')")
            }
        }
        // Codes are unique ignoring case.
        await #expect(throws: (any Error).self) {
            try await store.scriptureWrite { db in
                try db.execute(sql: """
                    INSERT INTO scriptureTranslation (id, code, name, language, abbreviation, isPublicDomain, versificationID, verseCount, importedAt)
                    VALUES ('T2', 'SYN', 'Other', 'en', 'O', 0, 'KJV', 0, ?)
                    """, arguments: [Date()])
            }
        }
        try await store.scriptureWrite { db in try db.execute(sql: "DELETE FROM scriptureTranslation WHERE id = 'T1'") }
        let left = try await store.scriptureRead { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureVerse") }
        #expect(left == 0)
    }

    @Test func aFailedWriteRollsBackEverything() async throws {
        let store = try LibraryStore.inMemory()
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.scriptureWrite { db in
                try db.execute(sql: """
                    INSERT INTO scriptureTranslation (id, code, name, language, abbreviation, isPublicDomain, versificationID, verseCount, importedAt)
                    VALUES ('T1', 'syn', 'Synthetic', 'en', 'SYN', 0, 'KJV', 0, ?)
                    """, arguments: [Date()])
                throw Boom()
            }
        }
        #expect(try await store.scriptureRead { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureTranslation") } == 0)
    }

    @Test(arguments: [LibraryStore.SearchBackend.fts5, .like])
    func searchTableExistsOnlyWhenFTS5IsUsed(_ backend: LibraryStore.SearchBackend) async throws {
        let store = try LibraryStore.inMemory(forcing: backend)
        #expect(store.scriptureSearchUsesFTS5 == (backend == .fts5))
        let tables = try await store.tableNames()
        #expect(tables.contains("scriptureSearch") == (backend == .fts5))
    }

    /// The index is derived data: when it is missing at open (older file, or FTS5 was absent), it is rebuilt from the verses.
    @Test func missingSearchTableIsRebuiltFromVersesAtOpen() async throws {
        let url = tempURL()
        let first = try LibraryStore.open(at: url)
        try await first.scriptureWrite { db in
            try db.execute(sql: """
                INSERT INTO scriptureTranslation (id, code, name, language, abbreviation, isPublicDomain, versificationID, verseCount, importedAt)
                VALUES ('T1', 'syn', 'Synthetic', 'en', 'SYN', 0, 'KJV', 1, ?)
                """, arguments: [Date()])
            try db.execute(sql: "INSERT INTO scriptureVerse (translationID, bookOrder, chapter, verse, text, textFolded) VALUES ('T1', 43, 3, 16, 'Hello', 'hello')")
            try db.execute(sql: "DROP TABLE scriptureSearch")
        }
        try first.close()
        let second = try LibraryStore.open(at: url)
        let hits = try await second.scriptureRead { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM scriptureSearch WHERE scriptureSearch MATCH '\"hello\"*'")
        }
        #expect(hits == 1)
        try second.close()
    }

    @Test func oldSchemaStoreHasNoSearchTableAndDoesNotCrashAtOpen() async throws {
        let store = try LibraryStore.open(at: tempURL(), migratingUpTo: "v6")
        #expect(!(try await store.tableNames()).contains("scriptureSearch"))
        try store.close()
    }
}
