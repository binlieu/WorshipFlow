// UI-006g: the presentations that have slide actions.
import Testing
import Foundation
import Domain
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

@Suite struct UI006g_SlideActionPresentationsTests {
    private func makePresentation(_ f: Fixture, in library: Library, title: String, lines: [String]) async throws -> [Slide] {
        let p = try await f.library.createPresentation(in: library.id, title: title, kind: .song)
        for line in lines { _ = try await f.library.appendSlide(to: p.id, content: SlideContent(primary: line)) }
        return try await f.library.slides(of: p.id)
    }

    @Test func noneWhenNoSlideHasActions() async throws {
        let f = try Fixture()
        _ = try await f.slides(["one"])
        #expect(try await f.store.presentationsWithSlideActions().isEmpty)
    }

    @Test func eachPresentationListsHowManyOfItsSlidesHaveActionsByTitle() async throws {
        let f = try Fixture()
        let lib = try await f.library.createLibrary(name: "L")
        let zion = try await makePresentation(f, in: lib, title: "Zion", lines: ["a", "b", "c"])
        let amazing = try await makePresentation(f, in: lib, title: "amazing grace", lines: ["x", "y"])
        _ = try await makePresentation(f, in: lib, title: "Bare", lines: ["q"])
        let look = UUID()
        try await f.store.setSlideActions([.selectLook(look)], for: zion[0].id)
        try await f.store.setSlideActions([.selectLook(look)], for: zion[2].id)
        try await f.store.setSlideActions([.stopForeground], for: amazing[1].id)

        let rows = try await f.store.presentationsWithSlideActions()
        #expect(rows.map(\.title) == ["amazing grace", "Zion"])      // by title, ignoring case
        #expect(rows.map(\.slideCount) == [1, 2])
    }

    @Test func clearingTheLastActionOfAPresentationDropsItsRow() async throws {
        let f = try Fixture()
        let lib = try await f.library.createLibrary(name: "L")
        let slides = try await makePresentation(f, in: lib, title: "Song", lines: ["a"])
        try await f.store.setSlideActions([.stopForeground], for: slides[0].id)
        #expect(try await f.store.presentationsWithSlideActions().count == 1)
        try await f.store.setSlideActions([], for: slides[0].id)
        #expect(try await f.store.presentationsWithSlideActions().isEmpty)
    }

    @Test func deletingAPresentationDropsItsRow() async throws {
        let f = try Fixture()
        let lib = try await f.library.createLibrary(name: "L")
        let slides = try await makePresentation(f, in: lib, title: "Song", lines: ["a"])
        try await f.store.setSlideActions([.stopForeground], for: slides[0].id)
        try await f.library.deletePresentation(id: slides[0].presentationID)
        #expect(try await f.store.presentationsWithSlideActions().isEmpty)
    }
}
