// SLIDE-004: extra edge cases for the reflow rules (written by the implementer).
import Testing
import Foundation
@testable import Domain

@Suite struct ReflowEdgeTests {
    @Test func labelAloneNamesTheNextBlock() {
        let sections = Reflow.sections(from: "Chorus\n\nHallelujah\nHallelujah")
        #expect(sections == [ReflowSection(name: "Chorus", lines: ["Hallelujah", "Hallelujah"])])
    }

    @Test func labelMidBlockIsALyricLine() {
        let sections = Reflow.sections(from: "one\nChorus\ntwo")
        #expect(sections == [ReflowSection(name: nil, lines: ["one", "Chorus", "two"])])
    }

    @Test func textSkipsSlidesWithoutTheRequestedLanguage() {
        let slides: [(name: String?, content: SlideContent)] = [
            ("Verse 1", SlideContent(primary: "a", secondary: "x")),
            ("Verse 1", SlideContent(primary: "b", secondary: nil)),
            ("Chorus", SlideContent(primary: "c", secondary: "z")),
        ]
        #expect(Reflow.text(from: slides, language: .secondary) == "Verse 1\nx\n\nChorus\nz")
        #expect(Reflow.text(from: slides, language: .primary) == "Verse 1\na\nb\n\nChorus\nc")
    }

    @Test func surplusSecondarySectionsJoinTheLastSlide() {
        let result = Reflow.contents(primary: "a\n\nb", secondary: "x\n\ny\n\nz", maxLines: 1)
        #expect(result.map(\.content.secondary) == ["x", "y\nz"])
    }
}
