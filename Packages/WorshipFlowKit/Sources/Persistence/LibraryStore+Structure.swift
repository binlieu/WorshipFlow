// SLIDE-003 / SLIDE-004: song sections, arrangements and reflowed content (schema v2).
import Foundation
import GRDB
import Domain

extension LibraryStore {
    // MARK: Groups

    /// Sections of a presentation in order.
    public func groups(of presentationID: UUID) async throws -> [SlideGroup] {
        try await writer.read { db in try Self.fetchGroups(db, presentationID: presentationID) }
    }

    /// Replaces every slide of the presentation with `results`. Sections are matched to existing
    /// groups by exact name so group identity (and therefore arrangements) survives an edit; new
    /// names create groups, vanished names delete theirs and drop them from arrangements. One
    /// group per distinct name, in order of first appearance. Slides without a section name stay
    /// ungrouped. Speaker notes of replaced slides are discarded.
    public func replaceContent(of presentationID: UUID, with results: [ReflowResult]) async throws {
        let backend = searchBackend
        try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: presentationID)
            let existing = try Self.fetchGroups(db, presentationID: presentationID)
            var idByName: [String: UUID] = [:]
            for group in existing where idByName[group.name] == nil { idByName[group.name] = group.id }

            var names: [String] = []
            for name in results.compactMap(\.sectionName) where !names.contains(name) { names.append(name) }
            var keptIDs: [String: UUID] = [:]
            for name in names { keptIDs[name] = idByName[name] ?? UUID() }
            let keep = Set(keptIDs.values)

            // Slides first, so nothing references a group that is about to go.
            try db.execute(sql: "DELETE FROM slide WHERE presentationID = ?", arguments: [presentationID.dbText])
            var arrangementsToClose = Set<String>()
            for group in existing where !keep.contains(group.id) {
                arrangementsToClose.formUnion(try String.fetchAll(
                    db, sql: "SELECT DISTINCT arrangementID FROM arrangementItem WHERE groupID = ?",
                    arguments: [group.id.dbText]))
                try db.execute(sql: "DELETE FROM arrangementItem WHERE groupID = ?", arguments: [group.id.dbText])
                try db.execute(sql: "DELETE FROM slideGroup WHERE id = ?", arguments: [group.id.dbText])
            }
            for arrangementID in arrangementsToClose { try Self.closeArrangementGaps(db, arrangementID: arrangementID) }

            let known = Set(existing.map(\.id))
            for (order, name) in names.enumerated() {
                guard let id = keptIDs[name] else { continue }
                if known.contains(id) {
                    try db.execute(sql: "UPDATE slideGroup SET sortOrder = ? WHERE id = ?", arguments: [order, id.dbText])
                } else {
                    try db.execute(sql: "INSERT INTO slideGroup (id, presentationID, name, sortOrder) VALUES (?, ?, ?, ?)",
                                   arguments: [id.dbText, presentationID.dbText, name, order])
                }
            }

