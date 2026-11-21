// LIB-004: per-translation versification. The 1925 Vietnamese table comes from the owner's database export
// (counts only): 31,081 verses against 31,102 for the KJV, differing in 46 of 1,189 chapters.
import Testing
@testable import ScriptureEngine

@Suite struct VersificationTests {
    @Test func kjvTotals() {
        #expect(Versification.kjv.id == "KJV")
        #expect(Versification.kjv.totalChapters == 1189)
        #expect(Versification.kjv.totalVerses == 31102)
    }

    @Test func vi1925Totals() {
        #expect(Versification.vi1925.id == "VI1925")
        #expect(Versification.vi1925.totalChapters == 1189)
        #expect(Versification.vi1925.totalVerses == 31081)
    }

    @Test func fiveDifferingChaptersAndThreeGaps() {
        func vi(_ b: String, _ c: Int) -> (count: Int?, highest: Int?) {
            (Versification.vi1925.verseCount(book: BookID(b), chapter: c), Versification.vi1925.highestVerse(book: BookID(b), chapter: c))
        }
        func kjv(_ b: String, _ c: Int) -> Int? { Versification.kjv.verseCount(book: BookID(b), chapter: c) }
        #expect(kjv("EXO", 12) == 51); #expect(vi("EXO", 12).count == 50)
        #expect(kjv("NUM", 29) == 40); #expect(vi("NUM", 29).count == 39)
        #expect(kjv("NUM", 30) == 16); #expect(vi("NUM", 30).count == 17)
        #expect([38, 39, 40, 41].map { kjv("JOB", $0) } == [41, 30, 24, 34])
        #expect([38, 39, 40, 41].map { vi("JOB", $0).count } == [38, 38, 28, 25])
        #expect(kjv("EZK", 20) == 49); #expect(vi("EZK", 20).count == 44)
        #expect(kjv("EZK", 21) == 32); #expect(vi("EZK", 21).count == 37)
        #expect(kjv("3JN", 1) == 14); #expect(vi("3JN", 1).count == 15)
        #expect(kjv("REV", 12) == 17); #expect(vi("REV", 12).count == 18)
        // Gaps: fewer verses than the highest verse number.
        #expect(vi("1CH", 8) == (36, 40))
        #expect(vi("EST", 1) == (21, 22))
        #expect(vi("MAT", 17) == (26, 27))
        // An unchanged chapter.
        #expect(vi("JHN", 3) == (36, 36))
    }

    @Test func differencesBetweenTheTwoTables() {
        let diffs = Versification.differences(Versification.kjv, Versification.vi1925)
        #expect(diffs.count == 46)
        #expect(diffs.first?.book == BookID("EXO"))
        #expect(diffs.first?.chapter == 12)
        #expect(diffs.contains { $0.book == BookID("JOB") && $0.chapter == 41 && $0.a.count == 34 && $0.b.count == 25 })
        #expect(Versification.differences(Versification.kjv, Versification.kjv).isEmpty)
    }

    @Test func namedLookup() {
        #expect(Versification.named("KJV") == Versification.kjv)
        #expect(Versification.named("vi1925") == Versification.vi1925)
        #expect(Versification.named("nope") == nil)
    }

    @Test func extendedWidensWithoutLosingTheRest() {
        let wide = Versification.kjv.extended(with: [BookID("3JN"): [15]])
        #expect(wide.highestVerse(book: BookID("3JN"), chapter: 1) == 15)
        #expect(wide.verseCount(book: BookID("3JN"), chapter: 1) == 15)
        #expect(wide.totalVerses == 31103)
        #expect(wide.highestVerse(book: BookID("JHN"), chapter: 3) == 36)
        #expect(wide.totalChapters == 1189)
        // Never narrows.
        #expect(Versification.kjv.extended(with: [BookID("3JN"): [3]]).highestVerse(book: BookID("3JN"), chapter: 1) == 14)
    }

    @Test func unknownBookOrChapter() {
        #expect(Versification.kjv.verseCount(book: BookID("XXX"), chapter: 1) == nil)
        #expect(Versification.kjv.chapterCount(book: BookID("JHN")) == 21)
        #expect(Versification.kjv.verseCount(book: BookID("JHN"), chapter: 22) == nil)
    }
}
