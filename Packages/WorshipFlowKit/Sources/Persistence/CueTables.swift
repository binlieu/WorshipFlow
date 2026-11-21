// CUE-002a: the narrow door `CueStore` uses to reach the cue tables through this store's one connection pool
// (ADR-0004 decision 2: one pool per file, never a second), and what a reflow does with a slide's actions.
import Foundation
import GRDB
import Domain

@_spi(CueStore)
extension LibraryStore {
    /// Reads through this store's pool. For `CueStore` only.
    public func cueRead<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.read(body)
    }

    /// Runs `body` in one transaction on this store's pool: it commits when `body` returns and rolls back everything
    /// when it throws. For `CueStore` only.
    public func cueWrite<T: Sendable>(_ body: @Sendable (Database) throws -> T) async throws -> T {
        try await writer.write(body)
    }
}

extension LibraryStore {
    /// A slide's stored actions, taken out before a reflow deletes the slide.
    struct SlideActionCarry {
        /// For each new slide in order: the row of the old slide whose words it kept, or nil.
        var rows: [Row?]
    }

    /// Which old slide's actions each new slide takes over. The matching is `Reflow.carryOver`'s own (same words, same
    /// section, first unused old slide), reached by handing it each old slide's position as its "notes" and reading the
    /// position back, so the two rules cannot drift apart. Empty when the store has no cue tables (older than v9).
    static func slideActionCarry(_ db: Database, presentationID: UUID, groups: [SlideGroup],
                                 results: [ReflowResult]) throws -> SlideActionCarry {
        guard try db.tableExists("cueSlideActions") else { return SlideActionCarry(rows: []) }
        let names = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let old = try SlideRecord.fetchAll(
            db, sql: "SELECT * FROM slide WHERE presentationID = ? ORDER BY sortOrder, rowid",
            arguments: [presentationID.dbText]).map(\.domain)
        let stored = Dictionary(try Row.fetchAll(db, sql: """
            SELECT a.* FROM cueSlideActions a JOIN slide s ON s.id = a.slideID WHERE s.presentationID = ?
            """, arguments: [presentationID.dbText]).map { ($0["slideID"] as String, $0) }, uniquingKeysWith: { first, _ in first })
        guard !stored.isEmpty else { return SlideActionCarry(rows: []) }
        let existing = old.enumerated().map { index, slide in
            ExistingSlide(sectionName: slide.groupID.flatMap { names[$0] }, content: SlideContent(primary: slide.content.primary),
                          notes: String(index))
        }
        let carry = Reflow.carryOver(from: existing, to: results)
        let rows: [Row?] = carry.notes.map { marker in
            guard let index = Int(marker), old.indices.contains(index) else { return nil }
            return stored[old[index].id.dbText]
        }
        return SlideActionCarry(rows: rows)
    }

    /// Writes the carried rows against the new slides, which `replaceContent` has just inserted in order.
    static func restoreSlideActions(_ db: Database, _ carry: SlideActionCarry, newSlideIDs: [UUID]) throws {
        for (index, row) in carry.rows.enumerated() {
            guard let row, newSlideIDs.indices.contains(index) else { continue }
            try db.execute(sql: """
                INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?)
                """, arguments: [newSlideIDs[index].dbText, row["definition"] as String, row["createdAt"] as DatabaseValue,
                                 row["updatedAt"] as DatabaseValue])
        }
    }
}
