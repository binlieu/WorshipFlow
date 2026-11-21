// CUE-002b item 2 (KI-075): before a re-flow is saved the operator is told which slide actions will be dropped.
import Testing
import Foundation
import Domain
import CueEngine
import CueStore
import Persistence

@Suite struct CUE002b_SlideActionLossTests {
    func reflowed(_ text: String) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: 1) }

    func seeded() async throws -> (Fixture, Presentation, [Slide]) {
        let f = try Fixture()
        let lib = try await f.library.createLibrary(name: "L")
        let p = try await f.library.createPresentation(in: lib.id, title: "Song", kind: .song)
        try await f.library.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc"))
        let slides = try await f.library.slides(of: p.id)
        return (f, p, slides)
    }

    @Test func slidesWhoseWordsChangedAreListedWithTheirActionCounts() async throws {
        let (f, p, slides) = try await seeded()
        try await f.store.setSlideActions([.stopForeground], for: slides[0].id)
        try await f.store.setSlideActions([.stopForeground, .hideMessage(id: UUID())], for: slides[2].id)
        let losses = try await f.library.slideActionLosses(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc edited"))
        #expect(losses.count == 1)
        #expect(losses.first?.actionCount == 2)
        #expect(losses.first?.sectionName == "Chorus")
        #expect(losses.first?.primary == "c")
    }

    @Test func nothingIsListedWhenEveryActionKeepsItsSlide() async throws {
        let (f, p, slides) = try await seeded()
        try await f.store.setSlideActions([.stopForeground], for: slides[0].id)
        #expect(try await f.library.slideActionLosses(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc")).isEmpty)
        #expect(try await f.library.slideActionLosses(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc\n\nBridge\nd")).isEmpty)
    }

    @Test func aSlideWithoutActionsIsNeverListedAndTheReadChangesNothing() async throws {
        let (f, p, slides) = try await seeded()
        try await f.store.setSlideActions([.stopForeground], for: slides[0].id)
        _ = try await f.library.slideActionLosses(of: p.id, with: reflowed("Totally\nnew"))
        #expect(try await f.store.slideActions(for: slides[0].id) == [.stopForeground])
        let none = try await f.library.slideActionLosses(of: p.id, with: [])
        #expect(none.count == 1)                                  // everything would go
    }
}
