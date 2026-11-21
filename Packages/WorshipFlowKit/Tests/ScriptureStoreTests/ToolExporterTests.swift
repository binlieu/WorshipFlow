// LIB-004b: rows from the database -> translation file, with the validation report. Synthetic text only.
import Testing
import Foundation
import ScriptureEngine
@testable import ScriptureStore

@Suite struct ToolExporterTests {
    private func meta(language: String? = "vi") -> ExportMetadata { var m = ExportMetadata(); m.language = language; return m }
    private func build(_ rows: [RawVerse], metadata: ExportMetadata? = nil, names: [Int: String] = [:]) throws -> (file: TranslationFile, report: ExportReport) {
        try TranslationExporter.build(code: "VI1934", versionName: "Test version", rows: rows, bookNames: names, metadata: metadata ?? meta(), sourceDescription: "fake database")
    }

    @Test func booksAreMappedByOrderToTheCanonAndTextIsExact() throws {
        let (file, report) = try build(ToolFixtures.smallVerses())
        #expect(Set(file.books.keys) == ["GEN", "JHN", "REV"])
        #expect(file.books["GEN"]?["1"]?["1"] == ToolFixtures.nasty)
        #expect(Array((file.books["GEN"]?["1"]?["2"] ?? "").unicodeScalars) == Array(ToolFixtures.stacked.unicodeScalars))
        #expect(file.books["JHN"]?["3"]?["16"] == "synthetic sixteen")
        #expect(file.books["REV"]?["22"]?["21"] == "synthetic last")
        #expect(report.verseCount == 6 && report.bookCount == 3 && report.chapterCount == 3 && report.partial)
        // It survives the real encoder and decoder as well.
        let again = try TranslationLoader.decode(from: file.encoded())
        #expect(again == file)
        #expect(again.books["GEN"]?["1"]?["1"] == ToolFixtures.nasty)
    }

    @Test func metadataNeverInventsAnything() throws {
        let (file, _) = try build(ToolFixtures.smallVerses())
        let m = file.metadata
        #expect(m.id == "VI1934" && m.name == "Test version" && m.abbreviation == "VI1934" && m.language == "vi")
        #expect(m.copyright == "not stated" && m.license == "not stated")
        #expect(m.isPublicDomain == false && m.ownerApproval == nil)
        #expect(m.sourceURL == "fake database")
        var set = meta()
        set.id = "VI1925"; set.name = "Kinh"; set.abbreviation = "KT"; set.copyright = "© someone"; set.licence = "owner says free"
        set.source = "the owner's database"; set.isPublicDomain = true
        set.ownerApproved = true; set.ownerApprovalDate = "2026-11-20"; set.ownerApprovalNote = "approved"
        let m2 = try build(ToolFixtures.smallVerses(), metadata: set).file.metadata
        #expect(m2.id == "VI1925" && m2.name == "Kinh" && m2.abbreviation == "KT" && m2.copyright == "© someone" && m2.license == "owner says free")
        #expect(m2.sourceURL == "the owner's database" && m2.isPublicDomain)
        #expect(m2.ownerApproval == OwnerApproval(approved: true, date: "2026-11-20", note: "approved"))
        // Blank flags count as not given.
        var blank = meta(); blank.copyright = "   "; blank.licence = ""
        #expect(try build(ToolFixtures.smallVerses(), metadata: blank).file.metadata.copyright == "not stated")
    }

    @Test func languageIsRequired() throws {
        #expect(throws: MySQLError.self) { try build(ToolFixtures.smallVerses(), metadata: meta(language: nil)) }
        #expect(throws: MySQLError.self) { try build(ToolFixtures.smallVerses(), metadata: meta(language: "  ")) }
    }

    @Test func emptyNullAndBadRowsAreSkippedAndCounted() throws {
        let rows = ToolFixtures.smallVerses() + [
            RawVerse(bookOrder: 1, chapter: 2, verse: 1, text: "   \n"),
            RawVerse(bookOrder: 1, chapter: 2, verse: 2, text: nil),
            RawVerse(bookOrder: 0, chapter: 1, verse: 1, text: "book zero"),
            RawVerse(bookOrder: 67, chapter: 1, verse: 1, text: "book sixty-seven"),
            RawVerse(bookOrder: 67, chapter: 1, verse: 2, text: "again"),
            RawVerse(bookOrder: 2, chapter: 0, verse: 1, text: "chapter zero"),
            RawVerse(bookOrder: 2, chapter: 1, verse: 0, text: "verse zero"),
        ]
        let (file, report) = try build(rows)
        #expect(report.verseCount == 6 && report.rowsRead == 13)
        #expect(report.emptyVerses == ["GEN 2:1", "GEN 2:2"] && report.nullTexts == 1)
        #expect(report.skippedBadBook == [0: 1, 67: 2] && report.skippedBadNumber == 2)
        #expect(file.books["GEN"]?["2"] == nil && file.books["EXO"] == nil)
        #expect(report.hasProblems)
        let text = report.lines.joined(separator: "\n")
        #expect(text.contains("2 verses are empty") && text.contains("book_order is not 1 to 66") && text.contains("below 1"))
    }

