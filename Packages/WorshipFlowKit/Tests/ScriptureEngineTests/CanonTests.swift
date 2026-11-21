// LIB-004: canon rules. Totals are the checksum for the KJV versification.
import Testing
@testable import ScriptureEngine

@Suite struct CanonTests {
    @Test func sixtySixBooksInProtestantOrder() {
        #expect(Canon.books.count == 66)
        #expect(Canon.books.first?.id.rawValue == "GEN")
        #expect(Canon.books[38].id.rawValue == "MAL")
        #expect(Canon.books[39].id.rawValue == "MAT")
        #expect(Canon.books.last?.id.rawValue == "REV")
        #expect(Set(Canon.books.map(\.id)).count == 66)
        #expect(Canon.books.map(\.order) == Array(1...66))
    }

    @Test func totalsMatchTheKJV() {
        #expect(Canon.totalChapters == 1189)
        #expect(Canon.totalVerses == 31102)
        #expect(Canon.books[..<39].reduce(0) { $0 + $1.totalVerses } == 23145)
        #expect(Canon.books[39...].reduce(0) { $0 + $1.totalVerses } == 7957)
    }

    @Test func perBookTotals() {
        let expected: [String: Int] = [
            "GEN": 1533, "EXO": 1213, "LEV": 859, "NUM": 1288, "DEU": 959, "JOS": 658, "JDG": 618, "RUT": 85,
            "1SA": 810, "2SA": 695, "1KI": 816, "2KI": 719, "1CH": 942, "2CH": 822, "EZR": 280, "NEH": 406,
            "EST": 167, "JOB": 1070, "PSA": 2461, "PRO": 915, "ECC": 222, "SNG": 117, "ISA": 1292, "JER": 1364,
            "LAM": 154, "EZK": 1273, "DAN": 357, "HOS": 197, "JOL": 73, "AMO": 146, "OBA": 21, "JON": 48,
            "MIC": 105, "NAM": 47, "HAB": 56, "ZEP": 53, "HAG": 38, "ZEC": 211, "MAL": 55,
            "MAT": 1071, "MRK": 678, "LUK": 1151, "JHN": 879, "ACT": 1007, "ROM": 433, "1CO": 437, "2CO": 257,
            "GAL": 149, "EPH": 155, "PHP": 104, "COL": 95, "1TH": 89, "2TH": 47, "1TI": 113, "2TI": 83,
            "TIT": 46, "PHM": 25, "HEB": 303, "JAS": 108, "1PE": 105, "2PE": 61, "1JN": 105, "2JN": 13,
            "3JN": 14, "JUD": 25, "REV": 404,
        ]
        for book in Canon.books {
            #expect(book.totalVerses == expected[book.id.rawValue], "\(book.id.rawValue)")
        }
        #expect(expected.count == 66)
    }

    @Test func chapterCounts() {
        #expect(Canon.book(BookID("PSA"))?.chapterCount == 150)
        #expect(Canon.book(BookID("JHN"))?.chapterCount == 21)
        #expect(Canon.book(BookID("JUD"))?.chapterCount == 1)
        #expect(Canon.book(BookID("XXX")) == nil)
    }

    /// Spot checks taken from an independent source (see the report), not from the table under test.
    @Test func knownChapters() {
        func v(_ b: String, _ c: Int) -> Int? { Canon.book(BookID(b))?.verseCount(chapter: c) }
        #expect(v("PSA", 119) == 176)
        #expect(v("PSA", 117) == 2)
        #expect(v("PSA", 23) == 6)
        #expect(v("JHN", 3) == 36)
        #expect(v("GEN", 1) == 31)
        #expect(v("GEN", 35) == 29)
        #expect(v("NUM", 7) == 89)
        #expect(v("1KI", 8) == 66)
        #expect(v("EST", 10) == 3)
        #expect(v("LUK", 1) == 80)
        #expect(v("REV", 22) == 21)
        #expect(v("ROM", 16) == 27)
        #expect(v("JOL", 2) == 32)
        #expect(v("MAL", 4) == 6)
        #expect(v("3JN", 1) == 14)
        #expect(v("JER", 52) == 34)
        #expect(v("ISA", 66) == 24)
        #expect(v("JHN", 3) == 36)
        #expect(v("ACT", 19) == 41)
        #expect(v("MAT", 26) == 75)
        #expect(v("JHN", 22) == nil)
        #expect(v("JHN", 0) == nil)
    }

    @Test func singleChapterBooks() {
        let ids = Canon.books.filter { $0.chapterCount == 1 }.map(\.id.rawValue)
        #expect(ids == ["OBA", "PHM", "2JN", "3JN", "JUD"])
    }
}
