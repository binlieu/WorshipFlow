// FIX-J item 5 (UI-005h): the editor's own operations (drag, resize, typed numbers) carry the attached parts, and a saved layout keeps them.
import Testing
import Foundation
import Domain
@testable import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXJ_StageAttachedTests {
    func ready() async throws -> (StageModel, StageLayout) {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        let layout = try #require(model.createLayout(name: "Mine"))
        return (model, layout)
    }
    func element(_ model: StageModel, _ layout: StageLayout, _ kind: StageElement.Kind) throws -> StageElement {
        try #require(model.customLayouts.first { $0.id == layout.id }?.elements.first { $0.kind == kind })
    }

    @Test func aDragThroughTheModelMovesTheSecondLanguageLineWithTheElement() async throws {
        let (model, layout) = try await ready()
        let current = try element(model, layout, .currentSlide)
        let home = try #require(current.secondLanguageFrame)
        model.moveElement(current.id, in: layout.id, from: current.frame, dx: -0.02, dy: 0.05)
        let moved = try element(model, layout, .currentSlide)
        let after = try #require(moved.secondLanguageFrame)
        #expect(abs(after.x - home.x + 0.02) < 1e-9 && abs(after.y - home.y - 0.05) < 1e-9)
        // And the drag's start frame brings it back.
        model.moveElement(current.id, in: layout.id, from: current.frame, dx: 0, dy: 0)
        let back = try #require(try element(model, layout, .currentSlide).secondLanguageFrame)
        #expect(abs(back.x - home.x) < 1e-9 && abs(back.y - home.y) < 1e-9)
    }

    @Test func aResizeThroughTheModelScalesTheNEXTLabelWithTheNextElement() async throws {
        let (model, layout) = try await ready()
        let next = try element(model, layout, .nextSlide)
        let home = try #require(next.labelFrame)
        model.resizeElement(next.id, in: layout.id, from: next.frame, dWidth: -next.frame.width / 2, dHeight: 0)
        let resized = try element(model, layout, .nextSlide)
        let after = try #require(resized.labelFrame)
        #expect(abs(after.width - home.width / 2) < 1e-9)
        #expect(abs((after.x - resized.frame.x) - (home.x - next.frame.x) / 2) < 1e-9)
    }

    @Test func typedNumbersMoveThePartsToo() async throws {
        let (model, layout) = try await ready()
        let current = try element(model, layout, .currentSlide)
        let home = try #require(current.secondLanguageFrame)
        model.setFrame(current.id, in: layout.id, x: current.frame.x, y: current.frame.y + 0.1, width: current.frame.width, height: current.frame.height)
        let after = try #require(try element(model, layout, .currentSlide).secondLanguageFrame)
        #expect(abs(after.y - home.y - 0.1) < 1e-9 && abs(after.x - home.x) < 1e-9)
    }

    @Test func aMovedLayoutKeepsItsPartsAfterASaveAndReload() async throws {
        let store = try LibraryStore.inMemory()
        let model = StageModel(store: store)
        await model.load()
        let layout = try #require(model.createLayout(name: "Mine"))
        let current = try element(model, layout, .currentSlide)
        model.moveElement(current.id, in: layout.id, from: current.frame, dx: -0.02, dy: 0.05)
        let expected = try #require(try element(model, layout, .currentSlide).secondLanguageFrame)
        await model.flush()
        let again = StageModel(store: store)
        await again.load()
        let stored = try #require(again.customLayouts.first { $0.id == layout.id }?.elements.first { $0.kind == .currentSlide }?.secondLanguageFrame)
        #expect(abs(stored.x - expected.x) < 1e-9 && abs(stored.y - expected.y) < 1e-9 && abs(stored.width - expected.width) < 1e-9)
    }
}
