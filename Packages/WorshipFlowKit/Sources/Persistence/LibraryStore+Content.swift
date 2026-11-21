// SYS-001: libraries, presentations and slides. Each operation is one transaction.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    // MARK: Libraries

    public func createLibrary(name: String) async throws -> Library {
        let name = try Self.validName(name)
        return try await writer.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM library") ?? 0
            let now = Date()
            let record = LibraryRecord(id: UUID(), name: name, sortOrder: count, createdAt: now, updatedAt: now)
            try record.insert(db)
            return record.domain
        }
    }

    public func libraries() async throws -> [Library] {
        try await writer.read { db in
            try LibraryRecord.fetchAll(db, sql: "SELECT * FROM library ORDER BY sortOrder, rowid").map(\.domain)
        }
    }

    public func renameLibrary(id: UUID, to name: String) async throws {
        let name = try Self.validName(name)
        try await writer.write { db in
            try Self.requireExists(db, table: "library", id: id)
            try db.execute(sql: "UPDATE library SET name = ?, updatedAt = ? WHERE id = ?",
                           arguments: [name, Date(), id.dbText])
        }
    }

    /// Deletes the library, its presentations and their slides, and removes those presentations
    /// from playlists (the playlists stay, with dense order).
    public func deleteLibrary(id: UUID) async throws {
        let backend = searchBackend
        try await writer.write { db in
            try Self.requireExists(db, table: "library", id: id)
            let affected = try String.fetchAll(db, sql: """
                SELECT DISTINCT playlistID FROM playlistItem
                WHERE presentationID IN (SELECT id FROM presentation WHERE libraryID = ?)
                """, arguments: [id.dbText])
            if backend == .fts5 {
                try db.execute(sql: """
                    DELETE FROM \(SearchIndex.tableName)
                    WHERE presentationID IN (SELECT id FROM presentation WHERE libraryID = ?)
                    """, arguments: [id.dbText])
            }
            try db.execute(sql: "DELETE FROM library WHERE id = ?", arguments: [id.dbText])
            try Self.renumber(db, table: "library", parent: nil)
            for playlistID in affected {
                try Self.renumber(db, table: "playlistItem", parent: ("playlistID", playlistID))
            }
        }
    }

    // MARK: Presentations

    public func createPresentation(in libraryID: UUID, title: String, kind: PresentationKind) async throws -> Presentation {
        let title = try Self.validName(title)
        let backend = searchBackend
        return try await writer.write { db in
            try Self.requireExists(db, table: "library", id: libraryID)
            let now = Date()
            let record = PresentationRecord(
                id: UUID(), libraryID: libraryID, title: title, kind: kind,
                titleFolded: SearchFolding.fold(title), bodyFolded: "", createdAt: now, updatedAt: now)
            try record.insert(db)
            try SearchIndex.write(db, backend: backend, presentationID: record.id,
                                  titleFolded: record.titleFolded, bodyFolded: "")
            return record.domain
        }
    }

    /// Presentations in a library, ordered by folded title.
    public func presentations(in libraryID: UUID) async throws -> [Presentation] {
        try await writer.read { db in
            try PresentationRecord.fetchAll(
                db, sql: "SELECT * FROM presentation WHERE libraryID = ? ORDER BY titleFolded, rowid",
                arguments: [libraryID.dbText]).map(\.domain)
        }
    }

    public func renamePresentation(id: UUID, to title: String) async throws {
        let title = try Self.validName(title)
        let backend = searchBackend
        try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: id)
            try db.execute(sql: "UPDATE presentation SET title = ?, updatedAt = ? WHERE id = ?",
                           arguments: [title, Date(), id.dbText])
            try SearchIndex.reindex(db, backend: backend, presentationID: id)
        }
    }

    public func movePresentation(id: UUID, to libraryID: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: id)
            try Self.requireExists(db, table: "library", id: libraryID)
            try db.execute(sql: "UPDATE presentation SET libraryID = ?, updatedAt = ? WHERE id = ?",
                           arguments: [libraryID.dbText, Date(), id.dbText])
        }
    }

    /// Deletes the presentation and its slides and removes it from every playlist.
    public func deletePresentation(id: UUID) async throws {
        let backend = searchBackend
        try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: id)
            let affected = try String.fetchAll(
                db, sql: "SELECT DISTINCT playlistID FROM playlistItem WHERE presentationID = ?",
                arguments: [id.dbText])
            try SearchIndex.remove(db, backend: backend, presentationID: id)
            try db.execute(sql: "DELETE FROM presentation WHERE id = ?", arguments: [id.dbText])
            for playlistID in affected {
                try Self.renumber(db, table: "playlistItem", parent: ("playlistID", playlistID))
            }
        }
    }

    // MARK: Slides

    public func appendSlide(to presentationID: UUID, content: SlideContent) async throws -> Slide {
        let backend = searchBackend
        return try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: presentationID)
            let count = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM slide WHERE presentationID = ?", arguments: [presentationID.dbText]) ?? 0
            let now = Date()
            let record = SlideRecord(
                id: UUID(), presentationID: presentationID, sortOrder: count,
                primaryText: content.primary, secondaryText: content.secondary, notes: "",
                createdAt: now, updatedAt: now)
            try record.insert(db)
            try Self.touch(db, presentationID: presentationID, backend: backend)
            return record.domain
        }
    }

    public func slides(of presentationID: UUID) async throws -> [Slide] {
        try await writer.read { db in
            try SlideRecord.fetchAll(
                db, sql: "SELECT * FROM slide WHERE presentationID = ? ORDER BY sortOrder, rowid",
                arguments: [presentationID.dbText]).map(\.domain)
        }
    }

    /// Updates content and notes only; order and owner are unchanged.
    public func updateSlide(_ slide: Slide) async throws {
        let backend = searchBackend
        try await writer.write { db in
            guard let presentationID = try Self.presentationID(db, slideID: slide.id) else { throw StoreError.notFound }
            try db.execute(sql: """
                UPDATE slide SET primaryText = ?, secondaryText = ?, notes = ?, updatedAt = ? WHERE id = ?
                """, arguments: [slide.content.primary, slide.content.secondary, slide.notes, Date(), slide.id.dbText])
            try Self.touch(db, presentationID: presentationID, backend: backend)
        }
    }

    public func moveSlide(id: UUID, to index: Int) async throws {
        let backend = searchBackend
        try await writer.write { db in
            guard let presentationID = try Self.presentationID(db, slideID: id) else { throw StoreError.notFound }
            try Self.move(db, table: "slide", parentColumn: "presentationID", parentID: presentationID.dbText,
                          id: id, to: index)
            try Self.touch(db, presentationID: presentationID, backend: backend)
        }
    }

    public func deleteSlide(id: UUID) async throws {
        let backend = searchBackend
        try await writer.write { db in
            guard let presentationID = try Self.presentationID(db, slideID: id) else { throw StoreError.notFound }
            try db.execute(sql: "DELETE FROM slide WHERE id = ?", arguments: [id.dbText])
            try Self.renumber(db, table: "slide", parent: ("presentationID", presentationID.dbText))
            try Self.touch(db, presentationID: presentationID, backend: backend)
        }
    }

    // MARK: Helpers

    private static func presentationID(_ db: Database, slideID: UUID) throws -> UUID? {
        guard let text = try String.fetchOne(
            db, sql: "SELECT presentationID FROM slide WHERE id = ?", arguments: [slideID.dbText]) else { return nil }
        return UUID(uuidString: text)
    }

    /// Bumps `updatedAt` and refreshes the folded search text after a slide change.
    private static func touch(_ db: Database, presentationID: UUID, backend: SearchBackend) throws {
        try db.execute(sql: "UPDATE presentation SET updatedAt = ? WHERE id = ?",
                       arguments: [Date(), presentationID.dbText])
        try SearchIndex.reindex(db, backend: backend, presentationID: presentationID)
    }

    // MARK: Test and benchmark helper

    /// TEST AND BENCHMARK HELPER ONLY. Bulk-inserts `count` presentations (kind `.song`) with one
    /// slide per returned line, in a single transaction, computing folded text once per presentation.
    /// `make` is called with 0..<count before the transaction starts.
    public func importForTesting(libraryID: UUID, count: Int, _ make: (Int) -> (title: String, lines: [String])) async throws {
        let items = (0..<max(count, 0)).map(make)
        let backend = searchBackend
        try await writer.write { db in
            try Self.requireExists(db, table: "library", id: libraryID)
            let now = Date()
            for item in items {
                let record = PresentationRecord(
                    id: UUID(), libraryID: libraryID, title: item.title, kind: .song,
                    titleFolded: "", bodyFolded: "", createdAt: now, updatedAt: now)
                try record.insert(db)
                for (order, line) in item.lines.enumerated() {
                    try SlideRecord(id: UUID(), presentationID: record.id, sortOrder: order, primaryText: line,
                                    secondaryText: nil, notes: "", createdAt: now, updatedAt: now).insert(db)
                }
                try SearchIndex.write(db, backend: backend, presentationID: record.id,
                                      titleFolded: SearchFolding.fold(item.title),
                                      bodyFolded: SearchFolding.fold(item.lines.joined(separator: "\n")))
            }
        }
    }
}
