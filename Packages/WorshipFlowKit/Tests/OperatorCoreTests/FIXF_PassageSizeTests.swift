// FIX-F item 6 (LIB-004c): a reference that would make more than 300 slides is not built; the operator is told how many it would be
// and asked to narrow it. Written before the fix; invented text only.
import Testing
import Foundation
import Domain
import Persistence
import ScriptureEngine
import ScriptureStore
@testable import OperatorCore

@MainActor
@Suite struct FIXF_PassageSizeTests {
    /// Psalms 78, 89, 105 and 119 with one short invented line per verse, so one verse is one slide.
    private func big() -> TranslationFile {
        var file = TranslationFile(metadata: TranslationMetadata(
            id: "big-test", name: "Big test text", language: "en", abbreviation: "BIG", copyright: "Invented for tests.",
            license: "none", isPublicDomain: true, versification: "KJV"), books: [:])
        for chapter in [78, 89, 105, 119] {
            for n in 1...(Versification.kjv.verseCount(book: BookID("PSA"), chapter: chapter) ?? 0) {
                file.setVerse("Line \(chapter).\(n).", book: BookID("PSA"), chapter: chapter, verse: n)
            }
        }
        return file
    }

    private func rig() async throws -> L4C.Rig { try await L4C.rig(install: [big()]) }

    @Test func aReferenceThatWouldMakeMoreThanThreeHundredSlidesIsNotBuilt() async throws {
        let r = try await rig()
        await r.scripture.show("Psalm 119; Psalm 78; Psalm 89; Psalm 105")      // 176 + 72 + 52 + 45 = 345 verses, one slide each
        #expect(r.scripture.passage == nil, "nothing is built")
        let problem = try #require(r.scripture.problem)
        #expect(problem.contains("345"), Comment(rawValue: problem))
        #expect(problem.contains("300") && problem.localizedCaseInsensitiveContains("narrow"), Comment(rawValue: problem))
        #expect(r.workspace.openScripture == nil)
        #expect(r.workspace.show.previewDeck?.slides.isEmpty ?? true)
    }

    @Test func exactlyThreeHundredSlidesIsAllowed() async throws {
        let r = try await rig()
        await r.scripture.show("Psalm 119; Psalm 78; Psalm 89")                 // 176 + 72 + 52 = 300
        #expect(r.scripture.problem == nil)
        #expect(r.scripture.passage?.contents.count == 300)
    }

    @Test func narrowingTheReferenceWorksAfterTheRefusal() async throws {
        let r = try await rig()
        await r.scripture.show("Psalm 119; Psalm 78; Psalm 89; Psalm 105")
        #expect(r.scripture.passage == nil)
        await r.scripture.show("Psalm 105")
        #expect(r.scripture.passage?.contents.count == 45 && r.scripture.problem == nil)
    }

    @Test func aChangeOfVersesPerSlideThatGoesOverTheLimitIsRefusedToo() async throws {
        let r = try await rig()
        await r.scripture.setVersesPerSlide(2)
        await r.scripture.show("Psalm 119; Psalm 78; Psalm 89; Psalm 105")      // 345 verses, two to a slide: fits
        let shown = try #require(r.scripture.passage)
        #expect(shown.contents.count < 300)
        await r.scripture.setVersesPerSlide(1)                                  // one to a slide: 345 slides
        #expect(r.scripture.passage == nil)
        #expect(r.scripture.problem?.contains("345") == true)
    }
}