    @Test func duplicatesKeepTheFirstAndConflictsAreSaidLoudly() throws {
        let rows = [
            RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "first"),
            RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "first"),
            RawVerse(bookOrder: 1, chapter: 1, verse: 2, text: "two"),
            RawVerse(bookOrder: 1, chapter: 1, verse: 2, text: "TWO, different"),
        ]
        let (file, report) = try build(rows)
        #expect(file.books["GEN"]?["1"]?["1"] == "first" && file.books["GEN"]?["1"]?["2"] == "two")
        #expect(report.duplicates == ["GEN 1:1"] && report.conflictingDuplicates == ["GEN 1:2"])
        #expect(report.lines.joined().contains("PROBLEM"))
    }

    @Test func gapsInVersesAndChaptersAreReportedNotFilled() throws {
        let rows = [
            RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "a"), RawVerse(bookOrder: 1, chapter: 1, verse: 4, text: "d"),
            RawVerse(bookOrder: 1, chapter: 3, verse: 1, text: "x"),
        ]
        let (file, report) = try build(rows)
        #expect(report.verseGaps == ["GEN 1: 2,3"] && report.chapterGaps == ["GEN 2"])
        #expect(file.books["GEN"]?["1"]?["2"] == nil)
    }

    @Test func aCompleteTableMatchesItsBuiltInVersification() throws {
        let kjv = try build(ToolFixtures.full(.kjv, language: "en"), metadata: meta(language: "en"))
        #expect(kjv.file.metadata.versification == "KJV" && kjv.file.metadata.versificationTable == nil)
        #expect(kjv.report.verseCount == 31_102 && !kjv.report.partial && !kjv.report.hasProblems)
        let vi = try build(ToolFixtures.full(.vi1925))
        #expect(vi.file.metadata.versification == "VI1925" && vi.file.metadata.versificationTable == nil)
        #expect(vi.report.verseCount == 31_081)
        // The numbers the engine reads back are the built-in ones: nothing reported missing or beyond the table.
        let loaded = TranslationLoader.validate(vi.file)
        #expect(loaded.report.versesBeyondTable == 0 && loaded.report.missingVerseCount == 0 && loaded.report.missingChapterCount == 0)
        #expect(loaded.translation.versification == .vi1925)
    }

    @Test func aTableThatMatchesNeitherIsDerivedAndStoredInTheFile() throws {
        // KJV with one chapter that ends one verse early and one that has a skipped number.
        var rows = ToolFixtures.full(.kjv, language: "en")
        rows.removeAll { $0.bookOrder == 43 && $0.chapter == 3 && $0.verse == 36 }           // John 3 ends at 35
        rows.removeAll { $0.bookOrder == 1 && $0.chapter == 1 && $0.verse == 5 }             // Genesis 1 skips 5
        let (file, report) = try build(rows, metadata: meta(language: "en"))
        #expect(file.metadata.versification == "DERIVED-VI1934")
        let table = try #require(file.metadata.versificationTable)
        #expect(table["JHN"]?[2] == [35, 35])
        #expect(table["GEN"]?[0] == [30, 31])
        #expect(report.versification == "DERIVED-VI1934" && report.versificationReason.contains("derived"))
        #expect(file.metadata.versificationNote?.contains("derived") == true)
        let loaded = TranslationLoader.validate(file)
        #expect(loaded.translation.versification.highestVerse(book: BookID("JHN"), chapter: 3) == 35)
        #expect(loaded.translation.versification.verseCount(book: BookID("GEN"), chapter: 1) == 30)
        #expect(loaded.report.versesBeyondTable == 0 && loaded.report.missingVerseCount == 0)
        #expect(report.verseGaps.contains("GEN 1: 5"))
    }

    @Test func versificationCanBeForcedOrDerivedOnRequest() throws {
        var m = meta(language: "en")
        m.versification = "derived"
        #expect(try build(ToolFixtures.full(.kjv, language: "en"), metadata: m).file.metadata.versificationTable != nil)
        m.versification = "VI1925"
        let forced = try build(ToolFixtures.full(.kjv, language: "en"), metadata: m)
        #expect(forced.file.metadata.versification == "VI1925" && forced.file.metadata.versificationTable == nil)
        #expect(forced.report.versificationReason.contains("--versification"))
        m.versification = "NOPE"
        #expect(throws: MySQLError.self) { try build(ToolFixtures.full(.kjv, language: "en"), metadata: m) }
    }

    @Test func wrongCharacterSetTextIsFlagged() throws {
        let rows = [RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "Ä\u{0090}á»©c ChÃºa Trá»\u{009D}i"), RawVerse(bookOrder: 1, chapter: 1, verse: 2, text: "clean")]
        let (_, report) = try build(rows)
        #expect(report.suspectedMojibake == 1)
        #expect(report.lines.joined().contains("character set"))
        #expect(try build(ToolFixtures.smallVerses()).report.suspectedMojibake == 0)     // real Vietnamese text is not flagged
    }

    @Test func bookNamesThatDisagreeWithTheCanonAreFlagged() throws {
        let ok = try build(ToolFixtures.smallVerses(), names: [1: "Genesis", 43: "John", 66: "Revelation"])
        #expect(ok.report.bookNameMismatches.isEmpty)
        let bad = try build(ToolFixtures.smallVerses(), names: [1: "Exodus", 43: "john"])
        #expect(bad.report.bookNameMismatches.count == 1 && bad.report.bookNameMismatches[0].contains("book_order 1"))
    }

    @Test func nothingUsableIsAnErrorNotAnEmptyFile() throws {
        #expect(throws: MySQLError.self) { try build([]) }
        #expect(throws: MySQLError.self) { try build([RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: " ")]) }
    }
}
