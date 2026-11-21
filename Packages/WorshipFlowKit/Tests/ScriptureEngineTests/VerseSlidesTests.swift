// LIB-004: verses -> slides.
import Testing
import Domain
@testable import ScriptureEngine

@Suite struct VerseSlidesTests {
    private let kjv = Fixtures.kjv()
    private func ranges(_ text: String) -> [VerseRange] { ReferenceParser().parse(text).ranges }
    private func ref(_ b: String, _ c: Int, _ v: Int) -> VerseRef { VerseRef(book: BookID(b), chapter: c, verse: v) }

    @Test func oneVersePerSlideByDefault() {
        let p = VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv)
        #expect(p.slides.count == 3)
        #expect(p.slides.map(\.reference) == ["John 3:16", "John 3:17", "John 3:18"])
        #expect(p.slides[0].content.primary == "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
        #expect(p.slides.allSatisfy { $0.content.secondary == nil })
        #expect(p.slides.map(\.verses) == [[ref("JHN", 3, 16)], [ref("JHN", 3, 17)], [ref("JHN", 3, 18)]])
        #expect(p.title == "John 3:16\u{2013}18 (KJV)")
        #expect(p.report.messages.isEmpty)
    }

    @Test func severalVersesPerSlide() {
        let p = VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv, options: SlideOptions(versesPerSlide: 2))
        #expect(p.slides.count == 2)
        #expect(p.slides.map(\.reference) == ["John 3:16\u{2013}17", "John 3:18"])
        #expect(p.slides[0].content.primary.hasPrefix("For God so loved"))
        #expect(p.slides[0].content.primary.contains("be saved. ") == false)
        #expect(p.slides[0].content.primary.contains("perish, but have everlasting life. For God sent"))
        let all = VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv, options: SlideOptions(versesPerSlide: 9))
        #expect(all.slides.count == 1)
        #expect(all.slides[0].reference == "John 3:16\u{2013}18")
        // Nonsense values act as one verse per slide.
        #expect(VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv, options: SlideOptions(versesPerSlide: 0)).slides.count == 3)
    }

    @Test func verseNumbersAreOptional() {
        func first(_ style: VerseNumberStyle, per: Int = 1) -> String {
            VerseSlides.build(ranges: ranges("John 3:16-17"), primary: kjv, options: SlideOptions(versesPerSlide: per, verseNumbers: style)).slides[0].content.primary
        }
        #expect(first(.none).hasPrefix("For God so loved"))
        #expect(first(.plain).hasPrefix("16 For God so loved"))
        #expect(first(.superscript).hasPrefix("\u{00B9}\u{2076} For God so loved"))
        let two = first(.plain, per: 2)
        #expect(two.contains("everlasting life. 17 For God sent"))
        #expect(VerseSlides.build(ranges: ranges("Ps 23:1"), primary: kjv, options: SlideOptions(verseNumbers: .superscript)).slides[0].content.primary.hasPrefix("\u{00B9} The LORD"))
        #expect(VerseSlides.build(ranges: ranges("John 11:35"), primary: kjv, options: SlideOptions(verseNumbers: .superscript)).slides[0].content.primary.hasPrefix("\u{00B3}\u{2075} Jesus"))
    }

    @Test func aLongVerseIsSplitAndTheReferenceSaysWhichPart() {
        let p = VerseSlides.build(ranges: ranges("John 3:16"), primary: kjv, options: SlideOptions(maxCharacters: 80))
        #expect(p.slides.count == 2)
        #expect(p.slides.map(\.reference) == ["John 3:16a", "John 3:16b"])
        #expect(p.slides.allSatisfy { $0.content.primary.count <= 80 })
        #expect(p.slides.map(\.content.primary).joined(separator: " ") == "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.")
        #expect(p.slides.map(\.partIndex) == [0, 1])
        #expect(p.slides.map(\.partCount) == [2, 2])
        #expect(p.slides[0].content.primary.hasSuffix("Son,"))
        // A verse that fits is not lettered.
        let short = VerseSlides.build(ranges: ranges("John 11:35"), primary: kjv, options: SlideOptions(maxCharacters: 80))
        #expect(short.slides.map(\.reference) == ["John 11:35"])
        #expect(short.slides[0].partIndex == nil)
    }

    @Test func threeWayLongVerseGetsABC() {
        let p = VerseSlides.build(ranges: ranges("John 3:18"), primary: kjv, options: SlideOptions(maxCharacters: 60))
        #expect(p.slides.map(\.reference) == ["John 3:18a", "John 3:18b", "John 3:18c"])
        #expect(p.slides.allSatisfy { $0.content.primary.count <= 60 })
    }

    @Test func groupingNeverExceedsTheCharacterLimit() {
        let options = SlideOptions(versesPerSlide: 3, maxCharacters: 200)
        let p = VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv, options: options)
        #expect(p.slides.allSatisfy { $0.content.primary.count <= 200 })
        #expect(p.slides.map(\.verses.count).reduce(0, +) >= 3)
        // 16 (143 characters) and 17 (110) do not fit together in 200.
        #expect(p.slides.first?.reference == "John 3:16")
        let roomy = VerseSlides.build(ranges: ranges("John 3:16-17"), primary: kjv, options: SlideOptions(versesPerSlide: 3, maxCharacters: 400))
        #expect(roomy.slides.map(\.reference) == ["John 3:16\u{2013}17"])
    }

    @Test func secondTranslationIsPairedVerseByVerse() {
        let vi = Fixtures.second()
        let p = VerseSlides.build(ranges: ranges("John 3:16-17"), primary: kjv, secondary: vi)
        #expect(p.slides.count == 2)
        #expect(p.slides[0].content.secondary == "Câu thử JHN 3:16 của bản thứ hai.")
        #expect(p.slides[1].content.secondary == "Câu thử JHN 3:17 của bản thứ hai.")
        #expect(p.slides[0].reference == "John 3:16")
        #expect(p.slides[0].secondaryReference == "Giăng 3:16")
        #expect(p.title == "John 3:16\u{2013}17 (KJV / TH2)")
        #expect(p.report.missingInSecondary.isEmpty)
    }

    @Test func vietnameseCanBeThePrimary() {
        let p = VerseSlides.build(ranges: ranges("John 3:16"), primary: Fixtures.second(), secondary: kjv)
        #expect(p.slides[0].reference == "Giăng 3:16")
        #expect(p.slides[0].secondaryReference == "John 3:16")
        #expect(p.slides[0].content.primary == "Câu thử JHN 3:16 của bản thứ hai.")
        #expect(p.slides[0].content.secondary?.hasPrefix("For God so loved") == true)
        #expect(p.title == "Giăng 3:16 (TH2 / KJV)")
    }

    @Test func aVerseMissingFromTheSecondTranslationLeavesThatSideEmptyAndIsReported() {
        let vi = Fixtures.second(skipping: ["JHN 3:17"])
        let p = VerseSlides.build(ranges: ranges("John 3:16-18"), primary: kjv, secondary: vi)
        #expect(p.slides.count == 3)
        #expect(p.slides[1].content.secondary == nil)
        #expect(p.slides[1].secondaryReference == nil)
        #expect(p.slides[0].content.secondary != nil && p.slides[2].content.secondary != nil)
        #expect(p.report.missingInSecondary == [ref("JHN", 3, 17)])
        #expect(p.report.messages.contains { $0.contains("John 3:17") && $0.contains("TH2") })
    }

    @Test func aVerseMissingFromThePrimaryIsSkippedAndReported() {
        let p = VerseSlides.build(ranges: ranges("John 3:16-20"), primary: kjv, secondary: Fixtures.second())
        #expect(p.slides.count == 3)
        #expect(p.report.missingInPrimary == [ref("JHN", 3, 19), ref("JHN", 3, 20)])
        #expect(p.report.messages.contains { $0.contains("John 3:19") && $0.contains("KJV") })
        #expect(p.title == "John 3:16\u{2013}20 (KJV / TH2)")
        // Nothing at all: no slides, still a report.
        let none = VerseSlides.build(ranges: ranges("Mark 1:1"), primary: kjv)
        #expect(none.slides.isEmpty)
        #expect(none.report.missingInPrimary == [ref("MRK", 1, 1)])
    }

    @Test func wholeChapterRequestsReportEverythingMissing() {
        let p = VerseSlides.build(ranges: ranges("Ps 23"), primary: kjv)
        #expect(p.slides.map(\.reference) == ["Psalms 23:1", "Psalms 23:2", "Psalms 23:3"])
        #expect(p.report.missingInPrimary.map(\.verse) == [4, 5, 6])
        #expect(p.title == "Psalms 23 (KJV)")
    }

    @Test func aSplitVerseSplitsBothSidesIntoTheSameNumberOfParts() {
        let p = VerseSlides.build(ranges: ranges("John 3:16"), primary: kjv, secondary: Fixtures.second(language: "en"),
                                  options: SlideOptions(maxCharacters: 20))
        #expect(p.slides.count >= 2)
        #expect(p.slides.first?.content.secondary != nil)
        #expect(p.slides.map(\.reference).first == "John 3:16a")
        // The secondary text is shorter than the primary, so it runs out first; the rest of the parts are empty (nil).
        #expect(p.slides.compactMap(\.content.secondary).joined(separator: " ") == "Second text JHN 3:16.")
        #expect(p.slides.last?.content.secondary == nil)
        #expect(p.slides.last?.secondaryReference == nil)
        // The longer side decides how many slides there are.
        #expect(p.slides.allSatisfy { $0.content.primary.count <= 20 || !$0.content.primary.contains(" ") })
    }

    @Test func pairingIsByReferenceAcrossDifferentVersifications() {
        // Exodus 12 has 51 verses in the KJV and 50 in the 1925 text; verse 51 has no partner.
        var en = TranslationFile(metadata: TranslationMetadata(id: "e", name: "E", language: "en", abbreviation: "EN"), books: [:])
        var vi = TranslationFile(metadata: TranslationMetadata(id: "v", name: "V", language: "vi", abbreviation: "VI", versification: "VI1925"), books: [:])
        for v in 49...51 { en.setVerse("en \(v)", book: BookID("EXO"), chapter: 12, verse: v) }
        for v in 49...50 { vi.setVerse("vi \(v)", book: BookID("EXO"), chapter: 12, verse: v) }
        let p = VerseSlides.build(ranges: ranges("Exodus 12:49-51"), primary: TranslationLoader.validate(en).translation,
                                  secondary: TranslationLoader.validate(vi).translation)
        #expect(p.slides.map(\.content.secondary) == ["vi 49", "vi 50", nil])
        #expect(p.report.missingInSecondary == [ref("EXO", 12, 51)])
    }

    @Test func slidesCarryNoObjectsAndAreOrdinaryContent() {
        let p = VerseSlides.build(ranges: ranges("John 3:16"), primary: kjv, secondary: Fixtures.second())
        let content: SlideContent = p.slides[0].content
        #expect(content.objects.isEmpty)
        #expect(content.isBlank == false)
    }

    @Test func noRangesNoSlides() {
        let p = VerseSlides.build(ranges: [], primary: kjv)
        #expect(p.slides.isEmpty)
        #expect(p.title == "")
    }

    @Test func severalReferencesInOnePresentation() {
        let p = VerseSlides.build(ranges: ranges("John 3:16; Rom 8:28"), primary: kjv)
        #expect(p.slides.map(\.reference) == ["John 3:16", "Romans 8:28"])
        #expect(p.title == "John 3:16; Romans 8:28 (KJV)")
    }
}
