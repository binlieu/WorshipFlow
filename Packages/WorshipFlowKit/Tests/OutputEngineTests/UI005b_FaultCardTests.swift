// UI-005b item 7: the error card's actions. "Retry output" re-opens the failed output through the coordinator's own restart, once, and
// says plainly if it failed again; "Details" shows the recorded fault text. Only an enabled output that is faulted gets a card.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@Suite struct UI005b_FaultCardTests {
    func readout(_ name: String, _ state: ScreenState, enabled: Bool = true, id: UUID = UUID(), mirrors: [MirrorReadout] = []) -> ScreenReadout {
        var r = ScreenReadout(id: id, name: name, role: .audience, destination: .window, isEnabled: enabled, state: state, refreshRate: 60,
                              presented: 0, dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
        r.mirrors = mirrors
        return r
    }

    @Test func onlyAnEnabledFaultedOutputGetsACardWithItsRecordedText() {
        let a = UUID(), b = UUID()
        let cards = OutputFaultCards.cards(from: [
            readout("Sanctuary", .running), readout("Stage", .faulted("Signal lost: the cable was unplugged."), id: a),
            readout("Hall", .faulted("old fault"), enabled: false), readout("Lobby", .hidden), readout("Broadcast", .stopped),
            readout("Feed", .faulted("Mode not supported by the card."), id: b)])
        #expect(cards.map(\.screenID) == [a, b])
        #expect(cards.map(\.detail) == ["Signal lost: the cable was unplugged.", "Mode not supported by the card."])
        #expect(cards[0].message.hasPrefix("Stage is not sending.") && cards[0].message.contains("other screens"))
        #expect(cards.map(\.canRetry) == [true, true])
    }

    @Test func aFaultedMirrorGetsACardForItsScreenWithTheMirrorsName() {
        let id = UUID()
        let mirror = MirrorReadout(id: "m1", index: 0, destination: .window, state: .faulted("Display gone."), refreshRate: 0, presented: 0, dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
        let cards = OutputFaultCards.cards(from: [readout("Sanctuary", .running, id: id, mirrors: [mirror])])
        #expect(cards.count == 1 && cards[0].screenID == id && cards[0].detail == "Display gone." && cards[0].message.contains("Sanctuary"))
    }

    @Test func retryReopensTheOutputOnceAndReportsSuccess() {
        let id = UUID()
        var reopened: [UUID] = []
        var state: ScreenState = .faulted("down")
        let outcome = OutputFaultCards.retry(id, name: "Stage", reopen: { reopened.append($0); state = .running }, state: { _ in state })
        #expect(reopened == [id])                                                   // exactly one reopen, of that output
        #expect(outcome == .reopened)
    }

    @Test func retryThatFailsAgainSaysSoPlainlyWithTheNewText() {
        let id = UUID()
        var calls = 0
        let outcome = OutputFaultCards.retry(id, name: "Stage", reopen: { _ in calls += 1 }, state: { _ in .faulted("The card refused the mode.") })
        #expect(calls == 1)
        guard case .stillFailing(let message) = outcome else { Issue.record("expected a failure"); return }
        #expect(message.contains("Stage") && message.contains("did not reopen") && message.contains("The card refused the mode."))
    }

    @Test func retryOfAnOutputThatIsGoneIsReportedNotIgnored() {
        let outcome = OutputFaultCards.retry(UUID(), name: "Hall", reopen: { _ in }, state: { _ in nil })
        guard case .stillFailing(let message) = outcome else { Issue.record("expected a failure"); return }
        #expect(message.contains("Hall") && message.contains("no longer"))
    }
}
