// LIB-004: reference parsing, validation and formatting.
import Testing
@testable import ScriptureEngine

@Suite struct ReferenceParserTests {
    private let parser = ReferenceParser()
    private func r(_ b: String, _ c1: Int, _ v1: Int, _ c2: Int, _ v2: Int) -> VerseRange {
        VerseRange(book: BookID(b), startChapter: c1, startVerse: v1, endChapter: c2, endVerse: v2)
    }
    private func ranges(_ text: String) -> [VerseRange] {
        let out = parser.parse(text)
        #expect(out.problems.isEmpty, "\(text): \(out.problems.map(\.message))")
        return out.ranges
    }

    @Test func singleVerseAndRanges() {
        #expect(ranges("John 3:16") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("John 3:16-18") == [r("JHN", 3, 16, 3, 18)])
        #expect(ranges("John 3:16\u{2013}18") == [r("JHN", 3, 16, 3, 18)])
        #expect(ranges("John 3:16\u{2014}18") == [r("JHN", 3, 16, 3, 18)])
        #expect(ranges("john3:16") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("Jn 3.16") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("1 John 1:9") == [r("1JN", 1, 9, 1, 9)])
        #expect(ranges("Psalm 119:105") == [r("PSA", 119, 105, 119, 105)])
    }

    @Test func verseLists() {
        #expect(ranges("John 3:16,18,20-22") == [r("JHN", 3, 16, 3, 16), r("JHN", 3, 18, 3, 18), r("JHN", 3, 20, 3, 22)])
        #expect(ranges("John 3:16, 18") == [r("JHN", 3, 16, 3, 16), r("JHN", 3, 18, 3, 18)])
        #expect(ranges("John 3:16,4:2") == [r("JHN", 3, 16, 3, 16), r("JHN", 4, 2, 4, 2)])
    }

    @Test func adjacentAndOverlappingRangesMerge() {
        #expect(ranges("John 3:16,17-18") == [r("JHN", 3, 16, 3, 18)])
        #expect(ranges("John 3:16-18,17-20") == [r("JHN", 3, 16, 3, 20)])
        #expect(ranges("John 3:16,16") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("John 3:20,16") == [r("JHN", 3, 20, 3, 20), r("JHN", 3, 16, 3, 16)])
    }

    @Test func wholeChaptersAndCrossChapterRanges() {
        #expect(ranges("John 3") == [r("JHN", 3, 1, 3, 36)])
        #expect(ranges("Ps 23") == [r("PSA", 23, 1, 23, 6)])
        #expect(ranges("John 3-4") == [r("JHN", 3, 1, 4, 54)])
        #expect(ranges("John 3,5") == [r("JHN", 3, 1, 3, 36), r("JHN", 5, 1, 5, 47)])
        #expect(ranges("John 3:16-4:2") == [r("JHN", 3, 16, 4, 2)])
        #expect(ranges("John 3:16\u{2013}4:2") == [r("JHN", 3, 16, 4, 2)])
    }

    @Test func singleChapterBooksTakeVersesNotChapters() {
        #expect(ranges("Jude 5") == [r("JUD", 1, 5, 1, 5)])
        #expect(ranges("Jude 5-7") == [r("JUD", 1, 5, 1, 7)])
        #expect(ranges("Jude 1:5") == [r("JUD", 1, 5, 1, 5)])
        #expect(ranges("Obadiah 3") == [r("OBA", 1, 3, 1, 3)])
        #expect(ranges("3 John 4,6") == [r("3JN", 1, 4, 1, 4), r("3JN", 1, 6, 1, 6)])
    }

    @Test func severalReferences() {
        #expect(ranges("John 3:16; Rom 8:28") == [r("JHN", 3, 16, 3, 16), r("ROM", 8, 28, 8, 28)])
        #expect(ranges("John 3:16; 4:2") == [r("JHN", 3, 16, 3, 16), r("JHN", 4, 2, 4, 2)])
        #expect(ranges("John 3:16; 1 John 1:9") == [r("JHN", 3, 16, 3, 16), r("1JN", 1, 9, 1, 9)])
        #expect(ranges("John 3:16;") == [r("JHN", 3, 16, 3, 16)])
    }

    @Test func vietnameseReferences() {
        #expect(ranges("Giăng 3:16") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("Thi Thiên 23:1-3") == [r("PSA", 23, 1, 23, 3)])
        #expect(ranges("1 Giăng 1:9") == [r("1JN", 1, 9, 1, 9)])
        #expect(ranges("Rô-ma 8:28; Khải-huyền 21:4") == [r("ROM", 8, 28, 8, 28), r("REV", 21, 4, 21, 4)])
        #expect(ranges("Giu-đe 5") == [r("JUD", 1, 5, 1, 5)])
    }

