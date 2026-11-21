// LIB-004b: additions to the engine that the store and importer need: a translation file may carry its own
// verse-count table, a translation can be built from stored rows, and the loader can decode without validating.
// Synthetic text only.
import Testing
import Foundation
@testable import ScriptureEngine

@Suite struct VersificationTableTests {
    private func meta(table: [String: [[Int]]]?, name: String? = "TEST-TABLE") -> TranslationMetadata {
        var m = TranslationMetadata(id: "t", name: "T", language: "en", abbreviation: "T", versification: name)
        m.versificationTable = table
        return m
    }

    @Test func tableRoundTripsThroughJSONAndIsAbsentWhenNil() throws {
        var file = Fixtures.file(metadata: meta(table: ["JHN": [[3, 3], [4, 5]]]))
        file.setVerse("a", book: BookID("JHN"), chapter: 1, verse: 1)
        let data = try file.encoded()
        let back = try JSONDecoder().decode(TranslationFile.self, from: data)
        #expect(back.metadata.versificationTable == ["JHN": [[3, 3], [4, 5]]])
        let plain = try Fixtures.file().encoded()
        #expect(!String(decoding: plain, as: UTF8.self).contains("versificationTable"))
    }

    @Test func loaderUsesTheFilesOwnTable() throws {
        // Genesis 1 has three verses here (the KJV has 31); chapter 2 has two with a gap (highest 3).
        var file = TranslationFile(metadata: meta(table: ["GEN": [[3, 3], [2, 3]]]), books: [:])
        file.setBook(BookID("GEN"), chapters: [1: [1: "a", 2: "b", 3: "c"], 2: [1: "d", 3: "e"]])
        let loaded = TranslationLoader.validate(file)
        #expect(loaded.translation.versification.id == "TEST-TABLE")
        #expect(loaded.translation.versification.verseCount(book: BookID("GEN"), chapter: 1) == 3)
        #expect(loaded.translation.versification.highestVerse(book: BookID("GEN"), chapter: 2) == 3)
        #expect(loaded.report.missingVerseCount == 0)
        #expect(loaded.report.versesBeyondTable == 0)
        #expect(loaded.report.missingChapters.isEmpty)
        #expect(loaded.translation.text(for: VerseRef(book: BookID("GEN"), chapter: 2, verse: 3)) == "e")
    }

    @Test func versesPastTheFilesTableWidenIt() throws {
        var file = TranslationFile(metadata: meta(table: ["GEN": [[3, 3]]]), books: [:])
        file.setBook(BookID("GEN"), chapters: [1: [1: "a", 2: "b", 3: "c", 4: "d"]])
        let loaded = TranslationLoader.validate(file)
        #expect(loaded.report.versesBeyondTable == 1)
        #expect(loaded.translation.versification.highestVerse(book: BookID("GEN"), chapter: 1) == 4)
    }

    @Test func aChapterWithNoVersesInTheTableIsNotReportedMissing() throws {
        // Chapter 2 does not exist in this table (a derived table has such holes).
        var file = TranslationFile(metadata: meta(table: ["GEN": [[1, 1], [0, 0], [1, 1]]]), books: [:])
        file.setBook(BookID("GEN"), chapters: [1: [1: "a"], 3: [1: "b"]])
        let loaded = TranslationLoader.validate(file)
        #expect(loaded.report.missingChapters.isEmpty)
        #expect(loaded.report.missingVerseCount == 0)
    }

    @Test func malformedTablesAreRejectedWithAMessageAndFallBackToTheNamedTable() throws {
        let bad: [[String: [[Int]]]] = [
            ["GEN": [[5, 3]]],            // count above highest
            ["GEN": [[1]]],               // wrong arity
            ["GEN": [[-1, 2]]],           // negative
            ["XXX": [[1, 1]]],            // not a canon book
        ]
        for table in bad {
            var file = TranslationFile(metadata: meta(table: table, name: "KJV"), books: [:])
            file.setBook(BookID("GEN"), chapters: [1: [1: "a"]])
            let loaded = TranslationLoader.validate(file)
            #expect(loaded.translation.versification.id == "KJV", "\(table)")
            #expect(loaded.report.messages.contains { $0.contains("table") }, "\(table)")
        }
    }

