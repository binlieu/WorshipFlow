// CUE-001 (AUTO-01): slide actions, their validation, and when they fire.
import Testing
import Foundation
import Domain
@testable import CueEngine

private func deck(_ id: UUID = UUID(), _ names: [String]) -> ShowDeck {
    ShowDeck(presentationID: id, slides: names.map { SlideContent(primary: $0) })
}

@Suite struct SlideActionValidationTests {
    let slide = UUID()

    @Test func storesAndReturnsActionsPerSlide() throws {
        var set = SlideActionSet()
        let look = CueAction.selectLook(UUID())
        try set.set([look, .playAudio(assetID: UUID())], for: slide, library: MacroLibrary())
        #expect(set.actions(for: slide).count == 2)
        #expect(set.actions(for: UUID()).isEmpty)
        #expect(set.slideIDs == [slide])
    }

    @Test func settingAnEmptyListRemovesTheEntry() throws {
        var set = SlideActionSet()
        try set.set([.selectLook(UUID())], for: slide, library: MacroLibrary())
        try set.set([], for: slide, library: MacroLibrary())
        #expect(set.slideIDs.isEmpty)
    }

    @Test(arguments: [
        CueAction.transport(.next), .transport(.previous), .transport(.goToSlide(index: 0)), .transport(.clear),
        .transport(.clearAll), .transport(.blackout(.toggle)), .transport(.stop),
    ]) func transportActionsAreRejectedWithAClearMessage(_ a: CueAction) {
        var set = SlideActionSet()
        do {
            try set.set([.selectLook(UUID()), a], for: slide, library: MacroLibrary())
            Issue.record("expected a rejection")
        } catch let e as SlideActionError {
            guard case .transportNotAllowed(let t) = e else { Issue.record("wrong case"); return }
            #expect(.transport(t) == a)
            #expect(e.message.contains(a.summary))
            #expect(e.message.localizedCaseInsensitiveContains("slide action"))
        } catch { Issue.record("wrong error") }
        #expect(set.slideIDs.isEmpty)          // nothing stored on failure
    }

    @Test func aMacroThatContainsTransportIsRejectedEvenWhenNested() throws {
        var lib = MacroLibrary()
        let inner = Macro(id: UUID(), name: "Skip ahead", steps: [.wait(seconds: 1), .transport(.next)])
        let outer = Macro(id: UUID(), name: "Wrapper", steps: [.runMacro(inner.id)])
        try lib.save(inner); try lib.save(outer)
        var set = SlideActionSet()
        do {
            try set.set([.runMacro(outer.id)], for: slide, library: lib)
            Issue.record("expected a rejection")
        } catch let e as SlideActionError {
            #expect(e == .macroContainsTransport(macroName: "Wrapper", transport: .next))
            #expect(e.message.contains("Wrapper"))
            #expect(e.message.contains("Next slide"))
        }
    }

    @Test func aMacroWithoutTransportAndAMissingMacroAreAccepted() throws {
        var lib = MacroLibrary()
        let ok = Macro(id: UUID(), name: "Warm up", steps: [.selectLook(UUID()), .wait(seconds: 1), .playAudio(assetID: UUID())])
        try lib.save(ok)
        var set = SlideActionSet()
        try set.set([.runMacro(ok.id), .runMacro(UUID())], for: slide, library: lib)
        #expect(set.actions(for: slide).count == 2)
    }

    @Test func revalidatingFindsMacrosEditedAfterTheSlideWasSaved() throws {
        var lib = MacroLibrary()
        let m = Macro(id: UUID(), name: "Later edited", steps: [])
        try lib.save(m)
        var set = SlideActionSet()
        try set.set([.runMacro(m.id)], for: slide, library: lib)
        try lib.save(Macro(id: m.id, name: "Later edited", steps: [.transport(.next)]))
        let problems = set.problems(library: lib)
        #expect(problems[slide] == [.macroContainsTransport(macroName: "Later edited", transport: .next)])
        #expect(SlideActionSet().problems(library: lib).isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        var set = SlideActionSet()
        try set.set([.selectLook(UUID()), .midiOut(.programChange(channel: 1, program: 4))], for: slide, library: MacroLibrary())
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(SlideActionSet.self, from: data) == set)
    }
}

@Suite struct SlideLiveDetectionTests {
    /// Applies `command` to `state` and returns what the detector says about the change.
    private func step(_ state: inout ShowState, _ command: ShowCommand) -> SlideLiveEvent? {
        let before = state
        state.apply(command)
        return SlideLiveEvent.detect(command: command, before: before, after: state)
    }

