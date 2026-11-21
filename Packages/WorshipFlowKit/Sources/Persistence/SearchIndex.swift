// SYS-001: folded search columns and the optional FTS5 index (ADR-0004 decisions 8 and 9).
// The folded columns on `presentation` are the source of truth. The FTS5 table is derived data:
// it is created at open when FTS5 exists, rebuilt from those columns when missing, and dropped
// when FTS5 is absent so it can never go stale.
import Foundation
import GRDB
import Domain

enum SearchIndex {
    static let tableName = "presentationSearch"

    static func fts5IsAvailable(_ db: Database) throws -> Bool {
        do {
            try db.execute(sql: "CREATE VIRTUAL TABLE temp.wf_fts5_probe USING fts5(x)")
            try db.execute(sql: "DROP TABLE temp.wf_fts5_probe")
            return true
        } catch {
            return false
        }
    }

    static func prepare(_ db: Database, backend: LibraryStore.SearchBackend) throws {
        let exists = try db.tableExists(tableName)
        switch backend {
        case .fts5:
            guard !exists else { return }
            try db.execute(sql: """
                CREATE VIRTUAL TABLE \(tableName) USING fts5(
                    title, body, presentationID UNINDEXED, tokenize = 'unicode61 remove_diacritics 0')
                """)
            try db.execute(sql: """
                INSERT INTO \(tableName) (title, body, presentationID)
                SELECT titleFolded, bodyFolded, id FROM presentation
                """)
        case .like:
            if exists { try? db.execute(sql: "DROP TABLE \(tableName)") }
        }
    }

    /// True once migration v5 has added `slide.objects`.
    static func slideHasObjectsColumn(_ db: Database) throws -> Bool {
        try db.columns(in: "slide").contains { $0.name == "objects" }
    }

    /// Recomputes folded title and slide text for one presentation. Call inside the same
    /// transaction as the change that made it stale.
    static func reindex(_ db: Database, backend: LibraryStore.SearchBackend, presentationID: UUID) throws {
        guard let title = try String.fetchOne(
            db, sql: "SELECT title FROM presentation WHERE id = ?", arguments: [presentationID.dbText]) else { return }
        // Text boxes (v5) are searched like lyrics. Older stores have no column.
        let columns = try slideHasObjectsColumn(db) ? "primaryText, secondaryText, objects" : "primaryText, secondaryText"
        let rows = try Row.fetchAll(
            db, sql: "SELECT \(columns) FROM slide WHERE presentationID = ? ORDER BY sortOrder",
            arguments: [presentationID.dbText])
        let text = rows.map { row -> String in
            let primary: String = row["primaryText"]
            let secondary: String? = row["secondaryText"]
            var line = primary + "\n" + (secondary ?? "")
            if row.hasColumn("objects"), let json: String = row["objects"] {
                line += "\n" + SlideObjectsJSON.searchableText(SlideObjectsJSON.decode(json))
            }
            return line
        }.joined(separator: "\n")
        try write(db, backend: backend, presentationID: presentationID,
                  titleFolded: SearchFolding.fold(title), bodyFolded: SearchFolding.fold(text))
    }

    static func write(_ db: Database, backend: LibraryStore.SearchBackend, presentationID: UUID,
                      titleFolded: String, bodyFolded: String) throws {
        try db.execute(sql: "UPDATE presentation SET titleFolded = ?, bodyFolded = ? WHERE id = ?",
                       arguments: [titleFolded, bodyFolded, presentationID.dbText])
        if backend == .fts5 {
            try db.execute(sql: "DELETE FROM \(tableName) WHERE presentationID = ?", arguments: [presentationID.dbText])
            try db.execute(sql: "INSERT INTO \(tableName) (title, body, presentationID) VALUES (?, ?, ?)",
                           arguments: [titleFolded, bodyFolded, presentationID.dbText])
        }
    }

    static func remove(_ db: Database, backend: LibraryStore.SearchBackend, presentationID: UUID) throws {
        if backend == .fts5 {
            try db.execute(sql: "DELETE FROM \(tableName) WHERE presentationID = ?", arguments: [presentationID.dbText])
        }
    }
}

extension LibraryStore {
    /// Folded search over titles and slide text. All terms are required; the last term matches
    /// as a prefix. Presentations whose title contains every term rank before lyric-only matches.
    /// The query is folded with `SearchFolding` and only ever passed as a bound parameter.
    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let terms = SearchFolding.fold(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty, limit > 0 else { return [] }
        let backend = searchBackend
        return try await writer.read { db in
            let rows: (title: [Row], all: [Row])
            switch backend {
            case .fts5:
                // Terms are alphanumeric after folding, so quoting them is always well-formed FTS5.
                let all = terms.enumerated().map { index, term in
                    "\"\(term)\"" + (index == terms.count - 1 ? "*" : "")
                }.joined(separator: " ")
                let sql = """
                    SELECT p.id AS id, p.title AS title FROM presentationSearch
                    JOIN presentation p ON p.id = presentationSearch.presentationID
                    WHERE presentationSearch MATCH ? ORDER BY rank, p.titleFolded LIMIT ?
                    """
                let titleRows = try Row.fetchAll(db, sql: sql, arguments: ["title : (\(all))", limit])
                let allRows = try Row.fetchAll(db, sql: sql, arguments: [all, limit + titleRows.count])
                rows = (titleRows, allRows)
            case .like:
                func conditions(_ haystack: String) -> (String, [String]) {
                    let clause = terms.indices.map { _ in "(\(haystack)) LIKE ?" }.joined(separator: " AND ")
                    let patterns = terms.enumerated().map { index, term in
                        "% " + term + (index == terms.count - 1 ? "%" : " %")
                    }
                    return (clause, patterns)
                }
                func run(_ haystack: String, _ count: Int) throws -> [Row] {
                    let (clause, patterns) = conditions(haystack)
                    var arguments = StatementArguments(patterns)
                    arguments += [count]
                    return try Row.fetchAll(db, sql: """
                        SELECT id, title FROM presentation WHERE \(clause) ORDER BY titleFolded, rowid LIMIT ?
                        """, arguments: arguments)
                }
                let titleRows = try run("' ' || titleFolded || ' '", limit)
                let allRows = try run("' ' || titleFolded || ' ' || bodyFolded || ' '", limit + titleRows.count)
                rows = (titleRows, allRows)
            }

            var hits: [SearchHit] = []
            var seen = Set<UUID>()
            func add(_ row: Row, matchedTitle: Bool) {
                let idText: String = row["id"]
                guard hits.count < limit, let id = UUID(uuidString: idText), seen.insert(id).inserted else { return }
                hits.append(SearchHit(presentationID: id, title: row["title"], matchedTitle: matchedTitle))
            }
            for row in rows.title { add(row, matchedTitle: true) }
            for row in rows.all { add(row, matchedTitle: false) }
            return hits
        }
    }
}
