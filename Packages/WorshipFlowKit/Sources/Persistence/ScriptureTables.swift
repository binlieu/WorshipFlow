// LIB-004b: the derived full-text index over scripture verses, and the narrow door `ScriptureStore` uses to reach the
// scripture tables through this store's one connection pool (ADR-0004 decision 2: one pool per file, never a second).
//
// `scriptureVerse.textFolded` is the source of truth for search, like `presentation.bodyFolded`. The FTS5 table is
// derived: created at open when FTS5 exists, rebuilt from `scriptureVerse` when missing, dropped when FTS5 is absent.
// Rows in it are only ever used through a join to `scriptureVerse`, so a stale row cannot produce a result.
import Foundation
import GRDB

enum ScriptureIndex {
    static let tableName = "scriptureSearch"

    static func prepare(_ db: Database, backend: LibraryStore.SearchBackend) throws {
        // A store opened with `migratingUpTo` an older version has no scripture tables: nothing to index.
        guard try db.tableExists("scriptureVerse") else { return }
        let exists = try db.tableExists(tableName)
        switch backend {
        case .fts5:
            guard !exists else { return }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE \(tableName) USING fts5(
                    textFolded, translationID UNINDEXED, bookOrder UNINDEXED, chapter UNINDEXED, verse UNINDEXED,
                    tokenize = 'unicode61 remove_diacritics 0')
                """)
            try db.execute(sql: """
                INSERT INTO \(tableName) (textFolded, translationID, bookOrder, chapter, verse)
                SELECT textFolded, translationID, bookOrder, chapter, verse FROM scriptureVerse
                """)
        case .like:
            if exists { try? db.execute(sql: "DROP TABLE \(tableName)") }
        }
    }
}

@_spi(ScriptureStore)
extension LibraryStore {
    /// True when the scripture search table exists and queries should use FTS5; false means `LIKE` on `textFolded`.
    public var scriptureSearchUsesFTS5: Bool { searchBackend == .fts5 }

    /// Reads through this store's pool. For `ScriptureStore` only.
    public func scriptureRead<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(body)
    }

    /// Runs `body` in one transaction on this store's pool: it commits when `body` returns and rolls back everything
    /// when it throws. For `ScriptureStore` only.
    public func scriptureWrite<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(body)
    }
}
