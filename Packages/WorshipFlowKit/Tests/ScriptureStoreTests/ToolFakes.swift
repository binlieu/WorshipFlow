// LIB-004b: fakes for the importer tests. A fake MySQL "server" answers the statements the tool sends with canned
// output in the client's batch format, so nothing here connects to any database. Synthetic text only.
import Foundation
import ScriptureEngine
import Persistence
@testable import ScriptureStore

func hex(_ text: String) -> String { text.utf8.map { String(format: "%02X", $0) }.joined() }

/// A MySQL stand-in: knows a schema and some versions' verses, and answers like the `mysql` client in `--batch
/// --skip-column-names` mode (hex for text, plain numbers). It records every statement it was sent.
final class FakeMySQLServer: MySQLRunning, @unchecked Sendable {   // all state behind `lock`
    struct Version { var id: Int; var code: String; var name: String?; var language: String?; var verses: [RawVerse] }

    private let lock = NSLock()
    private var log: [String] = []
    var schemaRows: [[String]]
    var versions: [Version]
    var bookNames: [Int: String]
    var failure: MySQLError?
    var rawOverride: [String: String] = [:]      // substring of a statement -> raw output

    init(schemaRows: [[String]] = FakeMySQLServer.ownerSchema, versions: [Version] = [], bookNames: [Int: String] = [:]) {
        self.schemaRows = schemaRows
        self.versions = versions
        self.bookNames = bookNames
    }

    static let ownerSchema: [[String]] = [
        ["books", "book_order", "int"], ["books", "abbreviation", "varchar"], ["books", "name_vi", "varchar"], ["books", "name_en", "varchar"],
        ["books", "testament", "varchar"], ["books", "total_chapters", "int"],
        ["versions", "id", "int"], ["versions", "code", "varchar"], ["versions", "name", "varchar"], ["versions", "language", "varchar"],
        ["verses", "id", "int"], ["verses", "version_id", "int"], ["verses", "book_order", "int"], ["verses", "chapter", "int"],
        ["verses", "verse", "int"], ["verses", "text", "longtext"],
    ]

    /// The same database, but `verses` points at versions by code.
    static let codeSchema: [[String]] = ownerSchema.map { row in row[1] == "version_id" ? ["verses", "version_code", "varchar"] : row }

    var statements: [String] { lock.lock(); defer { lock.unlock() }; return log }

    func run(sql: String) async throws -> String {
        let failure = lock.withLock { () -> MySQLError? in log.append(sql); return self.failure }
        if let failure { throw failure }
        guard ReadOnlyStatement.isAllowed(sql) else { throw MySQLError.notReadOnly }
        for (needle, output) in rawOverride where sql.contains(needle) { return output }
        if sql.contains("information_schema.COLUMNS") { return schemaRows.map { $0.joined(separator: "\t") }.joined(separator: "\n") + "\n" }
        let byCode = schemaRows.contains { $0 == ["verses", "version_code", "varchar"] }
        if sql.contains("GROUP BY") {
            return versions.compactMap { v -> String? in
                guard !v.verses.isEmpty else { return nil }
                let key = byCode ? v.code : String(v.id)
                let books = Set(v.verses.map(\.bookOrder)).count
                let chapters = Set(v.verses.map { "\($0.bookOrder)/\($0.chapter)" }).count
                return "\(hex(key))\t\(v.verses.count)\t\(books)\t\(chapters)"
            }.joined(separator: "\n") + "\n"
        }
        if sql.contains("FROM `verses` WHERE") {
            var found: Version?
            for v in versions {
                if byCode, sql.contains("_utf8mb4 0x\(hex(v.code))") { found = v }
                if !byCode, sql.contains("= \(v.id) ") { found = v }
            }
            guard let found else { return "" }
            return found.verses.map { "\($0.bookOrder)\t\($0.chapter)\t\($0.verse)\t" + ($0.text.map(hex) ?? "NULL") }.joined(separator: "\n") + "\n"
        }
        if sql.contains("FROM `versions`") {
            // Columns asked in the statement's order: code, id, name, language (those that exist).
            return versions.map { v in
                var fields = [hex(v.code)]
                if sql.contains("`id`") { fields.append(hex(String(v.id))) }
                if sql.contains("`name`") { fields.append(v.name.map(hex) ?? "NULL") }
                if sql.contains("`language`") { fields.append(v.language.map(hex) ?? "NULL") }
                return fields.joined(separator: "\t")
            }.joined(separator: "\n") + (versions.isEmpty ? "" : "\n")
        }
        if sql.contains("FROM `books`") {
            return bookNames.sorted { $0.key < $1.key }.map { "\($0.key)\t\(hex($0.value))" }.joined(separator: "\n") + "\n"
        }
        throw MySQLError.unexpectedOutput("the fake server does not know this statement")
    }
}

