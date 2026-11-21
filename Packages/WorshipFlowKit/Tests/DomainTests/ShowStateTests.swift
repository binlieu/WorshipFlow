// OUT-002 acceptance tests: Preview, Live, Clear and Stop semantics (CLAUDE.md working rules; LIVE-07).
// Owned by the coordinator: do not modify.
import Testing
import Foundation
@testable import Domain

@Suite struct ShowStateTests {
    let songA = ShowDeck(presentationID: UUID(), slides: ["A1", "A2", "A3"].map { SlideContent(primary: $0) })
    let songB = ShowDeck(presentationID: UUID(), slides: ["B1", "B2"].map { SlideContent(primary: $0) })

    @Test func startsWithNothingLive() {
        let s = ShowState()
        #expect(s.liveSlide == nil && s.nextSlide == nil && s.liveIndex == nil)
        #expect(s.isCleared == false && s.isStopped == true)
    }

    @Test func loadingADeckOnlyChangesPreview() {
        var s = ShowState()
        s.apply(.load(songA))
        #expect(s.previewDeck == songA)
        #expect(s.liveDeck == nil && s.liveSlide == nil)
    }

    @Test func triggerMakesPreviewLive() {
        var s = ShowState()
        s.apply(.load(songA))
        s.apply(.trigger(index: 1))
        #expect(s.liveDeck == songA && s.liveIndex == 1)
        #expect(s.liveSlide?.primary == "A2" && s.nextSlide?.primary == "A3")
        #expect(s.isStopped == false && s.isCleared == false)
    }

    @Test func triggerOutOfRangeIsIgnored() {
        var s = ShowState()
        s.apply(.load(songA))
        s.apply(.trigger(index: 0))
        let before = s
        s.apply(.trigger(index: 7))
        s.apply(.trigger(index: -1))
        #expect(s == before)
    }

    @Test func nextAndPreviousStopAtTheEnds() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 0))
        s.apply(.previous)
        #expect(s.liveIndex == 0)
        s.apply(.next); s.apply(.next); s.apply(.next); s.apply(.next)
        #expect(s.liveIndex == 2 && s.liveSlide?.primary == "A3" && s.nextSlide == nil)
    }

    /// With a deck loaded but nothing live, Next starts at the first slide.
    @Test func nextFromIdleStartsTheLoadedDeck() {
        var s = ShowState()
        s.apply(.load(songA))
        s.apply(.next)
        #expect(s.liveIndex == 0 && s.liveSlide?.primary == "A1")
    }

    @Test func nextWithNothingLoadedDoesNothing() {
        var s = ShowState()
        s.apply(.next); s.apply(.previous); s.apply(.clear)
        #expect(s == ShowState())
    }

    /// LIVE-07: loading or editing another deck never alters what is live.
    @Test func loadingAnotherDeckLeavesLiveAlone() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 1))
        s.apply(.load(songB))
        #expect(s.previewDeck == songB)
        #expect(s.liveDeck == songA && s.liveSlide?.primary == "A2")
        s.apply(.next)                                   // Next follows the live deck, not the preview
        #expect(s.liveDeck == songA && s.liveSlide?.primary == "A3")
        s.apply(.trigger(index: 0))                      // an explicit trigger takes the preview live
        #expect(s.liveDeck == songB && s.liveSlide?.primary == "B1")
    }

    /// LIVE-07: an edited copy of the live presentation in preview does not change live text.
    @Test func editedPreviewOfTheLiveDeckDoesNotLeak() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 0))
        var edited = songA
        edited.slides[0] = SlideContent(primary: "A1 edited")
        s.apply(.load(edited))
        #expect(s.liveSlide?.primary == "A1")
    }

    /// PRES-07: a quick edit is the one deliberate way to change live text.
    @Test func quickEditChangesTheLiveSlide() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 0))
        s.apply(.quickEdit(index: 0, content: SlideContent(primary: "A1 fixed")))
        #expect(s.liveSlide?.primary == "A1 fixed")
        s.apply(.quickEdit(index: 9, content: SlideContent(primary: "nope")))
        #expect(s.liveDeck?.slides.count == 3)
    }

    @Test func clearHidesTheSlideButKeepsThePlace() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 1))
        s.apply(.clear)
        #expect(s.isCleared && s.liveSlide == nil && s.liveIndex == 1 && s.isStopped == false)
        #expect(s.nextSlide?.primary == "A3")
        s.apply(.next)
        #expect(s.isCleared == false && s.liveSlide?.primary == "A3")
    }

    @Test func triggerAfterClearShowsAgain() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 1)); s.apply(.clear)
        s.apply(.trigger(index: 1))
        #expect(s.isCleared == false && s.liveSlide?.primary == "A2")
    }

    @Test func stopDropsLiveButKeepsPreview() {
        var s = ShowState()
        s.apply(.load(songA)); s.apply(.trigger(index: 2))
        s.apply(.stop)
        #expect(s.isStopped && s.liveDeck == nil && s.liveSlide == nil && s.liveIndex == nil)
        #expect(s.previewDeck == songA)
    }

    /// NFR-06: after a relaunch the place is restored to preview, never to live.
    @Test func restoreNeverGoesLive() {
        var s = ShowState()
        s.apply(.restore(deck: songA, selectedIndex: 2))
        #expect(s.previewDeck == songA && s.selectedIndex == 2)
        #expect(s.isStopped && s.liveSlide == nil)
    }
}
