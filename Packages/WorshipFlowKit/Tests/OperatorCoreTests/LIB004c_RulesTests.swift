// LIB-004c: the pure rules of the scripture interface: how many characters a slide may hold under a theme, what the operator
// is offered while typing a book name, and how a verse slide becomes a slide on the screens (the reference is its last line).
import Testing
import Foundation
import Domain
import ScriptureEngine
@testable import OperatorCore

@Suite struct LIB004c_RulesTests {
    // MARK: the theme's limits

    @Test func theDefaultThemeGivesASmallButUsableLimit() {
        let options = ScriptureSlideLimits.options(theme: .fullScreen, bilingual: false, versesPerSlide: 1)
        let limit = options.maxCharacters ?? 0
        #expect(limit >= 40 && limit <= 160, "\(limit)")
        #expect(options.versesPerSlide == 1 && options.verseNumbers == .none)
    }

    @Test func smallerTextOrATallerBoxHoldsMore() {
        let base = ScriptureSlideLimits.options(theme: .fullScreen, bilingual: false, versesPerSlide: 1).maxCharacters ?? 0
        var small = Theme.fullScreen
        small.primary.style.fontSize = 42
        #expect((ScriptureSlideLimits.options(theme: small, bilingual: false, versesPerSlide: 1).maxCharacters ?? 0) > base * 2)
        var tall = Theme.fullScreen
        tall.primary.frame.height = 0.6
        #expect((ScriptureSlideLimits.options(theme: tall, bilingual: false, versesPerSlide: 1).maxCharacters ?? 0) > base)
    }

    @Test func twoTranslationsAreHeldToTheSmallerOfTheTwoBoxes() {
        var theme = Theme.fullScreen
        theme.primary.frame = NormalizedRect(x: 0.05, y: 0.1, width: 0.9, height: 0.4)
        theme.secondary = TextBlock(style: Theme.fullScreen.primary.style, frame: NormalizedRect(x: 0.05, y: 0.55, width: 0.9, height: 0.15))
        let one = ScriptureSlideLimits.options(theme: theme, bilingual: false, versesPerSlide: 1).maxCharacters ?? 0
        let two = ScriptureSlideLimits.options(theme: theme, bilingual: true, versesPerSlide: 1).maxCharacters ?? 0
        #expect(two < one)
    }

    @Test func aThemeWithNoSecondBoxStillWorksForTwoTranslations() {
        var theme = Theme.fullScreen
        theme.secondary = nil
        #expect((ScriptureSlideLimits.options(theme: theme, bilingual: true, versesPerSlide: 1).maxCharacters ?? 0) > 0)
    }

    @Test func severalVersesOnASlideAreNumberedSoTheyCanBeTold() {
        let options = ScriptureSlideLimits.options(theme: .fullScreen, bilingual: false, versesPerSlide: 3)
        #expect(options.versesPerSlide == 3 && options.verseNumbers == .superscript)
        #expect(ScriptureSlideLimits.options(theme: .fullScreen, bilingual: false, versesPerSlide: 0).versesPerSlide == 1)
    }

    // MARK: suggestions while typing

    @Test func typingTheStartOfABookOffersItsNameInEnglishAndVietnamese() {
        #expect(ScriptureSuggestions.suggest("joh").map(\.name).contains("John"))
        #expect(ScriptureSuggestions.suggest("Gi").map(\.name).contains("Giăng"))
        #expect(ScriptureSuggestions.suggest("gia").map(\.name).contains("Giăng"), "diacritics are not needed")
    }

    @Test func aNumberedBookIsOfferedFromItsNumberAndLetters() {
        #expect(ScriptureSuggestions.suggest("1 jo").map(\.name).contains("1 John"))
        #expect(ScriptureSuggestions.suggest("1jo").map(\.name).contains("1 John"))
    }

    @Test func aCompletionReplacesTheTypedNameAndLeavesRoomForTheNumbers() throws {
        let s = try #require(ScriptureSuggestions.suggest("joh").first { $0.name == "John" })
        #expect(s.completion == "John ")
        #expect(s.book == BookID("JHN"))
    }

    @Test func noSuggestionsOnceTheNumbersStartOrForNothingTyped() {
        #expect(ScriptureSuggestions.suggest("").isEmpty)
        #expect(ScriptureSuggestions.suggest("John 3").isEmpty)
        #expect(ScriptureSuggestions.suggest("John 3:16-18").isEmpty)
        #expect(ScriptureSuggestions.suggest("zzzz").isEmpty)
        #expect(ScriptureSuggestions.suggest("j").count <= ScriptureSuggestions.limit)
    }

    // MARK: a verse slide on the screens

    @Test func theReferenceIsTheLastLineOfEachSideAndEachSideKeepsItsOwnLanguage() {
        let slide = ScriptureSlide(content: SlideContent(primary: "Primary words.", secondary: "Lời thứ hai."), reference: "John 3:16",
                                   secondaryReference: "Giăng 3:16", verses: [VerseRef(book: BookID("JHN"), chapter: 3, verse: 16)],
                                   partIndex: nil, partCount: nil)
        let content = ScriptureSlideContent.content(for: slide)
        #expect(content.primary == "Primary words.\nJohn 3:16")
        #expect(content.secondary == "Lời thứ hai.\nGiăng 3:16")
    }

    @Test func aMissingSideStaysMissing() {
        let slide = ScriptureSlide(content: SlideContent(primary: "Only this side."), reference: "John 3:18", secondaryReference: nil,
                                   verses: [VerseRef(book: BookID("JHN"), chapter: 3, verse: 18)], partIndex: nil, partCount: nil)
        let content = ScriptureSlideContent.content(for: slide)
        #expect(content.primary == "Only this side.\nJohn 3:18")
        #expect(content.secondary == nil)
    }
}
