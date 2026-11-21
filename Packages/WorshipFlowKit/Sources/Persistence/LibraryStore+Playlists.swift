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
            // Written without the v8 columns (kind defaults to 'presentation'), so it also works on a store opened at an older schema.
            let id = UUID()
            try db.execute(sql: "INSERT INTO playlistItem (id, playlistID, presentationID, sortOrder, createdAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id.dbText, playlistID.dbText, presentationID.dbText, count, Date()])
            try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [Date(), playlistID.dbText])
            return PlaylistItem(id: id, playlistID: playlistID, presentationID: presentationID,
                                title: title, sortOrder: count)
        }
    }

    public func playlistItems(of playlistID: UUID) async throws -> [PlaylistItem] {
        try await writer.read { db in
            // A store opened at a schema older than v8 has no kind or payload: its items are all presentations.
            let hasKinds = try db.columns(in: "playlistItem").contains { $0.name == "kind" }
            let rows = try Row.fetchAll(db, sql: """
                SELECT i.id AS id, i.playlistID AS playlistID, i.presentationID AS presentationID,
                       i.sortOrder AS sortOrder, i.arrangementID AS arrangementID, p.title AS title,
                       \(hasKinds ? "i.kind" : "'presentation'") AS kind, \(hasKinds ? "i.payload" : "NULL") AS payload
                FROM playlistItem i LEFT JOIN presentation p ON p.id = i.presentationID
                WHERE i.playlistID = ? ORDER BY i.sortOrder, i.rowid
                """, arguments: [playlistID.dbText])
            return rows.compactMap { row -> PlaylistItem? in
                guard let id = UUID(uuidString: row["id"] as String),
                      let playlist = UUID(uuidString: row["playlistID"] as String) else { return nil }
                let kind = PlaylistItemKind(storedKind: row["kind"] as String? ?? "presentation", payload: row["payload"] as String?)
                let presentation = (row["presentationID"] as String?).flatMap(UUID.init(uuidString:))
                var title: String
                switch kind {
                case .presentation:
                    guard presentation != nil, let t = row["title"] as String? else { return nil }
                    title = t
                case .header(let label): title = label
                case .countdown(let spec): title = spec.label
                }
                return PlaylistItem(id: id, playlistID: playlist, presentationID: presentation ?? PlaylistItem.noPresentationID,
                                    title: title, sortOrder: row["sortOrder"],
                                    arrangementID: (row["arrangementID"] as String?).flatMap(UUID.init(uuidString:)), kind: kind)
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

    // MARK: Headers and countdowns (UI-002)

    /// Appends a section header (a label such as "Worship") to the end of a playlist.
    @discardableResult
    public func addPlaylistHeader(_ label: String, to playlistID: UUID) async throws -> PlaylistItem {
        let label = try Self.validName(label)
        return try await addNonPresentation(.header(label: label), title: label, to: playlistID)
    }

    /// Appends a countdown to the end of a playlist.
    @discardableResult
    public func addPlaylistCountdown(_ spec: CountdownSpec, to playlistID: UUID) async throws -> PlaylistItem {
        try await addNonPresentation(.countdown(spec), title: spec.label, to: playlistID)
    }

    /// Changes a header's label or a countdown's settings. A presentation item cannot be changed this way.
    public func updatePlaylistItem(id: UUID, kind: PlaylistItemKind) async throws {
        guard case .presentation = kind else {
            let stored = kind.stored
            try await writer.write { db in
                guard try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlistItem WHERE id = ? AND kind != 'presentation'", arguments: [id.dbText]) == 1 else {
                    throw StoreError.notFound
                }
                try db.execute(sql: "UPDATE playlistItem SET kind = ?, payload = ? WHERE id = ?", arguments: [stored.kind, stored.payload, id.dbText])
            }
            return
        }
        throw StoreError.notFound
    }

    private func addNonPresentation(_ kind: PlaylistItemKind, title: String, to playlistID: UUID) async throws -> PlaylistItem {
        let stored = kind.stored
        return try await writer.write { db in
            try Self.requireExists(db, table: "playlist", id: playlistID)
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM playlistItem WHERE playlistID = ?", arguments: [playlistID.dbText]) ?? 0
            let record = PlaylistItemRecord(id: UUID(), playlistID: playlistID, presentationID: nil, sortOrder: count,
                                            createdAt: Date(), kind: stored.kind, payload: stored.payload)
            try record.insert(db)
            try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [Date(), playlistID.dbText])
            return PlaylistItem(id: record.id, playlistID: playlistID, presentationID: PlaylistItem.noPresentationID, title: title,
                                sortOrder: count, kind: kind)
        }
    }
}
