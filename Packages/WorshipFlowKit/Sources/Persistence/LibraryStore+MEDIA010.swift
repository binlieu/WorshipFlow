// MEDIA-010: a slide's own background and the hot folders, kept in the library's `appState` table as JSON. No migration: an
// earlier test pins the library at ten migrations, and neither value needs a column of its own. Rows of other tables are
// never touched. A slide's background is stored per presentation as `{"<slide id>": <MediaSelection>}`; a slide that was
// deleted leaves its entry behind until the presentation is deleted or the slide's entry is written again (harmless).
import Foundation
import GRDB
import Domain

extension LibraryStore {
    static func backgroundsKey(_ presentationID: UUID) -> String { "slideBackgrounds.\(presentationID.uuidString)" }
    static let hotFoldersKey = "media.hotFolders"

    /// Column names of a table, for tests and diagnostics.
    public func columnNames(of table: String) async throws -> [String] {
        try await writer.read { db in try db.columns(in: table).map(\.name) }
    }

    // MARK: Slide backgrounds

    static func backgrounds(_ db: Database, _ presentationID: UUID) -> [String: MediaSelection] {
        guard let text = try? String.fetchOne(db, sql: "SELECT value FROM appState WHERE key = ?", arguments: [backgroundsKey(presentationID)]),
              let data = text.data(using: .utf8) else { return [:] }
        // An unreadable value reads as no backgrounds rather than making the slide list fail to load.
        return (try? JSONDecoder().decode([String: MediaSelection].self, from: data)) ?? [:]
    }

    static func applyBackgrounds(_ slides: [Slide], _ db: Database, _ presentationID: UUID) -> [Slide] {
        let stored = backgrounds(db, presentationID)
        guard !stored.isEmpty else { return slides }
        return slides.map { slide in
            var copy = slide
            copy.content.background = stored[slide.id.dbText]
            return copy
        }
    }

    /// Sets or removes one slide's entry, inside the caller's transaction. Writes nothing when nothing changes.
    static func writeBackground(_ db: Database, presentationID: UUID, slideID: UUID, _ selection: MediaSelection?) throws {
        var stored = backgrounds(db, presentationID)
        guard stored[slideID.dbText] != selection else { return }
        stored[slideID.dbText] = selection
        let key = backgroundsKey(presentationID)
        if stored.isEmpty {
            try db.execute(sql: "DELETE FROM appState WHERE key = ?", arguments: [key])
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(stored), as: UTF8.self)
        try db.execute(sql: """
            INSERT INTO appState (key, value, updatedAt) VALUES (?, ?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value, updatedAt = excluded.updatedAt
            """, arguments: [key, text, Date()])
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
