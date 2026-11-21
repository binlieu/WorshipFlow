// FIX-F item 9 (LIB-004c): `ScriptureModel.referenceText(of:)` writes stored ranges with the default (KJV) table; the text is then read
// against the primary translation's table. Does the round trip change the bounds on VI1925 numbering (whole chapters, psalms with a
// title verse, chapters whose highest verse number is above their verse count)? Exhaustive over both built-in tables.
import Testing
import Foundation
import Domain
import ScriptureEngine
@testable import OperatorCore

@MainActor
@Suite struct FIXF_RoundTripTests {
    private func spec(_ range: VerseRange) -> ScriptureItemSpec {
        ScriptureItemSpec(label: "x", ranges: [.init(book: range.book.rawValue, startChapter: range.start.chapter, startVerse: range.start.verse,
                                                     endChapter: range.end.chapter, endVerse: range.end.verse)], primaryCode: "p", secondaryCode: nil)
    }

    private func roundTrip(_ range: VerseRange, table: Versification) -> [VerseRange] {
        let text = ScriptureModel.referenceText(of: spec(range))
        return ReferenceParser(language: .english, versification: table).parse(text).ranges
    }

    private func mismatches(table: Versification) -> [String] {
        var out: [String] = []
        for (book, chapters) in table.books.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for (index, info) in chapters.enumerated() where info.highest > 0 {
                let chapter = index + 1
                let whole = VerseRange(book: book, startChapter: chapter, startVerse: 1, endChapter: chapter, endVerse: info.highest)
                let back = roundTrip(whole, table: table)
                if back != [whole] { out.append("\(table.id) \(book.rawValue) \(chapter): 1-\(info.highest) -> \(back.map { "\($0.start.chapter):\($0.start.verse)-\($0.end.chapter):\($0.end.verse)" })") }
                if info.highest > 1 {
                    let part = VerseRange(book: book, startChapter: chapter, startVerse: 2, endChapter: chapter, endVerse: info.highest)
                    if roundTrip(part, table: table) != [part] { out.append("\(table.id) \(book.rawValue) \(chapter): 2-\(info.highest) changes") }
                }
            }
        }
        return out
    }

    @Test func everyWholeChapterAndEveryPartialRangeSurvivesTheRoundTripOnKJV() {
        let bad = mismatches(table: .kjv)
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) changed, first: \(bad.prefix(5))"))
    }

    @Test func everyWholeChapterAndEveryPartialRangeSurvivesTheRoundTripOnVI1925() {
        let bad = mismatches(table: .vi1925)
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) changed, first: \(bad.prefix(8))"))
    }

    @Test func aPsalmWithATitleVerseOnVI1925SurvivesTheRoundTrip() throws {
        // Psalm 3 has a title counted as verse 1 in the 1925 numbering: its chapter is longer than in the KJV table.
        let table = Versification.vi1925
        for chapter in [3, 51, 52, 54, 60] {
            let highest = try #require(table.highestVerse(book: BookID("PSA"), chapter: chapter))
            let whole = VerseRange(book: BookID("PSA"), startChapter: chapter, startVerse: 1, endChapter: chapter, endVerse: highest)
            #expect(roundTrip(whole, table: table) == [whole], "Psalm \(chapter)")
        }
    }

    /// A range stored under one table and read back under the other (the primary was changed after the item was made): the bounds may
    /// move to the other table's own chapter end, and a verse the other table lacks is refused in plain words (a problem), but a verse that exists in the other table is never lost silently.
    private func lostVerses(from a: Versification, to b: Versification) -> [String] {
        var out: [String] = []
        for (book, chapters) in a.books.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            for (index, info) in chapters.enumerated() where info.highest > 0 {
                let chapter = index + 1
                let whole = VerseRange(book: book, startChapter: chapter, startVerse: 1, endChapter: chapter, endVerse: info.highest)
                let wanted = Set(whole.verses(in: b))
                let outcome = ReferenceParser(language: .english, versification: b).parse(ScriptureModel.referenceText(of: spec(whole)))
                if !outcome.problems.isEmpty { continue }              // refused in plain words ("no such verse"), not changed silently
                let got = Set(outcome.ranges.flatMap { $0.verses(in: b) })
                if !wanted.isSubset(of: got) { out.append("\(a.id)->\(b.id) \(book.rawValue) \(chapter)") }
            }
        }
        return out
    }

    @Test func aRangeStoredUnderOneTableAndReadUnderTheOtherIsRefusedOrKeepsEveryVerseTheOtherHas() {
        let bad = lostVerses(from: .kjv, to: .vi1925) + lostVerses(from: .vi1925, to: .kjv)
        #expect(bad.isEmpty, Comment(rawValue: "\(bad.count) lose a verse, first: \(bad.prefix(8))"))
    }
}
