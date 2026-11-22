// FIX-I item 7, owner: "let the warning 'Broadcast is not sending. The operator controls and the other screens are not affected.' fade
// out after 5 seconds". The message card fades 5 seconds after it appears; the fault does not become invisible (the pill and the monitor keep
// their state from the readouts, and a click on the pill shows the card again); a new or different fault is a new card; a card with the pointer
// over it or with keyboard focus inside does not fade until the pointer leaves. Time is a value passed in: no wall clock anywhere.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@Suite struct FIXI_FaultCardFadeTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    func card(_ id: UUID, _ detail: String = "Signal lost.", mirror: Int? = nil) -> OutputFaultCard {
        OutputFaultCard(screenID: id, name: "Broadcast", message: "Broadcast is not sending. The operator controls and the other screens are not affected.",
                        detail: detail, canRetry: true, slot: OutputSlot(screenID: id, mirror: mirror))
    }

    @Test func aNewCardIsShownAndFadesFiveSecondsLater() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        #expect(visibility.isVisible(screenID: id, now: at(0)))
        #expect(visibility.isVisible(screenID: id, now: at(4.9)))
        #expect(!visibility.isVisible(screenID: id, now: at(5)))
        #expect(visibility.nextChange(now: at(1)) == at(5))
    }

    @Test func refreshingWithTheSameFaultDoesNotRestartTheTimer() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        for second in stride(from: 0.5, through: 4.5, by: 0.5) { visibility.update(cards: [card(id)], now: at(second)) }
        #expect(!visibility.isVisible(screenID: id, now: at(5)))
        visibility.update(cards: [card(id)], now: at(60))
        #expect(!visibility.isVisible(screenID: id, now: at(60)), "an old fault does not come back by itself")
    }

    @Test func aCardWithThePointerOverItDoesNotFadeUntilThePointerLeaves() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        visibility.setPointerOver(true, screenID: id, now: at(3))
        #expect(visibility.isVisible(screenID: id, now: at(5)) && visibility.isVisible(screenID: id, now: at(30)))
        #expect(visibility.nextChange(now: at(30)) == nil, "nothing is pending while it is held")
        visibility.setPointerOver(false, screenID: id, now: at(30))
        #expect(!visibility.isVisible(screenID: id, now: at(30)), "its five seconds were long over: it fades as the pointer leaves")
    }

    @Test func leavingBeforeTheFiveSecondsAreUpLeavesTheRestOfThem() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        visibility.setPointerOver(true, screenID: id, now: at(1))
        visibility.setPointerOver(false, screenID: id, now: at(2))
        #expect(visibility.isVisible(screenID: id, now: at(4.9)) && !visibility.isVisible(screenID: id, now: at(5)))
    }

    @Test func keyboardFocusInsideHoldsTheCardLikeThePointer() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        visibility.setFocusInside(true, screenID: id, now: at(4))
        #expect(visibility.isVisible(screenID: id, now: at(20)))
        visibility.setPointerOver(true, screenID: id, now: at(21))
        visibility.setFocusInside(false, screenID: id, now: at(22))
        #expect(visibility.isVisible(screenID: id, now: at(23)), "the pointer still holds it")
        visibility.setPointerOver(false, screenID: id, now: at(24))
        #expect(!visibility.isVisible(screenID: id, now: at(24)))
    }

    @Test func clickingThePillShowsTheCardAgainForAnotherFiveSeconds() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        #expect(!visibility.isVisible(screenID: id, now: at(10)))
        visibility.showAgain(screenID: id, now: at(10))
        #expect(visibility.isVisible(screenID: id, now: at(14.9)) && !visibility.isVisible(screenID: id, now: at(15)))
    }

    @Test func aDifferentFaultOnTheSameScreenIsANewCard() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id, "Signal lost.")], now: at(0))
        visibility.update(cards: [card(id, "Mode not supported by the card.")], now: at(30))
        #expect(visibility.isVisible(screenID: id, now: at(30)) && !visibility.isVisible(screenID: id, now: at(35)))
    }

    @Test func aFaultOnAnotherScreenOrAMirrorGetsItsOwnCardAndItsOwnTimer() {
        let a = UUID(), b = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(a)], now: at(0))
        visibility.update(cards: [card(a), card(b)], now: at(3))
        #expect(!visibility.isVisible(screenID: a, now: at(5)) && visibility.isVisible(screenID: b, now: at(5)))
        #expect(!visibility.isVisible(screenID: b, now: at(8)))
        #expect(visibility.visibleCards(from: [card(a), card(b)], now: at(4)).map(\.screenID) == [a, b])
        #expect(visibility.visibleCards(from: [card(a), card(b)], now: at(6)).map(\.screenID) == [b])
    }

    @Test func aFaultThatClearsAndComesBackIsANewCard() {
        let id = UUID()
        var visibility = FaultCardVisibility()
        visibility.update(cards: [card(id)], now: at(0))
        visibility.update(cards: [], now: at(8))                       // the output came back
        visibility.update(cards: [card(id)], now: at(40))              // and failed again
        #expect(visibility.isVisible(screenID: id, now: at(40)) && !visibility.isVisible(screenID: id, now: at(45)))
    }

    @Test func theFaultItselfStaysInTheReadoutsWhileTheCardIsHidden() {
        // The pill and the monitor read the screen's state, not the card: hiding a card changes nothing about them.
        let id = UUID()
        var r = ScreenReadout(id: id, name: "Broadcast", role: .broadcast, destination: .window, isEnabled: true, state: .faulted("Signal lost."),
                              refreshRate: 0, presented: 0, dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
        r.mirrors = []
        var visibility = FaultCardVisibility()
        visibility.update(cards: OutputFaultCards.cards(from: [r]), now: at(0))
        #expect(visibility.visibleCards(from: OutputFaultCards.cards(from: [r]), now: at(60)).isEmpty)
        #expect(OutputFaultCards.cards(from: [r]).count == 1, "still faulted: the card can be shown again")
        if case .faulted = r.state {} else { Issue.record("the readout keeps its fault state") }
    }
}