/// Synthetic verses for the fake server: filler text, plus the awkward characters the real client must survive.
enum ToolFixtures {
    static let nasty = "tab\there\nsecond line\r\nthird \\ back\\\\slash \"double\" 'single' `tick` ; -- NULL 0x41 \u{0}end"
    static let stacked = "Ne\u{0302}\u{0323}n ta no\u{0302}\u{0301}i va\u{0309} Đức Chúa Trời"
    static let precomposed = "Nệ̣n Trời ơi, ừ ữ ự ỵ ỷ ỹ"

    /// A small version: three books, awkward text in the first verses. Not scripture.
    static func smallVerses() -> [RawVerse] {
        [
            RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: nasty),
            RawVerse(bookOrder: 1, chapter: 1, verse: 2, text: stacked),
            RawVerse(bookOrder: 1, chapter: 1, verse: 3, text: precomposed),
            RawVerse(bookOrder: 43, chapter: 3, verse: 16, text: "synthetic sixteen"),
            RawVerse(bookOrder: 43, chapter: 3, verse: 17, text: "synthetic seventeen"),
            RawVerse(bookOrder: 66, chapter: 22, verse: 21, text: "synthetic last"),
        ]
    }

    /// Every verse of a table with filler text, as rows.
    static func full(_ table: Versification, language: String = "en") -> [RawVerse] {
        var rows: [RawVerse] = []
        for (index, book) in Canon.books.enumerated() {
            for (chapterIndex, chapter) in (table.books[book.id] ?? []).enumerated() {
                // A chapter with skipped numbers has `count` verses, the last of them numbered `highest`.
                let numbers = chapter.highest == chapter.count ? Array(1...max(chapter.count, 1)) : Array(1..<chapter.count) + [chapter.highest]
                for verse in numbers where chapter.highest > 0 {
                    rows.append(RawVerse(bookOrder: index + 1, chapter: chapterIndex + 1, verse: verse, text: "filler \(language) \(book.id.rawValue) \(chapterIndex + 1):\(verse) text"))
                }
            }
        }
        return rows
    }

    static func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-tool-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class Captured: @unchecked Sendable {   // test helper: lines printed by the tool, behind a lock
    private let lock = NSLock()
    private var items: [String] = []
    func add(_ line: String) { lock.lock(); items.append(line); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return items }
    var text: String { lines.joined(separator: "\n") }
}

struct FixedUsage: LibraryUsageChecking {
    var answer: LibraryUsage
    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage { answer }
}

/// Runs the tool with a fake server and a fake usage checker, and returns what it printed.
struct ToolRun {
    var status: Int32
    var out: String
    var err: String
    var madeRunners: [(MySQLConnection, String?)]
}

enum ToolHarness {
    static func run(_ arguments: [String], server: FakeMySQLServer? = nil, variables: [String: String] = [:], interactive: Bool = false,
                    typedPassword: String? = nil, usage: LibraryUsage = .free) async -> ToolRun {
        let out = Captured(), err = Captured(), runners = RunnerLog()
        var env = ToolEnvironment.live()
        env.variables = variables
        env.out = { out.add($0) }
        env.err = { err.add($0) }
        env.isInteractive = interactive
        env.promptPassword = { prompt in err.add("PROMPT: \(prompt)"); return typedPassword }
        env.makeRunner = { connection, password, _ in
            runners.add(connection, password)
            return server ?? FakeMySQLServer()
        }
        env.usage = FixedUsage(answer: usage)
        env.processID = 1
        let status = await ImportToolCLI.run(arguments, environment: env)
        return ToolRun(status: status, out: out.text, err: err.text, madeRunners: runners.all)
    }
}

final class RunnerLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(MySQLConnection, String?)] = []
    func add(_ c: MySQLConnection, _ p: String?) { lock.lock(); items.append((c, p)); lock.unlock() }
    var all: [(MySQLConnection, String?)] { lock.lock(); defer { lock.unlock() }; return items }
}