    @Test func versificationInitAndRepresentationRoundTrip() throws {
        let v = try #require(Versification(id: "X", table: ["JHN": [[3, 3], [4, 5]], "GEN": [[1, 1]]]))
        #expect(v.books[BookID("JHN")] == [.init(count: 3, highest: 3), .init(count: 4, highest: 5)])
        #expect(v.tableRepresentation == ["JHN": [[3, 3], [4, 5]], "GEN": [[1, 1]]])
        #expect(Versification(id: "X", table: ["JHN": [[4, 3]]]) == nil)
        #expect(Versification(id: "Y", table: Versification.vi1925.tableRepresentation)?.books == Versification.vi1925.books)
        #expect(Versification.kjv.tableRepresentation.count == 66)
    }

    @Test func derivedTableCountsVersesAndKeepsGaps() throws {
        let gen = BookID("GEN"), jhn = BookID("JHN")
        let refs = [VerseRef(book: gen, chapter: 1, verse: 1), VerseRef(book: gen, chapter: 1, verse: 2),
                    VerseRef(book: gen, chapter: 3, verse: 1), VerseRef(book: gen, chapter: 3, verse: 4),
                    VerseRef(book: jhn, chapter: 1, verse: 1)]
        let v = Versification.derived(id: "D", from: refs)
        #expect(v.books[gen] == [.init(count: 2, highest: 2), .init(count: 0, highest: 0), .init(count: 2, highest: 4)])
        #expect(v.books[jhn] == [.init(count: 1, highest: 1)])
        #expect(v.books[BookID("MAT")] == nil)
    }

    @Test func decodeReadsAFileWithoutValidatingIt() throws {
        let data = try Fixtures.file().encoded()
        let file = try TranslationLoader.decode(from: data)
        #expect(file == Fixtures.file())
        #expect(throws: TranslationLoadError.self) { try TranslationLoader.decode(from: Data("{}".utf8)) }
        #expect(throws: TranslationLoadError.self) { try TranslationLoader.decode(from: Data("nope".utf8)) }
    }

    @Test func aTranslationCanBeBuiltFromRows() throws {
        let rows = Fixtures.kjvVerses.map { (ref: VerseRef(book: BookID($0.0), chapter: $0.1, verse: $0.2), text: $0.3) }
        let t = Translation(metadata: Fixtures.kjvMetadata, versification: .kjv, verses: rows)
        #expect(t.verseCount == Fixtures.kjvVerses.count)
        #expect(t.text(for: VerseRef(book: BookID("JHN"), chapter: 11, verse: 35)) == "Jesus wept.")
        #expect(t.allVerses().first?.ref == VerseRef(book: BookID("GEN"), chapter: 1, verse: 1))
        // The same slides come out of a translation built this way as from a loaded one.
        let range = VerseRange(book: BookID("JHN"), startChapter: 3, startVerse: 16, endChapter: 3, endVerse: 17)
        #expect(VerseSlides.build(ranges: [range], primary: t).slides.map(\.content) ==
                VerseSlides.build(ranges: [range], primary: Fixtures.kjv()).slides.map(\.content))
    }

    @Test func searchHitsAndQueryTermsAreConstructibleOutsideTheModule() throws {
        #expect(ScriptureSearchIndex.queryTerms("Đức \"Chúa Trời\" lov") == ["duc", "chua troi", "lov"])
        let hit = ScriptureSearchHit(ref: VerseRef(book: BookID("JHN"), chapter: 3, verse: 16), text: "For God so loved the world",
                                     terms: ["loved"], snippetLength: 100)
        #expect(hit.snippet == "For God so loved the world")
    }
}
