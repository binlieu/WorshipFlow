// SYS-001: playlists and their ordered items.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    public func createPlaylist(name: String) async throws -> Playlist {
        let name = try Self.validName(name)
        return try await writer.write { db in
            let now = Date()
            let record = PlaylistRecord(id: UUID(), name: name, createdAt: now, updatedAt: now)
            try record.insert(db)
            return record.domain
        }
    }

    public func playlists() async throws -> [Playlist] {
        try await writer.read { db in
            try PlaylistRecord.fetchAll(db, sql: "SELECT * FROM playlist ORDER BY createdAt, rowid").map(\.domain)
        }
    }

    public func renamePlaylist(id: UUID, to name: String) async throws {
        let name = try Self.validName(name)
        try await writer.write { db in
            try Self.requireExists(db, table: "playlist", id: id)
            try db.execute(sql: "UPDATE playlist SET name = ?, updatedAt = ? WHERE id = ?",
                           arguments: [name, Date(), id.dbText])
        }
    }

    public func deletePlaylist(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "playlist", id: id)
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [id.dbText])
        }
    }

    /// Appends a presentation to the end of a playlist. The same presentation may appear many times.
    public func addPresentation(_ presentationID: UUID, to playlistID: UUID) async throws -> PlaylistItem {
        try await writer.write { db in
            try Self.requireExists(db, table: "playlist", id: playlistID)
            guard let title = try String.fetchOne(
                db, sql: "SELECT title FROM presentation WHERE id = ?", arguments: [presentationID.dbText]) else {
                throw StoreError.notFound
            }
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM playlistItem WHERE playlistID = ?", arguments: [playlistID.dbText]) ?? 0
            let record = PlaylistItemRecord(id: UUID(), playlistID: playlistID, presentationID: presentationID,
                                            sortOrder: count, createdAt: Date())
            try record.insert(db)
            try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [Date(), playlistID.dbText])
            return PlaylistItem(id: record.id, playlistID: playlistID, presentationID: presentationID,
                                title: title, sortOrder: count)
        }
    }

    public func playlistItems(of playlistID: UUID) async throws -> [PlaylistItem] {
        try await writer.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT i.id AS id, i.playlistID AS playlistID, i.presentationID AS presentationID,
                       i.sortOrder AS sortOrder, i.arrangementID AS arrangementID, p.title AS title
                FROM playlistItem i JOIN presentation p ON p.id = i.presentationID
                WHERE i.playlistID = ? ORDER BY i.sortOrder, i.rowid
                """, arguments: [playlistID.dbText])
            return rows.compactMap { row -> PlaylistItem? in
                guard let id = UUID(uuidString: row["id"] as String),
                      let playlist = UUID(uuidString: row["playlistID"] as String),
                      let presentation = UUID(uuidString: row["presentationID"] as String) else { return nil }
                return PlaylistItem(id: id, playlistID: playlist, presentationID: presentation,
                                    title: row["title"], sortOrder: row["sortOrder"],
                                    arrangementID: (row["arrangementID"] as String?).flatMap(UUID.init(uuidString:)))
            }
        }
    }

    public func movePlaylistItem(id: UUID, to index: Int) async throws {
        try await writer.write { db in
            guard let playlistID = try String.fetchOne(
                db, sql: "SELECT playlistID FROM playlistItem WHERE id = ?", arguments: [id.dbText]) else {
                throw StoreError.notFound
            }
            try Self.move(db, table: "playlistItem", parentColumn: "playlistID", parentID: playlistID, id: id, to: index)
        }
    }

    public func removePlaylistItem(id: UUID) async throws {
        try await writer.write { db in
            guard let playlistID = try String.fetchOne(
                db, sql: "SELECT playlistID FROM playlistItem WHERE id = ?", arguments: [id.dbText]) else {
                throw StoreError.notFound
            }
            try db.execute(sql: "DELETE FROM playlistItem WHERE id = ?", arguments: [id.dbText])
            try Self.renumber(db, table: "playlistItem", parent: ("playlistID", playlistID))
        }
    }
}
