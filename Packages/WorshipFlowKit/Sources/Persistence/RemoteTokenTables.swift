// CUE-002b (item 5): the paired devices of the remote control server, in the church's library (schema v10). A row holds a
// salted SHA-256 hash of the token and never the token, so a copy of the library file cannot be used to control the show.
import Foundation
import GRDB

public struct RemoteTokenRecord: Sendable, Equatable {
    public var id: UUID
    public var label: String
    public var salt: Data
    public var hash: Data
    public var createdAt: Date
    public var lastUsed: Date?

    public init(id: UUID, label: String, salt: Data, hash: Data, createdAt: Date, lastUsed: Date?) {
        self.id = id
        self.label = label
        self.salt = salt
        self.hash = hash
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }
}

extension LibraryStore {
    /// Oldest first.
    public func remoteTokens() async throws -> [RemoteTokenRecord] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM remoteToken ORDER BY createdAt, rowid").compactMap { row in
                guard let id = UUID(uuidString: row["id"] as String) else { return nil }
                return RemoteTokenRecord(id: id, label: row["label"], salt: row["salt"], hash: row["hash"],
                                         createdAt: row["createdAt"], lastUsed: row["lastUsed"])
            }
        }
    }

    public func saveRemoteToken(_ record: RemoteTokenRecord) async throws {
        try await writer.write { db in
            try db.execute(sql: """
                INSERT INTO remoteToken (id, label, salt, hash, createdAt, lastUsed) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET label = excluded.label, salt = excluded.salt, hash = excluded.hash,
                                              createdAt = excluded.createdAt, lastUsed = excluded.lastUsed
                """, arguments: [record.id.uuidString, record.label, record.salt, record.hash, record.createdAt, record.lastUsed])
        }
    }

    public func touchRemoteToken(id: UUID, at date: Date) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE remoteToken SET lastUsed = ? WHERE id = ?", arguments: [date, id.uuidString])
        }
    }

    public func deleteRemoteToken(id: UUID) async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM remoteToken WHERE id = ?", arguments: [id.uuidString]) }
    }

    public func deleteAllRemoteTokens() async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM remoteToken") }
    }
}

extension LibraryStore {
    /// Column names of a table, for tests that check what is stored.
    func rawColumnNames(of table: String) async throws -> [String] {
        try await writer.read { db in try db.columns(in: table).map(\.name) }
    }
}
