// LIB-004b: the seam to the MySQL client, driven by a fake server with canned output. Synthetic text only.
import Testing
import Foundation
import ScriptureEngine
@testable import ScriptureStore

@Suite struct ToolMySQLSourceTests {
    private func owner() -> FakeMySQLServer {
        FakeMySQLServer(versions: [
            .init(id: 1, code: "VI1934", name: "Vietnamese test", language: "vi", verses: ToolFixtures.smallVerses()),
            .init(id: 2, code: "NKJV", name: nil, language: "en", verses: Array(ToolFixtures.smallVerses().prefix(2))),
            .init(id: 3, code: "EMPTY", name: "No verses", language: nil, verses: []),
        ], bookNames: [1: "Genesis", 43: "John"])
    }

    @Test func schemaIsFoundFromLikelyColumnNames() async throws {
        let source = MySQLBibleSource(runner: owner())
        let schema = try await source.resolveSchema()
        #expect(schema.versionCode == "code" && schema.versionID == "id" && schema.versionName == "name" && schema.versionLanguage == "language")
        #expect(schema.versesVersion == "version_id" && schema.versesVersionIsID)
        #expect(schema.versesBook == "book_order" && schema.versesChapter == "chapter" && schema.versesVerse == "verse" && schema.versesText == "text")
        #expect(schema.booksOrder == "book_order" && schema.booksNameEN == "name_en")
        #expect(schema.description.count == 3)
    }

    @Test func aVersesTableThatPointsAtVersionsByCodeIsRead() async throws {
        let server = FakeMySQLServer(schemaRows: FakeMySQLServer.codeSchema, versions: [.init(id: 1, code: "VI1934", name: "V", language: "vi", verses: ToolFixtures.smallVerses())])
        let source = MySQLBibleSource(runner: server)
        let schema = try await source.resolveSchema()
        #expect(schema.versesVersion == "version_code" && !schema.versesVersionIsID)
        let versions = try await source.listVersions(schema)
        #expect(versions.map(\.code) == ["VI1934"] && versions[0].key == "VI1934")
        let rows = try await source.verses(of: versions[0], schema)
        #expect(rows.count == 6)
        #expect(server.statements.last?.contains("`version_code` = _utf8mb4 0x\(hex("VI1934"))") == true)
    }

    @Test func versionsAreListedWithCounts() async throws {
        let source = MySQLBibleSource(runner: owner())
        let schema = try await source.resolveSchema()
        let versions = try await source.listVersions(schema)
        #expect(versions.map(\.code) == ["VI1934", "NKJV", "EMPTY"])
        #expect(versions[0] == VersionSummary(key: "1", code: "VI1934", name: "Vietnamese test", language: "vi", verseCount: 6, bookCount: 3, chapterCount: 3))
        #expect(versions[1].name == nil && versions[1].verseCount == 2 && versions[1].bookCount == 1)
        #expect(versions[2].verseCount == 0 && versions[2].bookCount == 0)
    }

