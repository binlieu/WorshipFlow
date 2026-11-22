// TESTDATA-001: bulk loading of a library for performance tests. Each call is ONE transaction, built from the same rules the app's
// own import uses (`replaceContent` for the slides and sections), and is safe to repeat: a title already in the library is skipped.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    /// One song to load: its title and its slides as the import sheet would have split them.
    public struct SongSpec: Sendable, Equatable {
        public var title: String
        public var results: [ReflowResult]
        public init(title: String, results: [ReflowResult]) { self.title = title; self.results = results }
    }

    public struct SongBatchResult: Sendable, Equatable {
        public var libraryID: UUID
        public var libraryCreated: Bool
        public var added: [Presentation]
        public var skippedTitles: [String]
        public var slidesAdded: Int
    }

    /// Adds `songs` to the library called `libraryName` (created, of kind songs, when there is none) in one transaction. A song whose
    /// title is already in that library is skipped. A song with no slides is refused and nothing is written.
    public func addSongBatch(toLibraryNamed libraryName: String, songs: [SongSpec]) async throws -> SongBatchResult {
        let libraryName = try Self.validName(libraryName)
        let named = try songs.map { (spec: $0, title: try Self.validName($0.title)) }
        guard named.allSatisfy({ !$0.spec.results.isEmpty }) else { throw StoreError.invalidReference }
        let backend = searchBackend
        return try await writer.write { db in
            let now = Date()
            var created = false
            let libraryID: UUID
            if let found = try LibraryRecord.fetchAll(db, sql: "SELECT * FROM library WHERE name = ? ORDER BY sortOrder, rowid", arguments: [libraryName]).first {
                libraryID = found.id
            } else {
                let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM library") ?? 0
                let record = LibraryRecord(id: UUID(), name: libraryName, sortOrder: count, createdAt: now, updatedAt: now, kind: .songs)
                try record.insert(db)
                libraryID = record.id
                created = true
            }
            var known = Set(try String.fetchAll(db, sql: "SELECT title FROM presentation WHERE libraryID = ?", arguments: [libraryID.dbText]))
            var added: [Presentation] = [], skipped: [String] = [], slides = 0
            for (spec, title) in named {
                if known.contains(title) { skipped.append(title); continue }
                known.insert(title)
                let record = PresentationRecord(id: UUID(), libraryID: libraryID, title: title, kind: .song,
                                                titleFolded: SearchFolding.fold(title), bodyFolded: "", createdAt: now, updatedAt: now)
                try record.insert(db)
                try SearchIndex.write(db, backend: backend, presentationID: record.id, titleFolded: record.titleFolded, bodyFolded: "")
                try Self.replaceContent(db, backend: backend, presentationID: record.id, results: spec.results)
                added.append(record.domain)
                slides += spec.results.count
            }
            return SongBatchResult(libraryID: libraryID, libraryCreated: created, added: added, skippedTitles: skipped, slidesAdded: slides)
        }
    }

    /// The migrations this build knows that the file at `url` has not applied yet, read without writing to it. Empty for a file that is
    /// up to date; every migration for a file that does not exist. Lets a tool refuse to migrate somebody's library by opening it.
    public static func pendingMigrations(at url: URL) -> [String] {
        let known = Schema.makeMigrator().migrations
        guard FileManager.default.fileExists(atPath: url.path) else { return known }
        var config = Configuration()
        config.readonly = true
        guard let queue = try? DatabaseQueue(path: url.path, configuration: config) else { return known }
        let applied = Set((try? queue.read { db in
            try db.tableExists("grdb_migrations") ? try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations") : []
        }) ?? [])
        return known.filter { !applied.contains($0) }
    }
}
