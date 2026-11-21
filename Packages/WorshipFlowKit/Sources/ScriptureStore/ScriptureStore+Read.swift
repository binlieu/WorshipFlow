// LIB-004b: reading verses and searching them.
import Foundation
import GRDB
import Domain
import ScriptureEngine
@_spi(ScriptureStore) import Persistence

extension ScriptureStore {
    /// The verses of `ranges` that the translation has, each range in canon order, ranges in the order given (a verse
    /// named by two ranges comes back twice). A range is read by position, so it needs no verse-count table. Throws
    /// `notFound` when the translation is not in the library.
    public func verses(in ranges: [VerseRange], translationCode: String) async throws -> [StoredVerse] {
        try await library.scriptureRead { db in
            try Self.requireTables(db)
            let id = try Self.translationID(db, code: translationCode)
            var out: [StoredVerse] = []
            for range in ranges {
                guard range.start.book == range.end.book, range.start <= range.end, let order = Canon.order(of: range.book) else { continue }
                let rows = try Row.fetchAll(db, sql: """
                    SELECT chapter, verse, text FROM scriptureVerse
                    WHERE translationID = ? AND bookOrder = ? AND (chapter, verse) >= (?, ?) AND (chapter, verse) <= (?, ?)
                    ORDER BY chapter, verse
                    """, arguments: [id, order, range.start.chapter, range.start.verse, range.end.chapter, range.end.verse])
                for row in rows {
                    out.append(StoredVerse(ref: VerseRef(book: range.book, chapter: row["chapter"], verse: row["verse"]), text: row["text"]))
                }
            }
            return out
        }
    }

    /// Keyword search inside one translation, with the rules of `ScriptureSearchIndex`: all words must appear, each as the
    /// start of a word; a quoted phrase must appear as consecutive words; case, diacritics, đ and punctuation are ignored
    /// (`SearchFolding`). Results are in canon order; `truncated` says more verses matched than `limit`.
    public func search(_ query: String, translationCode: String, limit: Int = 50) async throws -> ScriptureSearchResult {
        let terms = ScriptureSearchIndex.queryTerms(query)
        let fts = library.scriptureSearchUsesFTS5
        return try await library.scriptureRead { db in
            try Self.requireTables(db)
            let id = try Self.translationID(db, code: translationCode)
            guard !terms.isEmpty, limit > 0 else { return ScriptureSearchResult(hits: [], truncated: false) }
            let rows: [Row]
            if fts, try db.tableExists(Self.searchTable) {
                // Terms are alphanumeric words after folding, so quoting them is always well-formed FTS5. A phrase is a
                // quoted run of words whose last word is a prefix; a single word is a prefix.
                let match = terms.map { "\"\($0)\"*" }.joined(separator: " ")
                rows = try Row.fetchAll(db, sql: """
                    SELECT v.bookOrder AS bookOrder, v.chapter AS chapter, v.verse AS verse, v.text AS text
                    FROM \(Self.searchTable)
                    JOIN scriptureVerse v ON v.translationID = \(Self.searchTable).translationID
                        AND v.bookOrder = \(Self.searchTable).bookOrder AND v.chapter = \(Self.searchTable).chapter
                        AND v.verse = \(Self.searchTable).verse
                    WHERE \(Self.searchTable) MATCH ? AND \(Self.searchTable).translationID = ?
                    ORDER BY v.bookOrder, v.chapter, v.verse LIMIT ?
                    """, arguments: [match, id, limit + 1])
            } else {
                // Folded terms contain only letters, digits and single spaces, so they hold no LIKE wildcard.
                let clause = terms.map { _ in "(' ' || textFolded) LIKE ?" }.joined(separator: " AND ")
                var arguments = StatementArguments([id])
                arguments += StatementArguments(terms.map { "% \($0)%" })
                arguments += [limit + 1]
                rows = try Row.fetchAll(db, sql: """
                    SELECT bookOrder, chapter, verse, text FROM scriptureVerse
                    WHERE translationID = ? AND \(clause) ORDER BY bookOrder, chapter, verse LIMIT ?
                    """, arguments: arguments)
            }
            var hits: [ScriptureSearchHit] = []
            for row in rows.prefix(limit) {
                guard let book = Self.bookID(order: row["bookOrder"]) else { continue }
                hits.append(ScriptureSearchHit(ref: VerseRef(book: book, chapter: row["chapter"], verse: row["verse"]),
                                               text: row["text"], terms: terms, snippetLength: 100))
            }
            return ScriptureSearchResult(hits: hits, truncated: rows.count > limit)
        }
    }

    static func translationID(_ db: Database, code: String) throws -> String {
        guard let id = try String.fetchOne(db, sql: "SELECT id FROM scriptureTranslation WHERE code = ?", arguments: [code]) else {
            throw ScriptureStoreError.notFound(code)
        }
        return id
    }
}
