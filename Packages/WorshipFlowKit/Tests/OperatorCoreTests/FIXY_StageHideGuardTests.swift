// FIX-Y item 12 (STAGE; REVIEW-4 L7): the eye refuses to hide the Current slide when that would leave the stage screen with nothing from the show on
// it (no Current slide, Next slide or Notes left visible), and says why. The smaller of the two ways out: a refusal, not a dialog. Everything else
// can still be hidden, and showing an element again is never refused.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXY_StageHideGuardTests {
    private func ready() async throws -> StageModel {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        return model
    }

    /// A layout that holds only the kinds given, made from a copy of the built-in one.
    private func layout(_ model: StageModel, keeping kinds: [StageElement.Kind]) throws -> StageLayout {
        let made = try #require(model.createLayout(name: "L\(UUID().uuidString.prefix(4))"))
        for e in made.elements where !kinds.contains(e.kind) { model.removeElement(e.id, from: made.id) }
        return try #require(model.layout(withID: made.id))
    }

    @Test func theOnlyCurrentSlideCannotBeHiddenAndTheReasonIsGiven() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.currentSlide])
        let id = try #require(l.elements.first { $0.kind == .currentSlide }?.id)
        model.setHidden(true, for: id, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == id }?.isHidden == false)
        let why = try #require(model.lastError)
        #expect(why.contains("Current slide") && why.contains("nothing from the show"))
    }

    @Test func aCurrentSlideBesideOnlyAClockCannotBeHiddenEither() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.currentSlide, .timeOfDay])
        let id = try #require(l.elements.first { $0.kind == .currentSlide }?.id)
        model.setHidden(true, for: id, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == id }?.isHidden == false && model.lastError != nil)
    }

    @Test func theCurrentSlideCanBeHiddenWhileNextOrNotesStillShowTheShow() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.currentSlide, .nextSlide])
        let id = try #require(l.elements.first { $0.kind == .currentSlide }?.id)
        model.setHidden(true, for: id, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == id }?.isHidden == true && model.lastError == nil)
    }

    @Test func oneOfTwoCurrentSlidesCanBeHiddenButNotTheSecond() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.currentSlide])
        let first = try #require(l.elements.first { $0.kind == .currentSlide }?.id)
        let second = try #require(model.addElement(.currentSlide, to: l.id))
        model.setHidden(true, for: first, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == first }?.isHidden == true && model.lastError == nil)
        model.setHidden(true, for: second, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == second }?.isHidden == false && model.lastError != nil)
    }

    @Test func showingAnElementAgainAndHidingOtherKindsAreNeverRefused() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.currentSlide, .timeOfDay])
        let clock = try #require(l.elements.first { $0.kind == .timeOfDay }?.id)
        model.setHidden(true, for: clock, in: l.id)                                  // a clock is not the show's words
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == clock }?.isHidden == true && model.lastError == nil)
        model.setHidden(false, for: clock, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == clock }?.isHidden == false && model.lastError == nil)
    }

    @Test func aLayoutWithNoCurrentSlideIsUnaffected() async throws {
        let model = try await ready()
        let l = try layout(model, keeping: [.timeOfDay])
        let notes = try #require(model.addElement(.notes, to: l.id))
        model.setHidden(true, for: notes, in: l.id)
        #expect(model.layout(withID: l.id)?.elements.first { $0.id == notes }?.isHidden == true && model.lastError == nil)
    }
}
