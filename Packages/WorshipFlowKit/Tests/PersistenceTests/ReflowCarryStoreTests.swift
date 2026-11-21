// SLIDE-001b: KI-019 and KI-020 in the store (written by the implementer; the coordinator's SongStructureStoreTests are unchanged).
import Testing
import Foundation
import Domain
@testable import Persistence

@Suite struct ReflowCarryStoreTests {
    func setUp() async throws -> (LibraryStore, Presentation) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        return (store, try await store.createPresentation(in: lib.id, title: "Song", kind: .song))
    }
    func reflowed(_ text: String, max: Int = 1) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: max) }
    func shape() -> SlideObject {
        SlideObject(frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
    }

    /// Writes notes and an object onto the stored slide with these words.
    func decorate(_ store: LibraryStore, _ p: Presentation, words: String, notes: String, objects: [SlideObject] = []) async throws {
        var slide = try #require(try await store.slides(of: p.id).first { $0.content.primary == words })
        slide.notes = notes
        slide.content.objects = objects
        try await store.updateSlide(slide)
    }

    @Test func unchangedSlidesKeepNotesAndObjectsAcrossAReflow() async throws {
        let (store, p) = try await setUp()
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc"))
        let o = shape()
        try await decorate(store, p, words: "b", notes: "play softly", objects: [o])
        try await decorate(store, p, words: "c", notes: "everyone")
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\nA new first line\nb\n\nChorus\nc\n\nBridge\nd"))
        let slides = try await store.slides(of: p.id)
        #expect(slides.map(\.content.primary) == ["A new first line", "b", "c", "d"])
        #expect(slides.map(\.notes) == ["", "play softly", "everyone", ""])
        #expect(slides[1].content.objects == [o] && slides[0].content.objects.isEmpty)
        let reloaded = try await store.slides(of: p.id)
        #expect(reloaded[1].content.objects == [o])
    }

    @Test func aSlideChangedOrMovedToAnotherSectionLosesItsNotesAndTheyAreListedFirst() async throws {
        let (store, p) = try await setUp()
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\n\nChorus\nb"))
        try await decorate(store, p, words: "a", notes: "note on a")
        try await decorate(store, p, words: "b", notes: "note on b", objects: [shape()])
        let next = reflowed("Verse 1\na edited\n\nChorus\nx\n\nBridge\nb")          // b is now in another section
        let losses = try await store.reflowLosses(of: p.id, with: next)
        #expect(losses == [ReflowLoss(sectionName: "Verse 1", primary: "a", notes: "note on a", objectCount: 0),
                           ReflowLoss(sectionName: "Chorus", primary: "b", notes: "note on b", objectCount: 1)])
        #expect(try await store.slides(of: p.id).map(\.notes) == ["note on a", "note on b"])   // listing changes nothing
        try await store.replaceContent(of: p.id, with: next)
        #expect(try await store.slides(of: p.id).map(\.notes) == ["", "", ""])
    }

    @Test func reflowingTheSameTextChangesNothingAndLosesNothing() async throws {
        let (store, p) = try await setUp()
        let text = "Verse 1\na\n\nChorus\nb"
        try await store.replaceContent(of: p.id, with: reflowed(text))
        try await decorate(store, p, words: "a", notes: "n", objects: [shape()])
        #expect(try await store.reflowLosses(of: p.id, with: reflowed(text)).isEmpty)
        try await store.replaceContent(of: p.id, with: reflowed(text))
        let slides = try await store.slides(of: p.id)
        #expect(slides.map(\.notes) == ["n", ""] && slides[0].content.objects.count == 1)
    }

    @Test func carriedObjectsAreSearchableAgain() async throws {
        let (store, p) = try await setUp()
        try await store.replaceContent(of: p.id, with: reflowed("a"))
        let text = SlideObject(frame: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.2),
                               content: .text(TextObject(text: "Zebra banner", style: TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white))))
        try await decorate(store, p, words: "a", notes: "", objects: [text])
        try await store.replaceContent(of: p.id, with: reflowed("a"))
        #expect(try await store.search("zebra", limit: 5).count == 1)
    }

    @Test func lossesForAMissingPresentationThrowNotFound() async throws {
        let (store, _) = try await setUp()
        await #expect(throws: StoreError.notFound) { _ = try await store.reflowLosses(of: UUID(), with: []) }
    }

    @Test func differentChorusesBecomeTwoGroupsAndKeepTheirIdentityOnTheNextReflow() async throws {
        let (store, p) = try await setUp()
        let text = "Chorus\nfirst\n\nVerse 1\nv\n\nChorus\nsecond\n\nChorus\nfirst"
        try await store.replaceContent(of: p.id, with: reflowed(text))
        let groups = try await store.groups(of: p.id)
        #expect(groups.map(\.name) == ["Chorus", "Verse 1", "Chorus 2"])
        let slides = try await store.slides(of: p.id)
        #expect(slides.map(\.groupID) == [groups[0].id, groups[1].id, groups[2].id, groups[0].id])
        let arr = try await store.createArrangement(for: p.id, name: "Odd", groupIDs: [groups[2].id, groups[0].id])
        try await store.replaceContent(of: p.id, with: reflowed(text + "\n\nBridge\nz"))
        let after = try await store.groups(of: p.id)
        #expect(after.prefix(3).map(\.id) == groups.map(\.id))
        #expect(try await store.arrangements(of: p.id).first?.groupIDs == arr.groupIDs)
        #expect(try await store.resolvedSlides(of: p.id, arrangementID: arr.id).map(\.content.primary) == ["second", "first", "first"])
    }
}