    @Test func strayPunctuationAndWhitespace() {
        #expect(ranges("  John 3:16  ") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("\n(John 3:16).") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges(",John 3:16;;") == [r("JHN", 3, 16, 3, 16)])
        #expect(ranges("John   3 : 16 - 18") == [r("JHN", 3, 16, 3, 18)])
        #expect(ranges("Gen. 1:1") == [r("GEN", 1, 1, 1, 1)])
        #expect(ranges("\u{201C}John 3:16\u{201D}") == [r("JHN", 3, 16, 3, 16)])
    }

    @Test func chapterAndVerseLimitsAreReported() {
        let a = parser.parse("John 22")
        #expect(a.ranges.isEmpty)
        #expect(a.problems.first?.message.contains("John has 21 chapters") == true)
        #expect(a.problems.first?.kind == .chapterOutOfRange)
        let b = parser.parse("John 3:37")
        #expect(b.problems.first?.message.contains("John 3 has 36 verses") == true)
        #expect(b.problems.first?.kind == .verseOutOfRange)
        #expect(parser.parse("Jude 26").problems.first?.message.contains("Jude has 25 verses") == true)
        #expect(parser.parse("John 3:16-4:55").problems.first?.message.contains("John 4 has 54 verses") == true)
        #expect(parser.parse("Psalm 151").problems.first?.message.contains("Psalms has 150 chapters") == true)
    }

    @Test func otherErrorsAreOperatorReadableAndNeverCrash() {
        #expect(parser.parse("John 3:18-16").problems.first?.kind == .backwards)
        #expect(parser.parse("John 3:0").problems.first?.message.contains("start at 1") == true)
        #expect(parser.parse("John 0").problems.first?.message.contains("start at 1") == true)
        #expect(parser.parse("Foo 3:1").problems.first?.kind == .unknownBook)
        #expect(parser.parse("Foo 3:1").problems.first?.message.contains("Foo") == true)
        #expect(parser.parse("John").problems.first?.kind == .missingLocation)
        #expect(parser.parse("John").problems.first?.message.contains("21 chapters") == true)
        #expect(parser.parse("John 3:16-").problems.first?.kind == .syntax)
        #expect(parser.parse("John 3:x").problems.first?.kind == .syntax)
        #expect(parser.parse("John 3:16a").problems.first?.kind == .syntax)
        #expect(parser.parse("John 3:").problems.first?.kind == .syntax)
        #expect(parser.parse("").problems.first?.kind == .empty)
        #expect(parser.parse("  ;; ").problems.first?.kind == .empty)
        #expect(parser.parse("3:16").problems.first?.kind == .missingBook)
        #expect(parser.parse("John 99999999999999999999").problems.isEmpty == false)
        for junk in ["::", "---", "1", "1:", "John 3:16-4:", "\u{0000}", "📖", "John 3,,5", "John -3"] {
            _ = parser.parse(junk)
        }
    }

    @Test func nothingIsCorrectedSilently() {
        // The valid part is kept, the bad part is reported, and nothing is rewritten.
        let out = parser.parse("John 3:16; John 3:99; Rom 8:28")
        #expect(out.ranges == [r("JHN", 3, 16, 3, 16), r("ROM", 8, 28, 8, 28)])
        #expect(out.problems.count == 1)
        #expect(out.problems[0].input == "John 3:99")
        #expect(out.isValid == false)
    }

    @Test func ambiguousBookNamesListBothCandidates() {
        let out = parser.parse("Phil 2:5")
        #expect(out.ranges.isEmpty)
        #expect(out.problems.first?.kind == .ambiguousBook)
        #expect(out.problems.first?.candidates == [BookID("PHP"), BookID("PHM")])
        #expect(out.problems.first?.message.contains("Philippians") == true)
        #expect(out.problems.first?.message.contains("Philemon") == true)
        let jud = parser.parse("Jud 3")
        #expect(jud.problems.first?.candidates == [BookID("JDG"), BookID("JUD")])
    }

    @Test func versificationCanBeWidenedForATranslation() {
        // Modern English Bibles have a 15th verse in 3 John; the KJV has 14.
        #expect(parser.parse("3 John 15").problems.isEmpty == false)
        let wide = Versification.kjv.extended(with: [BookID("3JN"): [15]])
        #expect(ReferenceParser(versification: wide).parse("3 John 15").problems.isEmpty)
        #expect(Versification.kjv.verseCount(book: BookID("3JN"), chapter: 1) == 14)
    }

