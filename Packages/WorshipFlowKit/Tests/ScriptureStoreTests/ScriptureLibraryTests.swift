// LIB-004b: the façade the app will use: typed reference in, slides out. Synthetic text and the KJV fixture only.
import Testing
import Foundation
import ScriptureEngine
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore
import Domain

private typealias F = StoreFixtures

@Suite struct ScriptureLibraryTests {
    private func library() async throws -> ScriptureLibrary {
        let store = ScriptureStore(library: try LibraryStore.inMemory())
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        _ = try await store.importTranslation(F.vietnameseFile(), replaceExisting: false)
        return ScriptureLibrary(store: store)
    }

    @Test func oneTranslationGivesOneSlidePerVerseWithTheReference() async throws {
        let lib = try await library()
        let look = try await lib.lookup("John 3:16-17", primary: "kjv")
        let p = try #require(look.presentation)
        #expect(look.outcome.isValid)
        #expect(p.slides.map(\.content.primary) == [F.kjvVerses[6].3, F.kjvVerses[7].3])
        #expect(p.slides.map(\.reference) == ["John 3:16", "John 3:17"])
        #expect(p.title == "John 3:16\u{2013}17 (KJV)")
        #expect(p.slides.allSatisfy { $0.content.secondary == nil })
        #expect(look.primary.code == "kjv" && look.secondary == nil && look.notes.isEmpty)
    }

    @Test func twoTranslationsArePairedByReferenceAndUnpairedVersesAreReported() async throws {
        let lib = try await library()
        // The synthetic Vietnamese text has John 3:16-17 but not 3:18.
        let look = try await lib.lookup("John 3:16-18", primary: "kjv", secondary: "vi-test")
        let p = try #require(look.presentation)
        #expect(p.slides.count == 3)
        #expect(p.slides[0].content.secondary == F.vietnamese[0].3)
        #expect(p.slides[2].content.secondary == nil)
        #expect(p.report.missingInSecondary == [F.ref("JHN", 3, 18)])
        #expect(p.report.messages.contains { $0.contains("John 3:18") })
        #expect(look.secondary?.code == "vi-test")
    }

    @Test func versesTheSecondTranslationHasButTheFirstLacksAreSkippedAndReported() async throws {
        let lib = try await library()
        let look = try await lib.lookup("Genesis 1:1-4", primary: "kjv", secondary: "vi-test")
        let p = try #require(look.presentation)
        #expect(p.slides.count == 3)                                   // KJV fixture has GEN 1:1-3, not 4
        #expect(p.report.missingInPrimary == [F.ref("GEN", 1, 4)])
        #expect(p.slides.allSatisfy { $0.content.secondary == nil })   // the Vietnamese has no Genesis at all
        #expect(p.report.missingInSecondary.count == 3)
    }

    @Test func aReferenceIsReadInTheLanguageContext() async throws {
        let lib = try await library()
        let vi = try await lib.lookup("Giăng 3:16", primary: "kjv", context: .vietnamese)
        #expect(vi.outcome.isValid)
        #expect(vi.presentation?.slides.first?.verses == [F.ref("JHN", 3, 16)])
        let viaUI = try await lib.lookup("Giăng 3:16", primary: "vi-test", uiLanguage: .vietnamese)
        #expect(viaUI.presentation?.slides.first?.reference == "Giăng 3:16")
        let en = try await lib.lookup("Jn 3:16", primary: "kjv", context: .english)
        #expect(en.outcome.ranges.count == 1)
    }

    @Test func aBadReferenceGivesProblemsAndNoSlides() async throws {
        let lib = try await library()
        let look = try await lib.lookup("Johnn 3:16", primary: "kjv")
        #expect(!look.outcome.isValid && !look.outcome.problems.isEmpty)
        #expect(look.presentation == nil)
        let mixed = try await lib.lookup("John 3:16; Nonsense 1:1", primary: "kjv")
        #expect(mixed.outcome.problems.count == 1)
        #expect(mixed.presentation?.slides.count == 1)                 // the good reference still gives its slide
        let empty = try await lib.lookup("   ", primary: "kjv")
        #expect(empty.presentation == nil)
    }

    @Test func aMissingTranslationIsAnError() async throws {
        let lib = try await library()
        await #expect(throws: ScriptureStoreError.notFound("nope")) { _ = try await lib.lookup("John 3:16", primary: "nope") }
        await #expect(throws: ScriptureStoreError.notFound("nope")) { _ = try await lib.lookup("John 3:16", primary: "kjv", secondary: "nope") }
    }

    @Test func differentNumberingBetweenTheTwoTranslationsIsSaid() async throws {
        let store = ScriptureStore(library: try LibraryStore.inMemory())
        _ = try await store.importTranslation(F.kjvFile(), replaceExisting: false)
        var vi = TranslationFile(metadata: TranslationMetadata(id: "vi25", name: "VI", language: "vi", abbreviation: "VI25", versification: "VI1925"), books: [:])
        vi.setVerse("synthetic one", book: BookID("3JN"), chapter: 1, verse: 15)
        vi.setVerse("synthetic two", book: BookID("JHN"), chapter: 3, verse: 16)
        _ = try await store.importTranslation(vi, replaceExisting: false)
        let lib = ScriptureLibrary(store: store)
        let same = try await lib.lookup("John 3:16", primary: "kjv", secondary: "vi25")
        #expect(same.notes.isEmpty)                                    // John 3 is numbered alike in both tables
        let differs = try await lib.lookup("3 John 1:14", primary: "kjv", secondary: "vi25")
        #expect(differs.notes.count == 1)
        #expect(differs.notes[0].contains("3 John 1") && differs.notes[0].contains("KJV") && differs.notes[0].contains("VI1925"))
    }

    @Test func slideOptionsPassThrough() async throws {
        let lib = try await library()
        let look = try await lib.lookup("John 3:16-17", primary: "kjv", options: SlideOptions(versesPerSlide: 2, verseNumbers: .plain))
        let p = try #require(look.presentation)
        #expect(p.slides.count == 1)
        #expect(p.slides[0].content.primary.hasPrefix("16 For God"))
        #expect(p.slides[0].reference == "John 3:16\u{2013}17")
    }

    @Test func onlyTheNeededVersesAreReadFromTheLibrary() async throws {
        // Full-size synthetic translation: a one-verse lookup must not load 31,102 verses. Checked by time and by shape.
        let store = ScriptureStore(library: try LibraryStore.inMemory())
        _ = try await store.importTranslation(F.syntheticFull(), replaceExisting: false)
        let lib = ScriptureLibrary(store: store)
        let clock = ContinuousClock()
        var look: ScriptureLookup?
        let elapsed = try await clock.measure { look = try await lib.lookup("Psalm 119:1-176", primary: "syn") }
        #expect(look?.presentation?.slides.count == 176)
        print("LIB-004b lookup of Psalm 119 (176 verses) through ScriptureLibrary: \(elapsed)")
        #expect(elapsed < .seconds(2))
    }
}
