// LIB-004b: Bible translations in the church's library file (ADR-0008 decision 4).
//
// `ScriptureStore` reads and writes the `scriptureTranslation` and `scriptureVerse` tables (schema v7) through the
// `LibraryStore` it is given, on that store's one connection pool: it never opens the file itself (ADR-0004 decision 2).
// An import is one transaction. The translation file is validated and every row is prepared before the transaction
// starts, so the write lock is held only for the inserts, and any failure rolls back to exactly what was there before.
import Foundation
import GRDB
import Domain
import ScriptureEngine
@_spi(ScriptureStore) import Persistence

/// A translation as kept in the library.
public struct StoredTranslation: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// The translation file's id ("kjv", "VI1925"); unique in a library, ignoring case.
    public var code: String
    public var name: String
    /// BCP 47 tag.
    public var language: String
    public var abbreviation: String
    public var copyright: String?
    public var licence: String?
    /// Where the church got it (the file's `sourceURL`, or a description).
    public var sourceDescription: String?
    public var isPublicDomain: Bool
    public var ownerApproval: OwnerApproval?
    /// "KJV", "VI1925", or the label of the translation's own table.
    public var versificationID: String
    public var versificationNote: String?
    public var verseCount: Int
    public var importedAt: Date

    /// The same facts in the translation file's shape.
    public var metadata: TranslationMetadata {
        TranslationMetadata(id: code, name: name, language: language, abbreviation: abbreviation, copyright: copyright,
                            license: licence, sourceURL: sourceDescription, isPublicDomain: isPublicDomain,
                            versificationNote: versificationNote, versification: versificationID, ownerApproval: ownerApproval)
    }
}

public struct StoredVerse: Sendable, Equatable {
    public var ref: VerseRef
    public var text: String
    public init(ref: VerseRef, text: String) { self.ref = ref; self.text = text }
}

public struct ScriptureImportProgress: Sendable, Equatable {
    public var versesDone: Int
    public var versesTotal: Int
}

public struct ScriptureImportResult: Sendable {
    public var translation: StoredTranslation
    /// What the loader found in the file: gaps, empty verses, duplicates, partial coverage.
    public var report: TranslationReport
    /// True when an existing translation with the same code was replaced.
    public var replaced: Bool
}

public enum ScriptureStoreError: Error, Equatable, Sendable {
    /// `importTranslation` without `replaceExisting` found the code already in the library.
    case alreadyExists(String)
    case notFound(String)
    /// The file has no usable verses.
    case emptyTranslation
    /// A required metadata field is blank. The text names the field.
    case invalidMetadata(String)
    /// The library file is older than schema v7; open it with `LibraryStore.open(at:)` to update it.
    case libraryNeedsUpdate

    /// Operator-readable text.
    public var message: String {
        switch self {
        case .alreadyExists(let code): return "The library already has a translation with the code “\(code)”. Replace it to import again."
        case .notFound(let code): return "The library has no translation with the code “\(code)”."
        case .emptyTranslation: return "The file has no verses that can be imported."
        case .invalidMetadata(let field): return "The translation's \(field) is empty."
        case .libraryNeedsUpdate: return "This library file has not been updated for Bible translations yet."
        }
    }
}

public final class ScriptureStore: Sendable {
    /// The derived FTS5 table `Persistence` keeps over `scriptureVerse.textFolded`.
    static let searchTable = "scriptureSearch"

    let library: LibraryStore
    /// Test seam: called inside the import transaction after each batch with the number of verses written so far.
    let afterBatch: (@Sendable (Int) throws -> Void)?
    let batchSize: Int

    public init(library: LibraryStore) {
        self.library = library
        self.afterBatch = nil
        self.batchSize = 500
    }

    init(library: LibraryStore, afterBatch: (@Sendable (Int) throws -> Void)?, batchSize: Int = 500) {
        self.library = library
        self.afterBatch = afterBatch
        self.batchSize = max(batchSize, 1)
    }

    // MARK: Translations

