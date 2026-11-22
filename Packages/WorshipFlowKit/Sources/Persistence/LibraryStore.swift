// SYS-001: GRDB-backed library store (ADR-0004).
import Foundation
import GRDB
import Domain

public final class LibraryStore: Sendable {
    enum SearchBackend: Sendable, Equatable {
        case fts5
        case like
    }

    // GRDB's DatabaseWriter is Sendable and serialises access itself.
    let writer: any DatabaseWriter
    let searchBackend: SearchBackend
    /// LIB-005: maps media paths kept relative to the library's folder (nil for an in-memory store). See `MediaPathMapper`.
    let mediaPaths: MediaPathMapper?

    private init(writer: any DatabaseWriter, searchBackend: SearchBackend, mediaPaths: MediaPathMapper?) {
        self.writer = writer
        self.searchBackend = searchBackend
        self.mediaPaths = mediaPaths
    }

    // MARK: Opening

    /// An in-memory store (a single connection), for tests and previews.
    public static func inMemory() throws -> LibraryStore {
        try inMemory(forcing: nil)
    }

    /// Internal: lets tests exercise the `LIKE` search path even where FTS5 exists.
    static func inMemory(forcing backend: SearchBackend?) throws -> LibraryStore {
        let queue = try DatabaseQueue(configuration: makeConfiguration())
        return try finishOpening(writer: queue, upTo: nil, forcing: backend)
    }

    /// Opens (creating directories and file if needed) and migrates to the latest schema.
    public static func open(at url: URL) throws -> LibraryStore {
        try open(at: url, upTo: nil, forcing: nil)
    }

    /// Opens and migrates only up to the named migration. Used by migration tests.
    public static func open(at url: URL, migratingUpTo migration: String) throws -> LibraryStore {
        try open(at: url, upTo: migration, forcing: nil)
    }

    static func open(at url: URL, upTo migration: String?, forcing backend: SearchBackend?) throws -> LibraryStore {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // FIX-H item 14: a library last opened by a newer build is looked at read-only first and refused before anything can be written.
        if let newer = newerMigration(in: url) { throw newer }
        // One DatabasePool per file, kept for the life of the store (ADR-0004 decision 2).
        let pool = try DatabasePool(path: url.path, configuration: makeConfiguration())
        return try finishOpening(writer: pool, upTo: migration, forcing: backend,
                                 mediaPaths: MediaPathMapper(libraryFolder: url.deletingLastPathComponent()))
    }

    /// Reads the file's migration history without writing to it. Nil for a new file, a file that cannot be read this way (the normal
    /// open then reports it as before) or a history this build knows entirely.
    private static func newerMigration(in url: URL) -> LibraryFromNewerBuildError? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var config = Configuration()
        config.readonly = true
        guard let queue = try? DatabaseQueue(path: url.path, configuration: config) else { return nil }
        let known = Schema.makeMigrator().migrations
        let applied: [String] = (try? queue.read { db in
            try db.tableExists("grdb_migrations") ? try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") : []
        }) ?? []
        guard let found = applied.last(where: { !known.contains($0) }), let latest = known.last else { return nil }
        return LibraryFromNewerBuildError(found: found, known: latest)
    }

    private static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            // ADR-0004 decision 3, set explicitly on every connection.
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        return config
    }

    private static func finishOpening(writer: any DatabaseWriter, upTo migration: String?,
                                      forcing forced: SearchBackend?, mediaPaths: MediaPathMapper? = nil) throws -> LibraryStore {
        let migrator = Schema.makeMigrator()
        if let migration {
            guard migrator.migrations.contains(migration) else { throw StoreError.unknownMigration(migration) }
            try migrator.migrate(writer, upTo: migration)
        } else {
            try migrator.migrate(writer)
        }
        let available: SearchBackend = try writer.write { db in
            try SearchIndex.fts5IsAvailable(db) ? .fts5 : .like
        }
        let backend = forced ?? available
        try writer.write { db in
            try SearchIndex.prepare(db, backend: backend)
            try ScriptureIndex.prepare(db, backend: backend)
        }
        return LibraryStore(writer: writer, searchBackend: backend, mediaPaths: mediaPaths)
    }

    /// Closes the connections. Calls made afterwards throw.
    public func close() throws {
        try writer.close()
    }

    // MARK: Introspection

    public func tableNames() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        }
    }

    public func appliedMigrations() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid")
        }
    }

    // MARK: App state (NFR-06)

    public func state(for key: String) async throws -> String? {
        try await writer.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [key])
        }
    }

    /// Stores `value` under `key`; `nil` removes the key.
    public func setState(_ value: String?, for key: String) async throws {
        try await writer.write { db in
            if let value {
                try db.execute(sql: """
                    INSERT INTO appState (key, value, updatedAt) VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
                    """, arguments: [key, value, Date()])
            } else {
                try db.execute(sql: "DELETE FROM appState WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: Shared helpers

    static func validName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        return trimmed
    }

    static func exists(_ db: Database, table: String, id: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM \(table) WHERE id = ?)", arguments: [id.dbText]) ?? false
    }

    static func requireExists(_ db: Database, table: String, id: UUID) throws {
        guard try exists(db, table: table, id: id) else { throw StoreError.notFound }
    }

    /// Rewrites `sortOrder` as 0...n-1 in the given id order. `table` is a fixed internal name.
    static func writeOrder(_ db: Database, table: String, ids: [String]) throws {
        for (index, id) in ids.enumerated() {
            try db.execute(sql: "UPDATE \(table) SET sortOrder = ? WHERE id = ? AND sortOrder <> ?",
                           arguments: [index, id, index])
        }
    }

    /// Closes gaps in `sortOrder` for one parent (or the whole table when `parent` is nil).
    static func renumber(_ db: Database, table: String, parent: (column: String, id: String)?) throws {
        let ids: [String]
        if let parent {
            ids = try String.fetchAll(db, sql: "SELECT id FROM \(table) WHERE \(parent.column) = ? ORDER BY sortOrder, rowid",
                                      arguments: [parent.id])
        } else {
            ids = try String.fetchAll(db, sql: "SELECT id FROM \(table) ORDER BY sortOrder, rowid")
        }
        try writeOrder(db, table: table, ids: ids)
    }

    /// Moves one row to `index` (clamped) among its siblings and keeps `sortOrder` dense.
    static func move(_ db: Database, table: String, parentColumn: String, parentID: String,
                     id: UUID, to index: Int) throws {
        var ids = try String.fetchAll(
            db, sql: "SELECT id FROM \(table) WHERE \(parentColumn) = ? ORDER BY sortOrder, rowid",
            arguments: [parentID])
        guard let from = ids.firstIndex(of: id.dbText) else { throw StoreError.notFound }
        let moving = ids.remove(at: from)
        ids.insert(moving, at: min(max(index, 0), ids.count))
        try writeOrder(db, table: table, ids: ids)
    }
}
