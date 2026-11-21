// MEDIA-010: the hot folders, kept in the library's `appState` table as JSON (no table of their own). A slide's own background
// moved into the slide row in FIX-G (migration v11, see `Schema`). Rows of other tables are never touched.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    static let hotFoldersKey = "media.hotFolders"

    /// Column names of a table, for tests and diagnostics.
    public func columnNames(of table: String) async throws -> [String] {
        try await writer.read { db in try db.columns(in: table).map(\.name) }
    }

    /// Keys of `appState` that start with `prefix`, for tests and diagnostics.
    public func stateKeys(prefix: String) async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT key FROM appState WHERE substr(key, 1, ?) = ? ORDER BY key",
                                arguments: [prefix.count, prefix])
        }
    }

    /// How many slides have their own background, for tests and diagnostics.
    public func slideBackgroundCount() async throws -> Int {
        try await writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM slide WHERE background IS NOT NULL") ?? 0 }
    }

    // MARK: Slide backgrounds in use

    /// The slides, in every presentation, that have the bin item `assetID` as their own background.
    public func slidesUsingBackground(of assetID: UUID) async throws -> [SlideBackgroundUse] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT s.presentationID AS presentationID, p.title AS title, s.sortOrder AS sortOrder, s.primaryText AS words
                FROM slide s JOIN presentation p ON p.id = s.presentationID
                WHERE s.background IS NOT NULL AND instr(s.background, ?) > 0
                ORDER BY p.title COLLATE NOCASE, p.id, s.sortOrder, s.rowid
                """, arguments: ["\"assetID\":\"\(assetID.uuidString)\""]).compactMap { row in
                guard let id = UUID(uuidString: row["presentationID"] as String) else { return nil }
                let words = (row["words"] as String).split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
                return SlideBackgroundUse(presentationID: id, presentationTitle: row["title"], slideNumber: (row["sortOrder"] as Int) + 1, words: words)
            }
        }
    }

    // MARK: Hot folders

    private struct StoredFolder: Codable {
        var id: UUID
        var name: String
        var path: String
        var bookmark: Data?
    }

    private func readFolders(_ db: Database) -> [StoredFolder] {
        guard let text = try? String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [Self.hotFoldersKey]),
              let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([StoredFolder].self, from: data)) ?? []
    }

    private static func writeFolders(_ db: Database, _ folders: [StoredFolder]) throws {
        if folders.isEmpty {
            try db.execute(sql: "DELETE FROM appState WHERE key = ?", arguments: [hotFoldersKey])
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(folders), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO appState (key, value, updatedAt) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
            """, arguments: [hotFoldersKey, text, Date()])
    }

    /// The hot folders in the order they were added.
    public func mediaFolders() async throws -> [HotFolder] {
        try await writer.read { [self] db in
            readFolders(db).map { HotFolder(id: $0.id, name: $0.name, path: $0.path, bookmark: $0.bookmark) }
        }
    }

    /// Adds a folder or updates its name, path and bookmark. An edited folder keeps its place in the list.
    public func saveMediaFolder(_ folder: HotFolder) async throws {
        try await writer.write { [self] db in
            var all = readFolders(db)
            let stored = StoredFolder(id: folder.id, name: folder.name, path: folder.path, bookmark: folder.bookmark)
            if let i = all.firstIndex(where: { $0.id == folder.id }) { all[i] = stored } else { all.append(stored) }
            try Self.writeFolders(db, all)
        }
    }

    /// Forgets the folder. Never touches the folder or its files.
    public func removeMediaFolder(id: UUID) async throws {
        try await writer.write { [self] db in
            try Self.writeFolders(db, readFolders(db).filter { $0.id != id })
        }
    }
}