    @Test func versesPointingAtAMissingVersionAreShownNotHidden() async throws {
        let server = FakeMySQLServer(versions: [
            .init(id: 1, code: "VI1934", name: "Vietnamese test", language: "vi", verses: ToolFixtures.smallVerses()),
            .init(id: 9, code: "GHOST", name: nil, language: nil, verses: [RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "x")]),
        ])
        server.rawOverride["FROM `versions`"] = "\(hex("VI1934"))\t\(hex("1"))\t\(hex("Vietnamese test"))\t\(hex("vi"))\n"
        let source = MySQLBibleSource(runner: server)
        let versions = try await source.listVersions(try await source.resolveSchema())
        #expect(versions.count == 2)
        #expect(versions[1].code.contains("no row in versions") && versions[1].verseCount == 1)
    }

    @Test func textWithTabsNewlinesBackslashesQuotesAndNULSurvivesByteForByte() async throws {
        let source = MySQLBibleSource(runner: owner())
        let schema = try await source.resolveSchema()
        let version = try await source.listVersions(schema)[0]
        let rows = try await source.verses(of: version, schema)
        #expect(rows.count == 6)
        for (got, expected) in zip(rows, ToolFixtures.smallVerses()) {
            #expect(got.bookOrder == expected.bookOrder && got.chapter == expected.chapter && got.verse == expected.verse)
            #expect(Array((got.text ?? "").unicodeScalars) == Array((expected.text ?? "").unicodeScalars), "\(got.bookOrder):\(got.chapter):\(got.verse)")
        }
        #expect(rows[0].text?.contains("\t") == true && rows[0].text?.contains("\n") == true && rows[0].text?.contains("\\") == true)
        #expect(rows[1].text?.unicodeScalars.contains("\u{0323}") == true)      // stacked marks not normalised
    }

    @Test func anEmptyResultIsAnEmptyListNotAnError() async throws {
        let server = owner()
        server.rawOverride["FROM `verses` WHERE"] = ""
        let source = MySQLBibleSource(runner: server)
        let schema = try await source.resolveSchema()
        let rows = try await source.verses(of: try await source.listVersions(schema)[0], schema)
        #expect(rows.isEmpty)
        let none = FakeMySQLServer(versions: [])
        let empty = MySQLBibleSource(runner: none)
        #expect(try await empty.listVersions(try await empty.resolveSchema()).isEmpty)
    }

    @Test func nullAndEmptyTextAreKeptDistinct() async throws {
        let server = owner()
        server.rawOverride["FROM `verses` WHERE"] = "1\t1\t1\tNULL\n1\t1\t2\t\n1\t1\t3\t\(hex("x"))\n"
        let source = MySQLBibleSource(runner: server)
        let schema = try await source.resolveSchema()
        let rows = try await source.verses(of: try await source.listVersions(schema)[0], schema)
        #expect(rows.map(\.text) == [nil, "", "x"])
    }

    @Test func everyStatementSentIsAPlainReadOnlySelect() async throws {
        let server = owner()
        let source = MySQLBibleSource(runner: server)
        let schema = try await source.resolveSchema()
        let versions = try await source.listVersions(schema)
        _ = try await source.verses(of: versions[0], schema)
        _ = try await source.bookNames(schema)
        #expect(server.statements.count == 5)
        for sql in server.statements {
            #expect(ReadOnlyStatement.isAllowed(sql), "\(sql)")
            #expect(sql.lowercased().hasPrefix("select "))
        }
        // Text is always fetched as hex of the utf8mb4 conversion, never as raw client output.
        let verseQuery = try #require(server.statements.first { $0.contains("FROM `verses` WHERE") })
        #expect(verseQuery.contains("HEX(CONVERT(`text` USING utf8mb4))") && verseQuery.contains("`version_id` = 1 ") && verseQuery.contains("ORDER BY `book_order`, `chapter`, `verse`"))
        #expect(server.statements.filter { $0.contains("`text`") }.allSatisfy { $0.contains("HEX(CONVERT(`text` USING utf8mb4))") })
        #expect(!ReadOnlyStatement.isAllowed("DROP TABLE verses"))
        #expect(!ReadOnlyStatement.isAllowed("SELECT 1; DROP TABLE verses"))
        #expect(!ReadOnlyStatement.isAllowed("SELECT * INTO OUTFILE '/tmp/x' FROM verses"))
        #expect(!ReadOnlyStatement.isAllowed("UPDATE verses SET text = ''"))
        #expect(ReadOnlyStatement.isAllowed("SHOW TABLES"))
    }

    @Test func hostileNamesAndKeysCannotBreakOutOfAStatement() async throws {
        #expect(throws: MySQLError.self) { try MySQLBibleSource.quote("verses`; DROP TABLE x; --") }
        #expect(throws: MySQLError.self) { try MySQLBibleSource.quote("") }
        #expect(try MySQLBibleSource.quote("verse_text") == "`verse_text`")
        #expect(throws: MySQLError.self) { try MySQLBibleSource.literal("1 OR 1=1", numeric: true) }
        #expect(try MySQLBibleSource.literal("12", numeric: true) == "12")
        // A code is sent as hex bytes, so a quote or a backslash in it is inert.
        #expect(try MySQLBibleSource.literal("A'B\\C", numeric: false) == "_utf8mb4 0x" + hex("A'B\\C"))
        // A column that really has such a name (named by hand) is refused before any statement is built from it.
        let hostile = "text`; DROP TABLE verses; --"
        let server = owner()
        server.schemaRows = FakeMySQLServer.ownerSchema.map { $0[1] == "text" ? [$0[0], hostile, $0[2]] : $0 }
        let source = MySQLBibleSource(runner: server, mapping: MySQLSchemaMapping(overrides: ["verses.text": hostile]))
        let schema = try await source.resolveSchema()
        await #expect(throws: MySQLError.self) {
            _ = try await source.verses(of: VersionSummary(key: "1", code: "x", name: nil, language: nil, verseCount: 1, bookCount: 1, chapterCount: 1), schema)
        }
        #expect(server.statements.allSatisfy { !$0.contains("DROP TABLE") })
    }

    @Test func unreadableOutputIsReportedNotGuessed() async throws {
        let base = owner()
        func attempt(_ needle: String, _ output: String) async -> MySQLError? {
            let server = owner()
            server.rawOverride[needle] = output
            do {
                let source = MySQLBibleSource(runner: server)
                let schema = try await source.resolveSchema()
                _ = try await source.verses(of: try await source.listVersions(schema)[0], schema)
                return nil
            } catch let error as MySQLError { return error } catch { return nil }
        }
        _ = base
        // A line with the wrong number of fields (a warning that reached standard output, say).
        #expect(await attempt("FROM `verses` WHERE", "mysql: [Warning] Using a password on the command line interface can be insecure.\n") != nil)
        // Odd length, a non-hex character, and bytes that are not UTF-8.
        #expect(await attempt("FROM `verses` WHERE", "1\t1\t1\tABC\n") != nil)
        #expect(await attempt("FROM `verses` WHERE", "1\t1\t1\tZZ\n") != nil)
        let invalid = await attempt("FROM `verses` WHERE", "1\t1\t1\tFFFE\n")
        #expect(invalid?.message.contains("UTF-8") == true)
        // A number that is not a number.
        #expect(await attempt("FROM `verses` WHERE", "one\t1\t1\t41\n") != nil)
    }

    @Test func columnsThatCannotBeFoundAreListedAndCanBeNamedByHand() async throws {
        let server = owner()
        server.schemaRows = FakeMySQLServer.ownerSchema.map { $0[1] == "text" ? [$0[0], "scripture_body_x", $0[2]] : $0 }
        do {
            _ = try await MySQLBibleSource(runner: server).resolveSchema()
            Issue.record("expected a schema error")
        } catch let error as MySQLError {
            #expect(error.message.contains("scripture_body_x") && error.message.contains("--map verses.text=<column>"))
        }
        let mapped = MySQLSchemaMapping(overrides: ["verses.text": "scripture_body_x"])
        #expect(try await MySQLBibleSource(runner: server, mapping: mapped).resolveSchema().versesText == "scripture_body_x")
        // A name that does not exist is refused with the real column list.
        do {
            _ = try await MySQLBibleSource(runner: server, mapping: MySQLSchemaMapping(overrides: ["verses.text": "nope"])).resolveSchema()
            Issue.record("expected a schema error")
        } catch let error as MySQLError { #expect(error.message.contains("nope") && error.message.contains("scripture_body_x")) }
    }

    @Test func missingTablesAreNamed() async throws {
        let server = owner()
        server.schemaRows = FakeMySQLServer.ownerSchema.filter { $0[0] != "verses" }
        do { _ = try await MySQLBibleSource(runner: server).resolveSchema(); Issue.record("expected an error") }
        catch let error as MySQLError { #expect(error.message.contains("verses") && error.message.contains("books, versions")) }
        let empty = FakeMySQLServer(schemaRows: [])
        do { _ = try await MySQLBibleSource(runner: empty).resolveSchema(); Issue.record("expected an error") }
        catch let error as MySQLError { #expect(error.message.contains("no tables")) }
    }

    @Test func aNumericVersionLinkNeedsAnIdColumn() async throws {
        let server = owner()
        server.schemaRows = FakeMySQLServer.ownerSchema.filter { !($0[0] == "versions" && $0[1] == "id") }
        do { _ = try await MySQLBibleSource(runner: server).resolveSchema(); Issue.record("expected an error") }
        catch let error as MySQLError { #expect(error.message.contains("versions.id")) }
    }

    @Test func aTableNameCaseDifferenceIsAccepted() async throws {
        let server = owner()
        server.schemaRows = FakeMySQLServer.ownerSchema.map { [$0[0].capitalized] + Array($0.dropFirst()) }
        let schema = try await MySQLBibleSource(runner: server).resolveSchema()
        #expect(schema.versesTable == "Verses" && schema.versionsTable == "Versions")
    }
}
