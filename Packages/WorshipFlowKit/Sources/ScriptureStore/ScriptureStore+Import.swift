// LIB-004b: importing a translation file into the library. One transaction; batched multi-row inserts.
import Foundation
import GRDB
import Domain
import ScriptureEngine
@_spi(ScriptureStore) import Persistence

extension ScriptureStore {
    private struct PreparedVerse: Sendable {
        var bookOrder: Int
        var chapter: Int
        var verse: Int
        var text: String
        var folded: String
    }

    /// Validates `file` with `TranslationLoader` (so gaps, duplicates and empty verses are reported the same way as
    /// everywhere else), then writes the translation and its verses in one transaction.
    ///
    /// - Parameters:
    ///   - replaceExisting: when false and the code exists, throws `alreadyExists` and changes nothing. When true the
    ///     existing translation (same code, ignoring case) is replaced, keeping its id.
    ///   - progress: called with the verses written so far, about every `batchSize` verses, first with 0 and last with the
    ///     total. It runs on the writer's queue inside the transaction: keep it quick.
    /// - Throws: `ScriptureStoreError`, or the database's error; in every case the library is as it was before the call.
    public func importTranslation(_ file: TranslationFile, replaceExisting: Bool,
                                  progress: (@Sendable (ScriptureImportProgress) -> Void)? = nil) async throws -> ScriptureImportResult {
        let meta = file.metadata
        let code = meta.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = meta.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = meta.language.trimmingCharacters(in: .whitespacesAndNewlines)
        let abbreviation = meta.abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { throw ScriptureStoreError.invalidMetadata("code (id)") }
        if name.isEmpty { throw ScriptureStoreError.invalidMetadata("name") }
        if language.isEmpty { throw ScriptureStoreError.invalidMetadata("language") }
        if abbreviation.isEmpty { throw ScriptureStoreError.invalidMetadata("abbreviation") }

        // Everything that costs CPU happens before the transaction.
        let loaded = TranslationLoader.validate(file)
        guard loaded.report.verseCount > 0 else { throw ScriptureStoreError.emptyTranslation }
        let translation = loaded.translation
        var rows: [PreparedVerse] = []
        rows.reserveCapacity(loaded.report.verseCount)
        for (ref, text) in translation.allVerses() {
            guard let order = Canon.order(of: ref.book) else { continue }
            rows.append(PreparedVerse(bookOrder: order, chapter: ref.chapter, verse: ref.verse, text: text, folded: SearchFolding.fold(text)))
        }
        let table = Self.storedVersification(translation.versification)
        let approvalJSON: String? = meta.ownerApproval.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }

        let prepared = rows
        let fts = library.scriptureSearchUsesFTS5
        let batch = batchSize
        let hook = afterBatch
        let newID = UUID().uuidString
        let now = Date()
        let total = prepared.count

        let (stored, replaced) = try await library.scriptureWrite { db -> (StoredTranslation, Bool) in
            try Self.requireTables(db)
            let existing = try String.fetchOne(db, sql: "SELECT id FROM scriptureTranslation WHERE code = ?", arguments: [code])
            if existing != nil, !replaceExisting { throw ScriptureStoreError.alreadyExists(code) }
            let id = existing ?? newID

            let fields: [any DatabaseValueConvertible & Sendable] = [
                code, name, language, abbreviation, meta.copyright, meta.license, meta.sourceURL, meta.isPublicDomain,
                approvalJSON, table.id, table.json, meta.versificationNote, total, now,
            ]
            if existing != nil {
                if fts, try db.tableExists(Self.searchTable) {
                    try db.execute(sql: "DELETE FROM \(Self.searchTable) WHERE translationID = ?", arguments: [id])
                }
                try db.execute(sql: "DELETE FROM scriptureVerse WHERE translationID = ?", arguments: [id])
                try db.execute(sql: """
                    UPDATE scriptureTranslation SET code = ?, name = ?, language = ?, abbreviation = ?, copyright = ?, licence = ?,
                        sourceDescription = ?, isPublicDomain = ?, ownerApprovalJSON = ?, versificationID = ?, versificationJSON = ?,
                        versificationNote = ?, verseCount = ?, importedAt = ? WHERE id = ?
                    """, arguments: StatementArguments(fields) + [id])
            } else {
                try db.execute(sql: """
                    INSERT INTO scriptureTranslation (code, name, language, abbreviation, copyright, licence, sourceDescription,
                        isPublicDomain, ownerApprovalJSON, versificationID, versificationJSON, versificationNote, verseCount, importedAt, id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: StatementArguments(fields) + [id])
            }

            progress?(ScriptureImportProgress(versesDone: 0, versesTotal: total))
            let indexed = try fts && db.tableExists(Self.searchTable)
            var written = 0
            while written < total {
                let slice = prepared[written..<min(written + batch, total)]
                try Self.insert(db, translationID: id, rows: slice, index: indexed)
                written += slice.count
                try hook?(written)
                progress?(ScriptureImportProgress(versesDone: written, versesTotal: total))
            }

            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scriptureTranslation WHERE id = ?", arguments: [id]),
                  let stored = Self.translation(from: row) else { throw ScriptureStoreError.notFound(code) }
            return (stored, existing != nil)
        }
        return ScriptureImportResult(translation: stored, report: loaded.report, replaced: replaced)
    }

    /// One multi-row INSERT for the verses and one for the search rows.
    private static func insert(_ db: Database, translationID: String, rows: ArraySlice<PreparedVerse>, index: Bool) throws {
        func marks(_ columns: Int) -> String {
            let one = "(" + Array(repeating: "?", count: columns).joined(separator: ", ") + ")"
            return Array(repeating: one, count: rows.count).joined(separator: ", ")
        }
        var verseArguments = StatementArguments()
        for row in rows {
            verseArguments += StatementArguments([translationID, row.bookOrder, row.chapter, row.verse, row.text, row.folded] as [any DatabaseValueConvertible])
        }
        let verseStatement = try db.cachedStatement(sql: """
            INSERT INTO scriptureVerse (translationID, bookOrder, chapter, verse, text, textFolded) VALUES \(marks(6))
            """)
        try verseStatement.execute(arguments: verseArguments)
        guard index else { return }
        var indexArguments = StatementArguments()
        for row in rows {
            indexArguments += StatementArguments([row.folded, translationID, row.bookOrder, row.chapter, row.verse] as [any DatabaseValueConvertible])
        }
        let indexStatement = try db.cachedStatement(sql: """
            INSERT INTO \(Self.searchTable) (textFolded, translationID, bookOrder, chapter, verse) VALUES \(marks(5))
            """)
        try indexStatement.execute(arguments: indexArguments)
    }
}
