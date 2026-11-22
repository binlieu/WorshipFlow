// LIB-004c items 1 to 4: typing a reference, the verses and slides it makes, two translations side by side. Invented text only.
import Testing
import Foundation
import Domain
import ScriptureEngine
import ScriptureStore
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct LIB004c_PassageTests {
    func normalised(_ text: String) -> String { text.split(whereSeparator: \.isWhitespace).joined(separator: " ") }

    // MARK: the typed reference

    @Test func aReferenceTypedInEnglishAndInVietnameseResolvesToTheSamePassage() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16-17")
        let english = try #require(r.scripture.passage)
        await r.scripture.show("Giăng 3:16-17")
        let vietnamese = try #require(r.scripture.passage)
        #expect(english.spec.ranges == vietnamese.spec.ranges)
        #expect(english.slides.map(\.verses) == vietnamese.slides.map(\.verses))
        #expect(english.slides.map(\.content) == vietnamese.slides.map(\.content))
        #expect(english.slides.flatMap(\.verses).contains(VerseRef(book: BookID("JHN"), chapter: 3, verse: 16)))
        #expect(r.scripture.problem == nil)
    }

    @Test func anUnknownBookGivesAPlainProblemAndNoSlides() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("Psalm 23:1")
        #expect(r.scripture.passage != nil)
        await r.scripture.show("Zorgon 3:16")
        let problem = try #require(r.scripture.problem)
        #expect(problem.contains("Zorgon") && problem.contains("not a book"))
        #expect(r.scripture.passage == nil)
        #expect(r.workspace.openScripture == nil)
    }

    @Test func aVerseOutOfRangeGivesAPlainProblemAndNoSlides() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:99")
        #expect(r.scripture.problem?.contains("36 verses") == true, "\(String(describing: r.scripture.problem))")
        #expect(r.scripture.passage == nil && r.workspace.openScripture == nil)
        await r.scripture.show("John 40")
        #expect(r.scripture.problem?.contains("21 chapters") == true)
        #expect(r.scripture.passage == nil)
    }

    @Test func oneBadPartMeansNothingIsShownRatherThanHalfAPassage() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16; Zorgon 1")
        #expect(r.scripture.problem != nil && r.scripture.passage == nil)
    }

    @Test func aVerseThatTheTranslationLacksIsSaidPlainlyAndMakesNoSlides() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:30")        // inside the verse-count table, but not in the fixture
        let problem = try #require(r.scripture.problem)
        #expect(problem.contains("no text") && problem.contains("John 3:30"), Comment(rawValue: problem))
        #expect(r.scripture.passage == nil)
    }

    @Test func anEmptyFieldAsksForAReference() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("   ")
        #expect(r.scripture.problem?.contains("Type a reference") == true)
        #expect(r.scripture.passage == nil)
    }

    // MARK: splitting

    @Test func aLongPassageSplitsIntoSeveralSlidesAndEveryVerseAppearsOnceInOrder() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:1-18")
        let passage = try #require(r.scripture.passage)
        let limit = try #require(ScriptureSlideLimits.options(theme: .fullScreen, bilingual: false, versesPerSlide: 1).maxCharacters)
        #expect(passage.slides.count > 18, "each long verse takes more than one slide: \(passage.slides.count)")
        // The verses, de-duplicated in the order they appear, are 1 to 18.
        var order: [Int] = []
        for slide in passage.slides { for v in slide.verses where order.last != v.verse { order.append(v.verse) } }
        #expect(order == Array(1...18))
        // The parts of each verse, put back together, are exactly its text.
        for n in 1...18 {
            let parts = passage.slides.filter { $0.verses.map(\.verse) == [n] }
            #expect(normalised(parts.map(\.content.primary).joined(separator: " ")) == normalised(L4C.englishVerse(n)), "verse \(n)")
            #expect(parts.allSatisfy { $0.content.primary.count <= limit })
        }
    }

    @Test func aWiderThemeKeepsTheSamePassageOnFewerSlides() async throws {
        var wide = Theme.fullScreen
        wide.primary.style.fontSize = 40
        let narrow = try await L4C.rig()
        let roomy = try await L4C.rig(theme: wide)
        await narrow.scripture.show("John 3:1-4")
        await roomy.scripture.show("John 3:1-4")
        #expect((roomy.scripture.passage?.slides.count ?? 99) < (narrow.scripture.passage?.slides.count ?? 0))
    }

    @Test func severalVersesCanShareASlideWhenTheyFit() async throws {
        let r = try await L4C.rig(theme: .classicFullScreen)   // UI-005h: the built-in type is 119 pt, which holds about 55 characters; the Classic theme's 84 pt holds what this test was written for (was: L4C.rig())
        await r.scripture.setVersesPerSlide(2)
        await r.scripture.show("Psalm 23:1-3")
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.count == 2)
        #expect(passage.slides[0].verses.map(\.verse) == [1, 2] && passage.slides[1].verses.map(\.verse) == [3])
    }

    @Test func theReferenceIsOnEveryScreenSlide() async throws {
        let r = try await L4C.rig()
        await r.scripture.show("John 3:16")
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.count == passage.contents.count && passage.slides.count > 1)
        for (slide, content) in zip(passage.slides, passage.contents) {
            #expect(content.primary.hasSuffix("\n" + slide.reference))
        }
        #expect(passage.slides.map(\.reference).first == "John 3:16a")
    }

    // MARK: two translations

    @Test func twoTranslationsShareEachSlideInTheBilingualLayout() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("vi-test")
        await r.scripture.show("John 3:16")
        let passage = try #require(r.scripture.passage)
        let withSecond = passage.contents.filter { $0.secondary != nil }
        #expect(!withSecond.isEmpty)
        #expect(passage.contents.first?.secondary?.hasSuffix("Giăng 3:16a") == true, "\(String(describing: passage.contents.first?.secondary))")
        #expect(passage.spec.secondaryCode == "vi-test")
    }

    @Test func versesNumberedDifferentlyArePairedByNumberAndAMissingVerseShowsOneSideOnly() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("vi-test")
        await r.scripture.show("Exodus 12:49-51")       // English has 51 verses in the chapter, the 1925 text has 50
        let passage = try #require(r.scripture.passage)
        #expect(passage.slides.map(\.verses.first?.verse) == [49, 50, 51])
        #expect(passage.contents[1].secondary?.contains("câu thử 50") == true)
        #expect(passage.contents[2].secondary == nil, "verse 51 is shown on its own side only, nothing is made up")
        #expect(passage.contents[2].primary.contains("English verse 51"))
        #expect(passage.messages.contains { $0.contains("Exodus 12") && $0.contains("numbered differently") }, "\(passage.messages)")
        #expect(passage.messages.contains { $0.contains("no text") })
    }

    @Test func aVerseTheSecondTranslationLacksLeavesThatSideEmpty() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("vi-test")
        await r.scripture.show("John 3:16-18")
        let passage = try #require(r.scripture.passage)
        let last = try #require(passage.slides.last)
        #expect(last.verses.last?.verse == 18)
        let content = try #require(passage.contents.last)
        #expect(content.secondary == nil)
        #expect(!content.primary.isEmpty)
    }

    @Test func choosingTheSameTranslationTwiceIsRefusedPlainly() async throws {
        let r = try await L4C.rig()
        await r.scripture.setSecondary("en-test")
        #expect(r.scripture.secondaryCode == nil)
        #expect(r.scripture.choiceMessage?.contains("different") == true)
    }

    @Test func theChoicesSurviveARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let r = try await L4C.rig(store: store)
        await r.scripture.setPrimary("vi-test")
        await r.scripture.setSecondary("en-test")
        await r.scripture.setVersesPerSlide(2)
        let again = ScriptureModel(store: ScriptureStore(library: store), stateStore: store)
        await again.load()
        #expect(again.primaryCode == "vi-test" && again.secondaryCode == "en-test" && again.versesPerSlide == 2)
    }

    // MARK: nothing installed

    @Test func withNoTranslationInstalledTheViewSaysSoAndATypedReferenceIsRefusedPlainly() async throws {
        let r = try await L4C.rig(install: [])
        #expect(r.scripture.isEmpty)
        #expect(r.scripture.emptyMessage.contains("No Bible translation"))
        await r.scripture.show("John 3:16")
        #expect(r.scripture.problem?.contains("Import") == true)
        #expect(r.scripture.passage == nil && r.workspace.openScripture == nil)
    }
}
