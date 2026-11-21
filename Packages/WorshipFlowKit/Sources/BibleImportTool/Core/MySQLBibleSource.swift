// LIB-004b: reading the owner's Bible database (tables `versions`, `books`, `verses`) through a `MySQLRunning`.
//
// Query building and output parsing live here, behind the runner, so tests drive them with canned output.
//
// Output mode: every text value is fetched as `HEX(CONVERT(column USING utf8mb4))`. The client then prints only the
// characters 0-9 and A-F for it, so tabs, newlines, backslashes, quotes and NUL inside verse text cannot be mistaken for
// the client's own separators or escapes, and the connection's character handling cannot change a byte. Numbers are
// printed plainly. A SQL NULL is the word NULL, which no hex string can be.
//
// The owner's column names are not in the repository, so they are found from `information_schema` by a list of likely
// names per role, and every role can be set by hand with `--map table.role=column`.
import Foundation

struct MySQLSchemaMapping: Equatable {
    var versionsTable = "versions"
    var booksTable = "books"
    var versesTable = "verses"
    /// role -> column, for example "verses.text" -> "verse_text". Roles: versions.id, versions.code, versions.name,
    /// versions.language, verses.version, verses.book, verses.chapter, verses.verse, verses.text, books.order, books.name_en.
    var overrides: [String: String] = [:]
}

/// Columns resolved for this database.
struct ResolvedSchema: Equatable {
    var versionsTable: String
    var versesTable: String
    var booksTable: String?
    var versionID: String?
    var versionCode: String
    var versionName: String?
    var versionLanguage: String?
    var versesVersion: String
    /// True when `verses.version` holds the number in `versions.id`; false when it holds the code itself.
    var versesVersionIsID: Bool
    var versesBook: String
    var versesChapter: String
    var versesVerse: String
    var versesText: String
    var booksOrder: String?
    var booksNameEN: String?

    /// Lines for `inspect --schema` and for error messages.
    var description: [String] {
        var lines = ["versions table: \(versionsTable) (code: \(versionCode)" + (versionID.map { ", id: \($0)" } ?? "") + (versionName.map { ", name: \($0)" } ?? "") + (versionLanguage.map { ", language: \($0)" } ?? "") + ")",
                     "verses table: \(versesTable) (version: \(versesVersion) = versions.\(versesVersionIsID ? "id" : "code"), book: \(versesBook), chapter: \(versesChapter), verse: \(versesVerse), text: \(versesText))"]
        if let booksTable { lines.append("books table: \(booksTable)" + (booksOrder.map { " (order: \($0)" } ?? " (") + (booksNameEN.map { ", English name: \($0)" } ?? "") + ")") }
        return lines
    }
}

struct VersionSummary: Equatable {
    /// The value `verses` uses for this version (id or code, as text).
    var key: String
    var code: String
    var name: String?
    var language: String?
    var verseCount: Int
    var bookCount: Int
    var chapterCount: Int
}

struct RawVerse: Equatable {
    var bookOrder: Int
    var chapter: Int
    var verse: Int
    /// Nil when the database value is NULL.
    var text: String?
}

struct MySQLBibleSource {
    let runner: any MySQLRunning
    let mapping: MySQLSchemaMapping

    init(runner: any MySQLRunning, mapping: MySQLSchemaMapping = MySQLSchemaMapping()) {
        self.runner = runner
        self.mapping = mapping
    }

    // MARK: Identifiers and literals

    /// Names go into statements inside back quotes, so only plain identifier characters are allowed.
    static func quote(_ identifier: String) throws -> String {
        guard !identifier.isEmpty, identifier.unicodeScalars.allSatisfy({ ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || $0 == "_" || $0 == "$" }) else {
            throw MySQLError.schema("the name “\(identifier.prefix(40))” cannot be used: names may contain only letters, digits, _ and $.")
        }
        return "`" + identifier + "`"
    }