    let pid = UUID()

    @Test func triggeringASlideFiresIt() {
        var s = ShowState()
        #expect(step(&s, .load(deck(pid, ["A", "B", "C"]))) == nil)
        #expect(step(&s, .trigger(index: 1)) == SlideLiveEvent(presentationID: pid, index: 1))
    }

    @Test func previewActionsNeverFire() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        #expect(step(&s, .select(index: 1)) == nil)
        #expect(step(&s, .restore(deck: deck(pid, ["A", "B"]), selectedIndex: 1)) == nil)
    }

    @Test func nextAndPreviousFireTheSlideThatGoesLive() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B", "C"])))
        _ = step(&s, .trigger(index: 0))
        #expect(step(&s, .next) == SlideLiveEvent(presentationID: pid, index: 1))
        #expect(step(&s, .next) == SlideLiveEvent(presentationID: pid, index: 2))
        #expect(step(&s, .next) == nil)                                   // already on the last slide: nothing changed
        #expect(step(&s, .previous) == SlideLiveEvent(presentationID: pid, index: 1))
        #expect(step(&s, .previous) == SlideLiveEvent(presentationID: pid, index: 0))
        #expect(step(&s, .previous) == nil)
    }

    @Test func nextWhenNothingIsLiveTakesTheFirstSlideLive() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        #expect(step(&s, .next) == SlideLiveEvent(presentationID: pid, index: 0))
    }

    @Test func nextWithNothingLoadedFiresNothing() {
        var s = ShowState()
        #expect(step(&s, .next) == nil)
        _ = step(&s, .load(deck(pid, [])))
        #expect(step(&s, .next) == nil)
    }

    @Test func retriggeringTheSameSlideFiresAgain() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        #expect(step(&s, .trigger(index: 1)) != nil)
        #expect(step(&s, .trigger(index: 1)) == SlideLiveEvent(presentationID: pid, index: 1))
    }

    @Test func triggeringAnOutOfRangeSlideFiresNothing() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A"])))
        #expect(step(&s, .trigger(index: 5)) == nil)
        #expect(step(&s, .trigger(index: -1)) == nil)
    }

    @Test func clearClearAllAndStopNeverFire() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        _ = step(&s, .trigger(index: 0))
        #expect(step(&s, .clear) == nil)
        #expect(step(&s, .clearAll) == nil)
        #expect(step(&s, .stop) == nil)
    }

    @Test func liftingClearByTakingTheSameSlideAgainIsAnExplicitTriggerAndFires() {
        // Clear keeps the place. Only a trigger/next/previous lifts it, and each of those is a slide change command.
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        _ = step(&s, .trigger(index: 0))
        _ = step(&s, .clear)
        #expect(step(&s, .trigger(index: 0)) == SlideLiveEvent(presentationID: pid, index: 0))
        _ = step(&s, .clear)
        #expect(step(&s, .next) == SlideLiveEvent(presentationID: pid, index: 1))
    }

    @Test func aFailedNextWhileClearedDoesNotCountAsLiftingClear() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A"])))
        _ = step(&s, .trigger(index: 0))
        _ = step(&s, .clear)
        #expect(step(&s, .next) == nil)         // nothing after slide 0; state stays cleared
        #expect(s.isCleared)
    }

    @Test func quickEditOfTheLiveSlideDoesNotFire() {
        var s = ShowState()
        _ = step(&s, .load(deck(pid, ["A", "B"])))
        _ = step(&s, .trigger(index: 0))
        #expect(step(&s, .quickEdit(index: 0, content: SlideContent(primary: "A edited"))) == nil)
    }

    @Test func actionsAreLookedUpBySlideId() throws {
        let slideA = UUID(), slideB = UUID()
        var set = SlideActionSet()
        try set.set([.selectLook(UUID())], for: slideB, library: MacroLibrary())
        let ids = [slideA, slideB]
        let event = SlideLiveEvent(presentationID: pid, index: 1)
        #expect(set.actions(for: event, slideID: { ids[$0.index] }) == set.actions(for: slideB))
        #expect(set.actions(for: SlideLiveEvent(presentationID: pid, index: 0), slideID: { ids[$0.index] }).isEmpty)
        #expect(set.actions(for: event, slideID: { _ in nil }).isEmpty)
    }
}
