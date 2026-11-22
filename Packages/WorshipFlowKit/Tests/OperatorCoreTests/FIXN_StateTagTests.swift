// FIX-N item 3: the red LIVE chip stays gone from the toolbar (owner: too busy), but an operator who presses B in Edit, Stage or Screens gets no
// feedback. A small, quiet, non-red tag is present only while the show is blacked out or cleared, and absent otherwise.
import Foundation
import Testing
import Domain
@testable import OperatorCore

@Suite struct FIXN_StateTagTests {
    private func live() -> ShowState {
        var show = ShowState()
        let deck = ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One"), SlideContent(primary: "Two")])
        show.apply(.load(deck))
        show.apply(.trigger(index: 0))
        return show
    }

    @Test func noTagWhileNothingIsLiveOrTheShowIsPlainlyLive() {
        #expect(ShowStateTag.text(for: ShowState()) == nil)
        #expect(ShowStateTag.text(for: live()) == nil)
    }

    @Test func blackoutShowsBlackoutAndLiftingItRemovesTheTag() {
        var show = live()
        show.apply(.blackout)
        #expect(ShowStateTag.text(for: show) == "BLACKOUT")
        show.apply(.blackout)
        #expect(ShowStateTag.text(for: show) == nil)
    }

    @Test func clearShowsClearedAndGoingLiveAgainRemovesIt() {
        var show = live()
        show.apply(.clear)
        #expect(ShowStateTag.text(for: show) == "CLEARED")
        show.apply(.trigger(index: 1))
        #expect(ShowStateTag.text(for: show) == nil)
        show.apply(.clearAll)
        #expect(ShowStateTag.text(for: show) == "CLEARED")
    }

    @Test func blackoutWinsOverClearedAndStopRemovesBoth() {
        var show = live()
        show.apply(.clear)
        show.apply(.blackout)
        #expect(ShowStateTag.text(for: show) == "BLACKOUT")
        show.apply(.stop)
        #expect(ShowStateTag.text(for: show) == nil)
    }

    @Test func clearBackgroundAloneAddsNoTag() {
        var show = live()
        show.apply(.clearBackground)
        #expect(ShowStateTag.text(for: show) == nil)
    }
}