    @Test func theParsersVersificationDecidesWhatIsInRange() {
        let vi = ReferenceParser(versification: .vi1925)
        #expect(parser.parse("Exodus 12:51").problems.isEmpty)
        #expect(vi.parse("Exodus 12:51").problems.first?.message.contains("Exodus 12 has 50 verses") == true)
        #expect(parser.parse("Job 41:30").problems.isEmpty)
        #expect(vi.parse("Job 41:30").problems.first?.kind == .verseOutOfRange)
        // Whole chapters follow the table in use.
        #expect(vi.parse("Job 41").ranges == [r("JOB", 41, 1, 41, 25)])
        #expect(parser.parse("Job 41").ranges == [r("JOB", 41, 1, 41, 34)])
        // 3 John has 15 verses in the 1925 text.
        #expect(vi.parse("3 John 15").problems.isEmpty)
        // A verse number inside a gap is accepted (1 Chronicles 8 has 36 verses, the highest is 40).
        #expect(vi.parse("1 Chronicles 8:40").problems.isEmpty)
        #expect(vi.parse("1 Chronicles 8:41").problems.isEmpty == false)
    }

    @Test func contextDecidesVietnameseAbbreviations() {
        #expect(ReferenceParser(language: .vietnamese, context: .vietnamese).parse("exo 1:1").ranges == [r("EZR", 1, 1, 1, 1)])
        #expect(ReferenceParser(context: .english).parse("exo 1:1").ranges == [r("EXO", 1, 1, 1, 1)])
        let auto = parser.parse("exo 1:1")
        #expect(auto.ranges.isEmpty)
        #expect(auto.problems.first?.kind == .ambiguousBook)
        #expect(auto.problems.first?.candidates == [BookID("EXO"), BookID("EZR")])
    }

    @Test func messagesUseTheParsersLanguage() {
        let vi = ReferenceParser(language: .vietnamese)
        #expect(vi.parse("Giăng 22").problems.first?.message.contains("Giăng has 21 chapters") == true)
    }
}

@Suite struct ReferenceFormatterTests {
    private func r(_ b: String, _ c1: Int, _ v1: Int, _ c2: Int, _ v2: Int) -> VerseRange {
        VerseRange(book: BookID(b), startChapter: c1, startVerse: v1, endChapter: c2, endVerse: v2)
    }

    @Test func verseRanges() {
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 3, 18)) == "John 3:16\u{2013}18")
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 3, 18), language: .vietnamese) == "Giăng 3:16\u{2013}18")
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 3, 16)) == "John 3:16")
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 4, 2)) == "John 3:16\u{2013}4:2")
        #expect(ReferenceFormatter.format(r("PSA", 23, 1, 23, 3), language: .vietnamese) == "Thi-thiên 23:1\u{2013}3")
        #expect(ReferenceFormatter.format(r("1JN", 1, 9, 1, 9)) == "1 John 1:9")
    }

    @Test func wholeChaptersAndSingleChapterBooks() {
        #expect(ReferenceFormatter.format(r("JHN", 3, 1, 3, 36)) == "John 3")
        #expect(ReferenceFormatter.format(r("JHN", 3, 1, 4, 54)) == "John 3\u{2013}4")
        #expect(ReferenceFormatter.format(r("JHN", 3, 1, 3, 35)) == "John 3:1\u{2013}35")
        #expect(ReferenceFormatter.format(r("JUD", 1, 5, 1, 5)) == "Jude 5")
        #expect(ReferenceFormatter.format(r("JUD", 1, 5, 1, 7)) == "Jude 5\u{2013}7")
        #expect(ReferenceFormatter.format(r("JUD", 1, 1, 1, 25)) == "Jude 1\u{2013}25")
    }

    @Test func listsOfRanges() {
        #expect(ReferenceFormatter.format([r("JHN", 3, 16, 3, 16), r("JHN", 3, 20, 3, 22)]) == "John 3:16, 20\u{2013}22")
        #expect(ReferenceFormatter.format([r("JHN", 3, 16, 3, 16), r("ROM", 8, 28, 8, 28)]) == "John 3:16; Romans 8:28")
        #expect(ReferenceFormatter.format([r("JHN", 3, 16, 3, 16), r("JHN", 4, 2, 4, 2)]) == "John 3:16; 4:2")
        #expect(ReferenceFormatter.format([]) == "")
    }

    @Test func partOfAVerse() {
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 3, 16), part: 0) == "John 3:16a")
        #expect(ReferenceFormatter.format(r("JHN", 3, 16, 3, 16), language: .vietnamese, part: 1) == "Giăng 3:16b")
    }

    @Test func formattedTextParsesBackToTheSameRange() {
        let parser = ReferenceParser()
        let samples = [r("JHN", 3, 16, 3, 18), r("JHN", 3, 1, 3, 36), r("JHN", 3, 16, 4, 2), r("JUD", 1, 5, 1, 7),
                       r("PSA", 119, 105, 119, 105), r("1CO", 13, 1, 13, 13), r("JHN", 3, 1, 4, 54)]
        for language in [ScriptureLanguage.english, .vietnamese] {
            for range in samples {
                let text = ReferenceFormatter.format(range, language: language)
                #expect(parser.parse(text).ranges == [range], "\(text)")
            }
        }
    }
}
