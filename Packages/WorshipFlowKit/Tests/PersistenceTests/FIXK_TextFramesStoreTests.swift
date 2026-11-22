// FIX-K item 3 (SLIDE): migration v14 adds one nullable column, `slide.textFrames`, for a slide's own text frames. Additive: a library written at v13 opens
// with every slide as it was and no frames. The frames are stored, reloaded, cleared, and carried by a re-flow by the same match as notes and backgrounds.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXK_TextFramesStoreTests {
    let own = SlideTextFrames(primary: NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.25),
                              secondary: NormalizedRect(x: 0.2, y: 0.6, width: 0.6, height: 0.2))

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixk-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("Library.sqlite")
    }

    private func setUp() async throws -> (LibraryStore, Presentation) {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        return (store, try await store.createPresentation(in: lib.id, title: "Song", kind: .song))
    }

    @Test func v14AddsTheColumnAndKeepsEveryOlderSlideAsItWas() async throws {
        let file = url()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let old = try LibraryStore.open(at: file, migratingUpTo: "v13")
        #expect(try await old.appliedMigrations().count == 13)
        #expect(!(try await old.columnNames(of: "slide").contains("textFrames")))
        let lib = try await old.createLibrary(name: "Songs")
        let p = try await old.createPresentation(in: lib.id, title: "Song", kind: .song)
        let shape = SlideObject(frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
        let a = try await old.appendSlide(to: p.id, content: SlideContent(primary: "one", secondary: "một", objects: [shape]))
        let b = try await old.appendSlide(to: p.id, content: SlideContent(primary: "two"))
        let before = try await old.slides(of: p.id)
        try old.close()

        let new = try LibraryStore.open(at: file)
        let applied = try await new.appliedMigrations()
        #expect(Array(applied.prefix(13)) == (1...13).map { "v\($0)" } && applied.last == "v14")
        #expect(try await new.columnNames(of: "slide").contains("textFrames"))
        let after = try await new.slides(of: p.id)
        #expect(after == before && after.map(\.id) == [a.id, b.id])
        #expect(after.allSatisfy { $0.content.textFrames == nil })
        // Opening again changes nothing.
        try new.close()
        let again = try LibraryStore.open(at: file)
        #expect(try await again.appliedMigrations().filter { $0 == "v14" }.count == 1)
        #expect(try await again.slides(of: p.id) == before)
    }

    @Test func aSlideWithoutFramesWritesNothingToTheColumn() async throws {
        let (store, p) = try await setUp()
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "plain"))
        let stored = try await store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM slide WHERE textFrames IS NOT NULL") }
        #expect(stored == 0)
    }

    @Test func framesAreStoredReloadedUpdatedAndCleared() async throws {
        let (store, p) = try await setUp()
        var content = SlideContent(primary: "one", secondary: "một")
        content.textFrames = own
        var slide = try await store.appendSlide(to: p.id, content: content)
        #expect(slide.content.textFrames == own)
        #expect(try await store.slides(of: p.id).first?.content.textFrames == own)

        slide.content.textFrames = SlideTextFrames(primary: NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), secondary: nil)
        try await store.updateSlide(slide)
        #expect(try await store.slides(of: p.id).first?.content.textFrames == slide.content.textFrames)

        slide.content.textFrames = nil
        try await store.updateSlide(slide)
        #expect(try await store.slides(of: p.id).first?.content.textFrames == nil)
        let stored = try await store.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM slide WHERE textFrames IS NOT NULL") }
        #expect(stored == 0)       // cleared means NULL, not an empty object
    }

    @Test func aDamagedValueReadsAsNoFramesAndDoesNotStopTheListLoading() async throws {
        let (store, p) = try await setUp()
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one"))
        try await store.writer.write { try $0.execute(sql: "UPDATE slide SET textFrames = '{not json'") }
        #expect(try await store.slides(of: p.id).map(\.content.primary) == ["one"])
        #expect(try await store.slides(of: p.id).first?.content.textFrames == nil)
    }

    @Test func aReflowCarriesFramesToTheSlideThatTakesOverTheOldOneAndListsTheOnesItLoses() async throws {
        let (store, p) = try await setUp()
        func reflowed(_ text: String) -> [ReflowResult] { Reflow.contents(primary: text, secondary: nil, maxLines: 1) }
        try await store.replaceContent(of: p.id, with: reflowed("Verse 1\na\nb\n\nChorus\nc"))
        for words in ["b", "c"] {
            var slide = try #require(try await store.slides(of: p.id).first { $0.content.primary == words })
            slide.content.textFrames = own
            try await store.updateSlide(slide)
        }
        let next = reflowed("Verse 1\nA new first line\nb\n\nChorus\nx")         // b stays, c is gone
        let losses = try await store.reflowLosses(of: p.id, with: next)
        #expect(losses.map(\.primary) == ["c"] && losses.first?.hasTextFrames == true)
        try await store.replaceContent(of: p.id, with: next)
        let slides = try await store.slides(of: p.id)
        #expect(slides.map(\.content.primary) == ["A new first line", "b", "x"])
        #expect(slides.map(\.content.textFrames) == [nil, own, nil])
    }
}
