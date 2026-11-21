// SLIDE-004 acceptance tests (PRES-05, PRES-10). Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct ReflowTests {
    let hymn = """
    Verse 1
    Amazing grace, how sweet the sound
    That saved a wretch like me
    I once was lost, but now am found
    Was blind, but now I see

    Chorus:
    My chains are gone
    I've been set free


    Twas grace that taught my heart to fear
    And grace my fears relieved
    """

    @Test func blankLinesSeparateSectionsAndLabelsNameThem() {
        let sections = Reflow.sections(from: hymn)
        #expect(sections.map(\.name) == ["Verse 1", "Chorus", nil])
        #expect(sections.map(\.lines.count) == [4, 2, 2])
        #expect(sections[1].lines.first == "My chains are gone")
    }

    @Test func recognisesEnglishAndVietnameseLabels() {
        for label in ["Verse 2", "verse 10:", "CHORUS", "Pre-Chorus", "Bridge", "Tag", "Intro", "Outro", "Ending", "Refrain",
                      "Câu 1", "Điệp khúc", "Điệp Khúc:", "Đoạn 2", "Kết"] {
            let sections = Reflow.sections(from: "\(label)\nline one\nline two")
            #expect(sections.count == 1, "\(label)")
            #expect(sections.first?.name == label.trimmingCharacters(in: CharacterSet(charactersIn: ":")), "\(label)")
            #expect(sections.first?.lines == ["line one", "line two"], "\(label)")
        }
    }

    /// A lyric line that merely starts with a label word is not a label.
    @Test func ordinaryLinesAreNotLabels() {
        let sections = Reflow.sections(from: "Bridge over troubled water\nsecond line")
        #expect(sections.first?.name == nil)
        #expect(sections.first?.lines.count == 2)
    }

    @Test func trimsLinesAndIgnoresLeadingAndTrailingBlankLines() {
        let sections = Reflow.sections(from: "\n\n   first  \n\tsecond\t\n\n\n")
        #expect(sections.count == 1)
        #expect(sections[0].lines == ["first", "second"])
        #expect(Reflow.sections(from: " \n \n").isEmpty)
    }

    @Test func splitsSectionsAtTheChosenLineCount() {
        let slides = Reflow.slides(from: Reflow.sections(from: hymn), maxLines: 2)
        #expect(slides.map(\.lines.count) == [2, 2, 2, 2])
        #expect(slides.map(\.sectionIndex) == [0, 0, 1, 2])
        // A section never shares a slide with another section.
        let three = Reflow.slides(from: Reflow.sections(from: hymn), maxLines: 3)
        #expect(three.map(\.lines.count) == [3, 1, 2, 2])
    }

    /// PRES-05: forty pasted lines lose nothing at any line count.
    @Test func fortyLinesLoseNothing() {
        let text = (1...40).map { "line \($0)" }.joined(separator: "\n")
        for max in 1...6 {
            let slides = Reflow.slides(from: Reflow.sections(from: text), maxLines: max)
            #expect(slides.flatMap(\.lines) == (1...40).map { "line \($0)" })
            #expect(slides.allSatisfy { $0.lines.count <= max && !$0.lines.isEmpty })
        }
        #expect(Reflow.slides(from: Reflow.sections(from: text), maxLines: 0).count == 40)   // treated as 1
    }

    /// PRES-05: moving a break re-splits without losing text.
    @Test func movingABreakKeepsEveryLine() {
        let slides = Reflow.slides(from: Reflow.sections(from: hymn), maxLines: 2)
        let all = slides.flatMap(\.lines)
        let pulled = Reflow.moveBreak(in: slides, after: 0, by: 1)       // one line moves up into slide 0
        #expect(pulled.map(\.lines.count) == [3, 1, 2, 2])
        #expect(pulled.flatMap(\.lines) == all)
        let pushed = Reflow.moveBreak(in: slides, after: 0, by: -1)      // one line moves down into slide 1
        #expect(pushed.map(\.lines.count) == [1, 3, 2, 2])
        #expect(pushed.flatMap(\.lines) == all)
    }

    @Test func aSlideEmptiedByAMoveIsRemoved() {
        let slides = Reflow.slides(from: Reflow.sections(from: hymn), maxLines: 2)
        let merged = Reflow.moveBreak(in: slides, after: 0, by: 5)       // clamped: takes both lines
        #expect(merged.map(\.lines.count) == [4, 2, 2])
        #expect(merged.flatMap(\.lines) == slides.flatMap(\.lines))
    }

    /// A break between two sections cannot be moved; sections stay intact.
    @Test func breaksDoNotCrossSections() {
        let slides = Reflow.slides(from: Reflow.sections(from: hymn), maxLines: 2)
        #expect(Reflow.moveBreak(in: slides, after: 1, by: 1) == slides)
        #expect(Reflow.moveBreak(in: slides, after: 99, by: 1) == slides)
        #expect(Reflow.moveBreak(in: slides, after: -1, by: 1) == slides)
    }

    /// PRES-10: a second-language text with the same shape pairs line for line.
    @Test func pairsSecondLanguageBySectionAndLine() {
        let english = "Verse 1\nAmazing grace, how sweet the sound\nThat saved a wretch like me\n\nChorus\nMy chains are gone"
        let vietnamese = "Câu 1\nÂn điển lạ lùng thay\nĐã cứu vớt tôi\n\nĐiệp khúc\nXiềng xích đã tan"
        let result = Reflow.contents(primary: english, secondary: vietnamese, maxLines: 1)
        #expect(result.map(\.sectionName) == ["Verse 1", "Verse 1", "Chorus"])
        #expect(result.map(\.content.primary) == ["Amazing grace, how sweet the sound", "That saved a wretch like me", "My chains are gone"])
        #expect(result.map(\.content.secondary) == ["Ân điển lạ lùng thay", "Đã cứu vớt tôi", "Xiềng xích đã tan"])
    }

    @Test func multiLineSlidesJoinWithNewlines() {
        let result = Reflow.contents(primary: "a\nb\nc", secondary: "x\ny\nz", maxLines: 2)
        #expect(result.map(\.content.primary) == ["a\nb", "c"])
        #expect(result.map(\.content.secondary) == ["x\ny", "z"])
    }

    /// Uneven second-language text never loses a line and never invents one.
    @Test func unevenSecondLanguageLosesNothing() {
        let short = Reflow.contents(primary: "a\nb\nc", secondary: "x", maxLines: 1)
        #expect(short.map(\.content.secondary) == ["x", nil, nil])
        let long = Reflow.contents(primary: "a\nb", secondary: "x\ny\nz\nw", maxLines: 1)
        #expect(long.map(\.content.primary) == ["a", "b"])
        #expect(long.map(\.content.secondary) == ["x", "y\nz\nw"])
        let none = Reflow.contents(primary: "a\nb", secondary: nil, maxLines: 2)
        #expect(none.map(\.content) == [SlideContent(primary: "a\nb", secondary: nil)])
    }

    /// Round trip: slides back to editable text, then split again, gives the same slides.
    @Test func textRoundTrips() {
        let first = Reflow.contents(primary: hymn, secondary: nil, maxLines: 2)
        let text = Reflow.text(from: first.map { (name: $0.sectionName, content: $0.content) }, language: .primary)
        let second = Reflow.contents(primary: text, secondary: nil, maxLines: 2)
        #expect(second.map(\.sectionName) == first.map(\.sectionName))
        #expect(second.map(\.content) == first.map(\.content))
    }
}
