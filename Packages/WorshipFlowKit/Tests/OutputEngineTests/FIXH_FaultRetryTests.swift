// FIX-H item 4 (UI-005b): Retry output on a faulted mirror restarts only that mirror, never the healthy primary or the other
// mirrors; a card carries the slot to restart; the "did not reopen" note goes when its card goes. Uses a fake coordinator that records
// the slots it was asked to restart, and the real coordinator with fake targets.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@MainActor
final class RecordingRestarter: OutputRestarting {
    var restarted: [OutputSlot] = []
    var shown: [ScreenReadout]
    /// What the readouts say after a restart of a slot (nil: it comes back healthy).
    var failAfterRestart: [OutputSlot: String] = [:]
    init(_ readouts: [ScreenReadout]) { shown = readouts }
    func restart(slot: OutputSlot) {
        restarted.append(slot)
        guard let i = shown.firstIndex(where: { $0.id == slot.screenID }) else { return }
        if let mirror = slot.mirror {
            shown[i].mirrors[mirror].state = failAfterRestart[slot].map { .faulted($0) } ?? .running
        } else {
            shown[i].state = failAfterRestart[slot].map { .faulted($0) } ?? .running
        }
    }
    func readouts() -> [ScreenReadout] { shown }
}

@MainActor
@Suite struct FIXH_FaultRetryTests {
    func readout(_ name: String, _ state: ScreenState, id: UUID = UUID(), mirrors: [MirrorReadout] = []) -> ScreenReadout {
        var r = ScreenReadout(id: id, name: name, role: .audience, destination: .window, isEnabled: true, state: state, refreshRate: 60,
                              presented: 0, dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
        r.mirrors = mirrors
        return r
    }
    func mirror(_ index: Int, _ state: ScreenState) -> MirrorReadout {
        MirrorReadout(id: "m\(index)", index: index, destination: .window, state: state, refreshRate: 0, presented: 0, dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
    }

    @Test func theCardForAFaultedMirrorNamesTheMirrorSlotAndAPrimaryFaultNamesThePrimary() {
        let id = UUID(), other = UUID()
        let cards = OutputFaultCards.cards(from: [
            readout("Sanctuary", .running, id: id, mirrors: [mirror(0, .running), mirror(1, .faulted("Display gone."))]),
            readout("Stage", .faulted("Cable out."), id: other, mirrors: [mirror(0, .faulted("Also gone."))])])
        #expect(cards.map(\.slot) == [OutputSlot(screenID: id, mirror: 1), OutputSlot(screenID: other)])
    }

    @Test func retryRestartsOnlyTheFaultedMirrorSlot() {
        let id = UUID()
        let screens = [readout("Sanctuary", .running, id: id, mirrors: [mirror(0, .running), mirror(1, .faulted("Display gone."))])]
        let coordinator = RecordingRestarter(screens)
        let card = OutputFaultCards.cards(from: screens)[0]
        #expect(OutputFaultCards.retry(card, on: coordinator) == .reopened)
        #expect(coordinator.restarted == [OutputSlot(screenID: id, mirror: 1)])
    }

    @Test func aMirrorThatFailsAgainSaysSoWithItsNewText() {
        let id = UUID()
        let screens = [readout("Sanctuary", .running, id: id, mirrors: [mirror(0, .faulted("Display gone."))])]
        let coordinator = RecordingRestarter(screens)
        coordinator.failAfterRestart[OutputSlot(screenID: id, mirror: 0)] = "The card refused the mode."
        let card = OutputFaultCards.cards(from: screens)[0]
        guard case .stillFailing(let text) = OutputFaultCards.retry(card, on: coordinator) else { Issue.record("expected a failure"); return }
        #expect(text.contains("Sanctuary") && text.contains("did not reopen") && text.contains("The card refused the mode."))
        #expect(coordinator.restarted.count == 1)
    }

    @Test func aScreenThatIsGoneIsReportedNotRestarted() {
        let card = OutputFaultCard(screenID: UUID(), name: "Hall", message: "", detail: "", canRetry: true, slot: OutputSlot(screenID: UUID()))
        let coordinator = RecordingRestarter([])
        guard case .stillFailing(let text) = OutputFaultCards.retry(card, on: coordinator) else { Issue.record("expected a failure"); return }
        #expect(text.contains("Hall") && text.contains("no longer"))
    }

    @Test func aNoteIsKeptOnlyWhileItsCardIsStillThere() {
        let a = UUID(), b = UUID()
        let cards = OutputFaultCards.cards(from: [readout("Stage", .faulted("down"), id: a)])
        let kept = OutputFaultCards.notes([a: "Stage did not reopen.", b: "Hall did not reopen."], keepingCardsOf: cards)
        #expect(kept == [a: "Stage did not reopen."])
        #expect(OutputFaultCards.notes([a: "old"], keepingCardsOf: []).isEmpty)           // the output came back: its note goes
    }

    // The real coordinator, with fake targets.
    @Test func theRealCoordinatorRestartsOneMirrorAndLeavesThePrimaryRunning() throws {
        let profile = ScreenProfile(name: "Audience", role: .audience, destination: .display(2), mirrors: [.window])
        let h = Harness([profile])
        h.coordinator.start()
        #expect(h.made.count == 2)
        let primary = h.made[0], mirrorTarget = h.made[1]
        mirrorTarget.failByItself("The projector was switched off.")
        guard case .faulted = h.readout(profile.id)?.mirrors.first?.state else { Issue.record("mirror should be faulted"); return }
        let card = try #require(OutputFaultCards.cards(from: h.coordinator.readouts()).first)
        #expect(card.slot == OutputSlot(screenID: profile.id, mirror: 0))
        let outcome = OutputFaultCards.retry(card, on: h.coordinator)
        #expect(outcome == .reopened)
        #expect(h.made.count == 3)                                   // one new target, for the mirror
        #expect(primary.startCount == 1 && primary.stopCount == 0)   // the healthy primary was not touched
        #expect(h.readout(profile.id)?.state == .running)
    }
}
