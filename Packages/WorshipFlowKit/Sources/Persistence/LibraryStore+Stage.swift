// STAGE-001a: stage layouts and timers (schema v4). The built-in layout lives in code and is never stored.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    // MARK: Stage layouts (LIVE-01)

    /// Custom layouts in creation order. `StageLayout.standard` is not included.
    public func stageLayouts() async throws -> [StageLayout] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT definition FROM stageLayout ORDER BY createdAt, rowid")
                .map { try SettingsJSON.decode(StageLayout.self, from: $0) }
        }
    }

    /// Inserts or updates a layout by id. The built-in id throws `invalidReference`; a blank name throws `invalidName`.
    public func saveStageLayout(_ layout: StageLayout) async throws {
        guard layout.id != StageLayout.standardID else { throw StoreError.invalidReference }
        var layout = layout
        layout.name = try Self.validName(layout.name)
        let definition = try SettingsJSON.encode(layout)
        let (id, name) = (layout.id.dbText, layout.name)
        try await writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO stageLayout (id, name, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, definition = excluded.definition,
                    updatedAt = excluded.updatedAt
                """, arguments: [id, name, definition, now, now])
        }
    }

    /// The built-in id throws `invalidReference`; an unknown id throws `notFound`.
    public func deleteStageLayout(id: UUID) async throws {
        guard id != StageLayout.standardID else { throw StoreError.invalidReference }
        try await writer.write { db in
            try Self.requireExists(db, table: "stageLayout", id: id)
            try db.execute(sql: "DELETE FROM stageLayout WHERE id = ?", arguments: [id.dbText])
        }
    }

    // MARK: Timers (LIVE-02)

    /// In creation order.
    public func timers() async throws -> [ShowTimer] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT definition FROM showTimer ORDER BY createdAt, rowid")
                .map { try SettingsJSON.decode(ShowTimer.self, from: $0) }
        }
    }

    /// Inserts or updates a timer by id, including whether it is running. A blank name throws `invalidName`.
    public func saveTimer(_ timer: ShowTimer) async throws {
        var timer = timer
        timer.name = try Self.validName(timer.name)
        let definition = try SettingsJSON.encode(timer)
        let (id, name) = (timer.id.dbText, timer.name)
        try await writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO showTimer (id, name, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, definition = excluded.definition,
                    updatedAt = excluded.updatedAt
                """, arguments: [id, name, definition, now, now])
        }
    }

    /// An unknown id throws `notFound`.
    public func deleteTimer(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "showTimer", id: id)
            try db.execute(sql: "DELETE FROM showTimer WHERE id = ?", arguments: [id.dbText])
        }
    }
}