    /// All translations, by name.
    public func translations() async throws -> [StoredTranslation] {
        try await library.scriptureRead { db in
            try Self.requireTables(db)
            return try Row.fetchAll(db, sql: "SELECT * FROM scriptureTranslation ORDER BY name COLLATE NOCASE, code COLLATE NOCASE")
                .compactMap(Self.translation(from:))
        }
    }

    public func translation(code: String) async throws -> StoredTranslation {
        try await library.scriptureRead { db in
            try Self.requireTables(db)
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scriptureTranslation WHERE code = ?", arguments: [code]),
                  let found = Self.translation(from: row) else { throw ScriptureStoreError.notFound(code) }
            return found
        }
    }

    /// Removes a translation, its verses and its search rows, in one transaction. Other translations and everything else
    /// in the library are untouched.
    public func deleteTranslation(code: String) async throws {
        let fts = library.scriptureSearchUsesFTS5
        try await library.scriptureWrite { db in
            try Self.requireTables(db)
            guard let id = try String.fetchOne(db, sql: "SELECT id FROM scriptureTranslation WHERE code = ?", arguments: [code]) else {
                throw ScriptureStoreError.notFound(code)
            }
            if fts, try db.tableExists(Self.searchTable) {
                try db.execute(sql: "DELETE FROM \(Self.searchTable) WHERE translationID = ?", arguments: [id])
            }
            try db.execute(sql: "DELETE FROM scriptureTranslation WHERE id = ?", arguments: [id])   // verses cascade
        }
    }

    /// The verse-count table of a translation: the built-in table it names, or the one stored with it.
    public func versification(for code: String) async throws -> Versification {
        try await library.scriptureRead { db in
            try Self.requireTables(db)
            guard let row = try Row.fetchOne(db, sql: "SELECT versificationID, versificationJSON FROM scriptureTranslation WHERE code = ?",
                                             arguments: [code]) else { throw ScriptureStoreError.notFound(code) }
            return Self.versification(from: row)
        }
    }

    // MARK: Row mapping (shared with the other files of this type)

    static func requireTables(_ db: Database) throws {
        guard try db.tableExists("scriptureTranslation"), try db.tableExists("scriptureVerse") else {
            throw ScriptureStoreError.libraryNeedsUpdate
        }
    }

    static func translation(from row: Row) -> StoredTranslation? {
        guard let idText: String = row["id"], let id = UUID(uuidString: idText) else { return nil }
        var approval: OwnerApproval?
        if let json: String = row["ownerApprovalJSON"] { approval = try? JSONDecoder().decode(OwnerApproval.self, from: Data(json.utf8)) }
        return StoredTranslation(
            id: id, code: row["code"], name: row["name"], language: row["language"], abbreviation: row["abbreviation"],
            copyright: row["copyright"], licence: row["licence"], sourceDescription: row["sourceDescription"],
            isPublicDomain: row["isPublicDomain"], ownerApproval: approval, versificationID: row["versificationID"],
            versificationNote: row["versificationNote"], verseCount: row["verseCount"], importedAt: row["importedAt"])
    }

    private struct StoredTable: Codable {
        var id: String
        var books: [String: [[Int]]]
    }

    static func versification(from row: Row) -> Versification {
        let id: String = row["versificationID"]
        if let json: String = row["versificationJSON"],
           let stored = try? JSONDecoder().decode(StoredTable.self, from: Data(json.utf8)),
           let table = Versification(id: stored.id, table: stored.books) {
            return table
        }
        return Versification.named(id) ?? .kjv
    }

    /// The columns for a translation's table: the built-in name when the table is exactly that built-in one, otherwise
    /// the table itself as JSON.
    static func storedVersification(_ table: Versification) -> (id: String, json: String?) {
        if let builtIn = Versification.named(table.id), builtIn == table { return (builtIn.id, nil) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = (try? encoder.encode(StoredTable(id: table.id, books: table.tableRepresentation))).map { String(decoding: $0, as: UTF8.self) }
        return (table.id, json)
    }

    static func bookID(order: Int) -> BookID? {
        guard order >= 1, order <= Canon.books.count else { return nil }
        return Canon.books[order - 1].id
    }
}