    static func hexColumn(_ column: String) throws -> String { "HEX(CONVERT(\(try quote(column)) USING utf8mb4))" }

    /// A number as itself; anything else as a `_utf8mb4` hex literal, which needs no escaping and takes the column's collation.
    static func literal(_ value: String, numeric: Bool) throws -> String {
        if numeric {
            guard !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }), value.count <= 18 else {
                throw MySQLError.schema("the version key “\(value.prefix(40))” is not a number, but the verses table stores a number.")
            }
            return String(Int(value) ?? 0)
        }
        guard !value.isEmpty else { throw MySQLError.schema("the version has an empty code.") }
        return "_utf8mb4 0x" + Array(value.utf8).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: Hex decoding

    static func decodeHex(_ field: String) throws -> String? {
        if field == "NULL" { return nil }
        guard field.count % 2 == 0 else { throw MySQLError.unexpectedOutput("a text value is not whole bytes") }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(field.utf8.count / 2)
        var high: UInt8?
        for byte in field.utf8 {
            let value: UInt8
            switch byte {
            case 0x30...0x39: value = byte - 0x30
            case 0x41...0x46: value = byte - 0x41 + 10
            case 0x61...0x66: value = byte - 0x61 + 10
            default: throw MySQLError.unexpectedOutput("a text value contains a character that is not hexadecimal")
            }
            if let h = high { bytes.append(h << 4 | value); high = nil } else { high = value }
        }
        guard let text = String(validatingUTF8Bytes: bytes) else {
            throw MySQLError.data("a text value is not valid UTF-8 after conversion; the column's character set may be wrong")
        }
        return text
    }

    static func rows(_ output: String, columns: Int) throws -> [[String]] {
        var out: [[String]] = []
        for (index, line) in output.split(whereSeparator: \.isNewline).enumerated() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            guard fields.count == columns else {
                throw MySQLError.unexpectedOutput("line \(index + 1) has \(fields.count) fields, expected \(columns)")
            }
            out.append(fields)
        }
        return out
    }

    // MARK: Schema

    func resolveSchema() async throws -> ResolvedSchema {
        let output = try await runner.run(sql: """
            SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() ORDER BY TABLE_NAME, ORDINAL_POSITION
            """)
        var tables: [String: [(name: String, type: String)]] = [:]
        for fields in try Self.rows(output, columns: 3) { tables[fields[0], default: []].append((fields[1], fields[2].lowercased())) }
        guard !tables.isEmpty else {
            throw MySQLError.schema("the database has no tables, or the user cannot see them in information_schema.")
        }

        func table(_ wanted: String, required: Bool) throws -> (name: String, columns: [(name: String, type: String)])? {
            if let hit = tables.first(where: { $0.key.lowercased() == wanted.lowercased() }) { return (hit.key, hit.value) }
            if required {
                throw MySQLError.schema("the database has no table “\(wanted)”. Tables found: \(tables.keys.sorted().joined(separator: ", ")). Use --versions-table, --verses-table or --books-table.")
            }
            return nil
        }
        guard let versions = try table(mapping.versionsTable, required: true), let verses = try table(mapping.versesTable, required: true) else {
            throw MySQLError.schema("the versions or verses table is missing.")
        }
        let books = try table(mapping.booksTable, required: false)

        func pick(_ role: String, in found: (name: String, columns: [(name: String, type: String)]), candidates: [String], required: Bool) throws -> String? {
            if let forced = mapping.overrides[role] {
                guard let hit = found.columns.first(where: { $0.name.lowercased() == forced.lowercased() }) else {
                    throw MySQLError.schema("--map \(role)=\(forced.prefix(40)): table \(found.name) has no such column. Columns: \(found.columns.map(\.name).joined(separator: ", ")).")
                }
                return hit.name
            }
            for candidate in candidates {
                if let hit = found.columns.first(where: { $0.name.lowercased() == candidate }) { return hit.name }
            }
            if required {
                throw MySQLError.schema("could not tell which column of \(found.name) is the \(role.split(separator: ".").last ?? ""). Columns: \(found.columns.map(\.name).joined(separator: ", ")). Name it with --map \(role)=<column>.")
            }
            return nil
        }

        let code = try pick("versions.code", in: versions, candidates: ["code", "version_code", "abbreviation", "abbr", "short_name", "shortname", "version"], required: true) ?? ""
        let versionID = try pick("versions.id", in: versions, candidates: ["id", "version_id", "versionid"], required: false)
        let name = try pick("versions.name", in: versions, candidates: ["name", "title", "version_name", "full_name", "fullname", "description"], required: false)
        let language = try pick("versions.language", in: versions, candidates: ["language", "lang", "locale", "language_code"], required: false)

        let link = try pick("verses.version", in: verses, candidates: ["version_id", "version_code", "versionid", "version", "bible_version", "translation_id", "translation", "code"], required: true) ?? ""
        let linkType = verses.columns.first { $0.name == link }?.type ?? ""
        let numeric = ["tinyint", "smallint", "mediumint", "int", "integer", "bigint", "decimal", "numeric"].contains(linkType)
        if numeric, versionID == nil {
            throw MySQLError.schema("verses.\(link) is a number but the versions table has no id column. Name it with --map versions.id=<column>.")
        }
        let book = try pick("verses.book", in: verses, candidates: ["book_order", "book", "book_id", "book_number", "book_num"], required: true) ?? ""
        let chapter = try pick("verses.chapter", in: verses, candidates: ["chapter", "chapter_number", "chapter_no", "chapter_num"], required: true) ?? ""
        let verse = try pick("verses.verse", in: verses, candidates: ["verse", "verse_number", "verse_no", "verse_num"], required: true) ?? ""
        let text = try pick("verses.text", in: verses, candidates: ["text", "verse_text", "content", "scripture", "body", "verse_content"], required: true) ?? ""

        var order: String?, nameEN: String?
        if let books {
            order = try pick("books.order", in: books, candidates: ["book_order", "order", "book_number", "number"], required: false)
            nameEN = try pick("books.name_en", in: books, candidates: ["name_en", "english_name", "name_english"], required: false)
        }
        return ResolvedSchema(versionsTable: versions.name, versesTable: verses.name, booksTable: books?.name, versionID: versionID,
                              versionCode: code, versionName: name, versionLanguage: language, versesVersion: link,
                              versesVersionIsID: numeric, versesBook: book, versesChapter: chapter, versesVerse: verse,
                              versesText: text, booksOrder: order, booksNameEN: nameEN)
    }

    // MARK: Versions

    func listVersions(_ schema: ResolvedSchema) async throws -> [VersionSummary] {
        var selected: [String] = [schema.versionCode]
        let idColumn = schema.versionID
        if let idColumn, idColumn != schema.versionCode { selected.append(idColumn) }
        for optional in [schema.versionName, schema.versionLanguage] { if let optional { selected.append(optional) } }
        let hexes = try selected.map(Self.hexColumn)
        let output = try await runner.run(sql: "SELECT \(hexes.joined(separator: ", ")) FROM \(try Self.quote(schema.versionsTable)) ORDER BY 1")
        var records: [[String: String?]] = []
        for fields in try Self.rows(output, columns: selected.count) {
            var record: [String: String?] = [:]
            for (column, field) in zip(selected, fields) { record[column] = try Self.decodeHex(field) }
            records.append(record)
        }

        let link = try Self.hexColumn(schema.versesVersion)
        let book = try Self.quote(schema.versesBook), chapter = try Self.quote(schema.versesChapter)
        let counts = try await runner.run(sql: """
            SELECT \(link), COUNT(*), COUNT(DISTINCT \(book)), COUNT(DISTINCT \(book), \(chapter)) FROM \(try Self.quote(schema.versesTable)) GROUP BY \(try Self.quote(schema.versesVersion))
            """)
        var countsByKey: [String: (verses: Int, books: Int, chapters: Int)] = [:]
        for fields in try Self.rows(counts, columns: 4) {
            guard let key = try Self.decodeHex(fields[0]), let v = Int(fields[1]), let b = Int(fields[2]), let c = Int(fields[3]) else {
                throw MySQLError.unexpectedOutput("a count line could not be read")
            }
            countsByKey[key] = (v, b, c)
        }

        var out: [VersionSummary] = []
        var matched = Set<String>()
        for record in records {
            guard let code = record[schema.versionCode] ?? nil else { continue }
            let key: String = schema.versesVersionIsID ? ((idColumn.flatMap { record[$0] } ?? nil) ?? "") : code
            let c = countsByKey[key]
            if c != nil { matched.insert(key) }
            out.append(VersionSummary(key: key, code: code, name: schema.versionName.flatMap { record[$0] ?? nil },
                                      language: schema.versionLanguage.flatMap { record[$0] ?? nil },
                                      verseCount: c?.verses ?? 0, bookCount: c?.books ?? 0, chapterCount: c?.chapters ?? 0))
        }
        // Verses that point at a version with no row in `versions` are shown, not hidden.
        for (key, c) in countsByKey.sorted(by: { $0.key < $1.key }) where !matched.contains(key) {
            out.append(VersionSummary(key: key, code: "(no row in \(schema.versionsTable): \(key))", name: nil, language: nil,
                                      verseCount: c.verses, bookCount: c.books, chapterCount: c.chapters))
        }
        return out
    }

    // MARK: Books (only used to cross-check)

    /// book order -> English name, when the books table has both columns.
    func bookNames(_ schema: ResolvedSchema) async throws -> [Int: String] {
        guard let table = schema.booksTable, let order = schema.booksOrder, let name = schema.booksNameEN else { return [:] }
        let output = try await runner.run(sql: "SELECT \(try Self.quote(order)), \(try Self.hexColumn(name)) FROM \(try Self.quote(table)) ORDER BY 1")
        var out: [Int: String] = [:]
        for fields in try Self.rows(output, columns: 2) {
            if let n = Int(fields[0]), let text = try Self.decodeHex(fields[1]) { out[n] = text }
        }
        return out
    }

    // MARK: Verses

    func verses(of version: VersionSummary, _ schema: ResolvedSchema) async throws -> [RawVerse] {
        let value = try Self.literal(version.key, numeric: schema.versesVersionIsID)
        let book = try Self.quote(schema.versesBook), chapter = try Self.quote(schema.versesChapter), verse = try Self.quote(schema.versesVerse)
        let output = try await runner.run(sql: """
            SELECT \(book), \(chapter), \(verse), \(try Self.hexColumn(schema.versesText)) FROM \(try Self.quote(schema.versesTable)) WHERE \(try Self.quote(schema.versesVersion)) = \(value) ORDER BY \(book), \(chapter), \(verse)
            """)
        var out: [RawVerse] = []
        out.reserveCapacity(32_000)
        for fields in try Self.rows(output, columns: 4) {
            guard let b = Int(fields[0]), let c = Int(fields[1]), let v = Int(fields[2]) else {
                throw MySQLError.data("a verse row has a book, chapter or verse that is not a whole number (\(fields[0].prefix(20)), \(fields[1].prefix(20)), \(fields[2].prefix(20))).")
            }
            out.append(RawVerse(bookOrder: b, chapter: c, verse: v, text: try Self.decodeHex(fields[3])))
        }
        return out
    }
}

extension String {
    /// Strict UTF-8: nil for invalid bytes, instead of replacement characters.
    init?(validatingUTF8Bytes bytes: [UInt8]) {
        guard let text = String(validating: bytes, as: UTF8.self) else { return nil }
        self = text
    }
}
