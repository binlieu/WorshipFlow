// FIX-Q (OUT, UI Show): the slide grid must not run its own body when Next, Previous or a selection moves a mark. Each cell asks
// `isSelected(at:)` and `isLive(at:)` and is woken only when its own slide gains or loses the mark. Counted with `withObservationTracking`,
// the way FIX-O counts parts: one tracker per slide position, then the set of trackers that fired is compared with the set the command is
// supposed to reach. The values must equal what the whole state says, after every command of a recorded sequence.
import Testing
import Foundation
import Observation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXQ_MarksTests {
    enum Mark: Hashable { case selected(Int), live(Int) }

    func readers(_ show: ObservedShow, positions: Int = 8) -> [Mark: () -> Void] {
        var out: [Mark: () -> Void] = [:]
        for i in 0..<positions {
            out[.selected(i)] = { _ = show.isSelected(at: i) }
            out[.live(i)] = { _ = show.isLive(at: i) }
        }
        return out
    }

    func rig() -> ObservedShow {
        let show = ObservedShow()
        show.apply(.load(FIXO.deck(UUID(), 8)))
        show.apply(.trigger(index: 2))
        return show
    }

    func reached(_ show: ObservedShow, _ command: ShowCommand) -> Set<Mark> {
        FIXO.parts(readers(show)) { show.apply(command) }
    }

    @Test func nextWakesTheCellItLeavesAndTheCellItEntersAndNoOther() {
        let show = rig()
        #expect(reached(show, .next) == [.live(2), .live(3), .selected(2), .selected(3)])
        #expect(reached(show, .previous) == [.live(3), .live(2), .selected(3), .selected(2)])
    }

    @Test func aSelectionWakesTwoCellsAndNeverTheLiveMarks() {
        let show = rig()
        #expect(reached(show, .select(index: 6)) == [.selected(2), .selected(6)])
        #expect(reached(show, .select(index: 1)) == [.selected(6), .selected(1)])
    }

    @Test func goLiveElsewhereWakesTheOldAndNewCells() {
        let show = rig()
        #expect(reached(show, .trigger(index: 5)) == [.live(2), .live(5), .selected(2), .selected(5)])
    }

    @Test func stoppingWakesTheLiveCellOnly() {
        let show = rig()
        #expect(reached(show, .stop) == [.live(2)])
    }

    @Test func goingLiveFromStoppedWakesTheNewLiveCell() {
        let show = ObservedShow()
        show.apply(.load(FIXO.deck(UUID(), 8)))
        #expect(reached(show, .trigger(index: 4)) == [.selected(0), .selected(4), .live(4)])
    }

    @Test func blackoutClearAndABackgroundChoiceWakeNoCell() {
        let show = rig()
        for command in [ShowCommand.blackout, .clear, .clearBackground, .restoreBackground, .liftHolds] {
            #expect(reached(show, command).isEmpty, "\(command)")
        }
    }

    @Test func aRefreshOfThePreviewDeckAndAQuickEditWakeNoCell() {
        let show = rig()
        let id = show.current.previewDeck!.presentationID
        #expect(reached(show, .restore(deck: ShowDeck(presentationID: id, slides: FIXO.deck(id, 8, prefix: "Edited").slides), selectedIndex: 2)).isEmpty)
        #expect(reached(show, .quickEdit(index: 2, content: SlideContent(primary: "Live fix"))).isEmpty)
    }

    @Test func aMarkEqualsWhatTheWholeStateSaysAfterEveryCommandOfARecordedSequence() {
        var seed: UInt64 = 0xC0FFEE
        func next(_ bound: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(bound)) }
        let id = UUID()
        let show = ObservedShow()
        for step in 0..<400 {
            let command: ShowCommand
            switch next(9) {
            case 0: command = .load(FIXO.deck(id, 3 + next(6)))
            case 1: command = .select(index: next(9))
            case 2: command = .trigger(index: next(9))
            case 3, 4: command = .next
            case 5: command = .previous
            case 6: command = .blackout
            case 7: command = .clear
            default: command = next(4) == 0 ? .stop : .liftHolds
            }
            show.apply(command)
            for i in 0..<10 {
                #expect(show.isSelected(at: i) == (show.current.selectedIndex == i), "step \(step) selected \(i)")
                #expect(show.isLive(at: i) == (show.current.liveIndex == i), "step \(step) live \(i)")
            }
        }
    }

    @Test func aTrackerReadingOnePositionStaysQuietWhileOthersMove() {
        let show = rig()
        let flag = FIXO_Flag()
        withObservationTracking({ _ = show.isLive(at: 6) }, onChange: { flag.fired = true })
        for _ in 0..<3 { show.apply(.next) }                  // live 2 -> 5
        #expect(!flag.fired)
        show.apply(.next)                                     // live 5 -> 6: this position gains the mark
        #expect(flag.fired)
    }
}