            let now = Date()
            for (order, result) in results.enumerated() {
                let groupID = result.sectionName.flatMap { keptIDs[$0] }
                try SlideRecord(id: UUID(), presentationID: presentationID, sortOrder: order,
                                primaryText: result.content.primary, secondaryText: result.content.secondary,
                                notes: "", createdAt: now, updatedAt: now, groupID: groupID).insert(db)
            }
            try Self.touch(db, presentationID: presentationID, backend: backend)
        }
    }

    // MARK: Arrangements

    public func createArrangement(for presentationID: UUID, name: String, groupIDs: [UUID]) async throws -> Arrangement {
        let name = try Self.validName(name)
        return try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: presentationID)
            try Self.requireGroups(db, groupIDs, in: presentationID)
            let id = UUID()
            let now = Date()
            try db.execute(sql: """
                INSERT INTO arrangement (id, presentationID, name, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)
                """, arguments: [id.dbText, presentationID.dbText, name, now, now])
            try Self.writeItems(db, arrangementID: id, groupIDs: groupIDs)
            return Arrangement(id: id, presentationID: presentationID, name: name, groupIDs: groupIDs)
        }
    }

    public func arrangements(of presentationID: UUID) async throws -> [Arrangement] {
        try await writer.read { db in try Self.fetchArrangements(db, presentationID: presentationID) }
    }

    public func updateArrangement(id: UUID, name: String, groupIDs: [UUID]) async throws {
        let name = try Self.validName(name)
        try await writer.write { db in
            guard let presentation = try String.fetchOne(
                db, sql: "SELECT presentationID FROM arrangement WHERE id = ?", arguments: [id.dbText]),
                  let presentationID = UUID(uuidString: presentation) else { throw StoreError.notFound }
            try Self.requireGroups(db, groupIDs, in: presentationID)
            try db.execute(sql: "UPDATE arrangement SET name = ?, updatedAt = ? WHERE id = ?",
                           arguments: [name, Date(), id.dbText])
            try db.execute(sql: "DELETE FROM arrangementItem WHERE arrangementID = ?", arguments: [id.dbText])
            try Self.writeItems(db, arrangementID: id, groupIDs: groupIDs)
        }
    }

    /// Deletes the arrangement; playlist items that used it fall back to natural order.
    public func deleteArrangement(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "arrangement", id: id)
            try db.execute(sql: "DELETE FROM arrangement WHERE id = ?", arguments: [id.dbText])
        }
    }

    /// Slides in play order: natural order for a nil arrangement, else the arrangement's order.
    public func resolvedSlides(of presentationID: UUID, arrangementID: UUID?) async throws -> [Slide] {
        try await writer.read { db in try Self.resolve(db, presentationID: presentationID, arrangementID: arrangementID) }
    }

    // MARK: Playlist items

    /// Sets or clears (nil) the arrangement a playlist item plays with. It must belong to the
    /// item's presentation.
    public func setArrangement(_ arrangementID: UUID?, forPlaylistItem itemID: UUID) async throws {
        try await writer.write { db in
            guard let presentation = try String.fetchOne(
                db, sql: "SELECT presentationID FROM playlistItem WHERE id = ?", arguments: [itemID.dbText]) else {
                throw StoreError.notFound
            }
            if let arrangementID {
                guard let owner = try String.fetchOne(
                    db, sql: "SELECT presentationID FROM arrangement WHERE id = ?", arguments: [arrangementID.dbText])
                else { throw StoreError.notFound }
                guard owner == presentation else { throw StoreError.invalidReference }
            }
            try db.execute(sql: "UPDATE playlistItem SET arrangementID = ? WHERE id = ?",
                           arguments: [arrangementID?.dbText, itemID.dbText])
        }
    }

    /// The slides a playlist item shows, honouring its arrangement.
    public func slides(forPlaylistItem itemID: UUID) async throws -> [Slide] {
        try await writer.read { db in
            guard let row = try Row.fetchOne(
                db, sql: "SELECT presentationID, arrangementID FROM playlistItem WHERE id = ?",
                arguments: [itemID.dbText]),
                  let presentationID = UUID(uuidString: row["presentationID"] as String) else { throw StoreError.notFound }
            let arrangementID = (row["arrangementID"] as String?).flatMap(UUID.init(uuidString:))
            return try Self.resolve(db, presentationID: presentationID, arrangementID: arrangementID)
        }
    }

    // MARK: Helpers

    private static func fetchGroups(_ db: Database, presentationID: UUID) throws -> [SlideGroup] {
        try Row.fetchAll(db, sql: """
            SELECT id, name, sortOrder FROM slideGroup WHERE presentationID = ? ORDER BY sortOrder, rowid
            """, arguments: [presentationID.dbText]).compactMap { row in
            guard let id = UUID(uuidString: row["id"] as String) else { return nil }
            return SlideGroup(id: id, presentationID: presentationID, name: row["name"], sortOrder: row["sortOrder"])
        }
    }

    private static func fetchArrangements(_ db: Database, presentationID: UUID) throws -> [Arrangement] {
        try Row.fetchAll(db, sql: """
            SELECT id, name FROM arrangement WHERE presentationID = ? ORDER BY createdAt, rowid
            """, arguments: [presentationID.dbText]).compactMap { row in
            guard let id = UUID(uuidString: row["id"] as String) else { return nil }
            let groupIDs = try String.fetchAll(db, sql: """
                SELECT groupID FROM arrangementItem WHERE arrangementID = ? ORDER BY position
                """, arguments: [id.dbText]).compactMap(UUID.init(uuidString:))
            return Arrangement(id: id, presentationID: presentationID, name: row["name"], groupIDs: groupIDs)
        }
    }

    private static func resolve(_ db: Database, presentationID: UUID, arrangementID: UUID?) throws -> [Slide] {
        let slides = try SlideRecord.fetchAll(
            db, sql: "SELECT * FROM slide WHERE presentationID = ? ORDER BY sortOrder, rowid",
            arguments: [presentationID.dbText]).map(\.domain)
        guard let arrangementID else { return slides }
        guard let arrangement = try fetchArrangements(db, presentationID: presentationID)
            .first(where: { $0.id == arrangementID }) else { throw StoreError.notFound }
        let groups = try fetchGroups(db, presentationID: presentationID)
        return ArrangementResolver.order(slides: slides, groups: groups, arrangement: arrangement)
    }

    private static func requireGroups(_ db: Database, _ groupIDs: [UUID], in presentationID: UUID) throws {
        for id in Set(groupIDs) {
            let owner = try String.fetchOne(
                db, sql: "SELECT presentationID FROM slideGroup WHERE id = ?", arguments: [id.dbText])
            guard owner == presentationID.dbText else { throw StoreError.invalidReference }
        }
    }

    private static func writeItems(_ db: Database, arrangementID: UUID, groupIDs: [UUID]) throws {
        for (position, groupID) in groupIDs.enumerated() {
            try db.execute(sql: "INSERT INTO arrangementItem (arrangementID, position, groupID) VALUES (?, ?, ?)",
                           arguments: [arrangementID.dbText, position, groupID.dbText])
        }
    }

    /// Rewrites positions as 0...n-1 after rows were removed from the middle.
    private static func closeArrangementGaps(_ db: Database, arrangementID: String) throws {
        let groups = try String.fetchAll(
            db, sql: "SELECT groupID FROM arrangementItem WHERE arrangementID = ? ORDER BY position",
            arguments: [arrangementID])
        try db.execute(sql: "DELETE FROM arrangementItem WHERE arrangementID = ?", arguments: [arrangementID])
        for (position, groupID) in groups.enumerated() {
            try db.execute(sql: "INSERT INTO arrangementItem (arrangementID, position, groupID) VALUES (?, ?, ?)",
                           arguments: [arrangementID, position, groupID])
        }
    }
}
