// FIX-AB items 1 to 3: which cell the Show grid reveals. The scroll itself is SwiftUI; this is the decision.
import Testing
@testable import OperatorCore

@Suite struct FIXAB_ShowGridFollowTests {
    typealias P = ShowGridFollow.Place

    @Test func aLiveMoveRevealsTheNewLiveCell() {
        #expect(ShowGridFollow.target(from: P(live: 3, selected: 0), to: P(live: 4, selected: 0), count: 10) == 4)
    }

    @Test func theLastSlideOfALongSongIsRevealed() {
        #expect(ShowGridFollow.target(from: P(live: 198, selected: 0), to: P(live: 199, selected: 0), count: 200) == 199)
    }

    @Test func aSelectionMoveRevealsTheSelectedCell() {
        #expect(ShowGridFollow.target(from: P(live: 2, selected: 5), to: P(live: 2, selected: 6), count: 10) == 6)
    }

    @Test func whenBothChangeInOneStepLiveWins() {
        #expect(ShowGridFollow.target(from: P(live: 2, selected: 3), to: P(live: 3, selected: 4), count: 10) == 3)
    }

    @Test func goingLiveForTheFirstTimeRevealsTheLiveCell() {
        #expect(ShowGridFollow.target(from: P(live: nil, selected: 1), to: P(live: 1, selected: 2), count: 10) == 1)
    }

    @Test func nothingChangedRevealsNothing() {
        #expect(ShowGridFollow.target(from: P(live: 2, selected: 3), to: P(live: 2, selected: 3), count: 10) == nil)
    }

    @Test func theLivePlaceLeavingTheOpenPresentationScrollsNothingByItself() {
        // Live moved to another presentation (the grid sees nil): only a selection change may scroll.
        #expect(ShowGridFollow.target(from: P(live: 7, selected: 3), to: P(live: nil, selected: 3), count: 10) == nil)
        #expect(ShowGridFollow.target(from: P(live: 7, selected: 3), to: P(live: nil, selected: 4), count: 10) == 4)
    }

    @Test func aTargetOutsideTheSlidesIsNeverReturned() {
        #expect(ShowGridFollow.target(from: P(live: 1, selected: 0), to: P(live: 10, selected: 0), count: 10) == nil)
        #expect(ShowGridFollow.target(from: P(live: nil, selected: 0), to: P(live: nil, selected: 5), count: 0) == nil)
        #expect(ShowGridFollow.target(from: P(live: nil, selected: 0), to: P(live: nil, selected: -1), count: 10) == nil)
    }

    @Test func aLiveIndexOutOfRangeFallsBackToTheSelection() {
        #expect(ShowGridFollow.target(from: P(live: 1, selected: 0), to: P(live: 12, selected: 2), count: 10) == 2)
    }
}
