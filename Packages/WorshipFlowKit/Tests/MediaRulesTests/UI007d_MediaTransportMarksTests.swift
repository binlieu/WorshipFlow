// UI-007d (MEDIA): a clip's mark in and mark out as the transport honours them. Pure values and a hand-moved clock: no wall clock, no player.
// Written before the implementation (test-first, risky timing logic on the live path).
import Testing
import Foundation
@testable import Domain

@Suite struct UI007d_MediaTransportMarksTests {
    @Test func aMarkedClipStartsAtItsInMarkNotAtZero() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 40)
        #expect(t.position(at: 0) == 10)                     // idle: where it will start
        t.play(at: 100)
        #expect(t.position(at: 100) == 10)
        #expect(t.position(at: 103) == 13 && t.status(at: 103) == .playing)
    }

    @Test func aClipThatDoesNotLoopEndsAtItsOutMarkAndHoldsThere() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 40)
        t.play(at: 0)
        #expect(t.status(at: 29.9) == .playing)
        #expect(t.status(at: 30) == .ended)                  // 10 + 30 = the out mark
        #expect(t.position(at: 90) == 40)
        #expect(t.remaining(at: 20) == 10 && t.remaining(at: 90) == 0)
    }

    @Test func playingAgainAfterTheEndStartsAtTheInMark() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 40)
        t.play(at: 0)
        t.play(at: 50)                                       // ended at 30: starts again
        #expect(t.position(at: 52) == 12 && t.status(at: 52) == .playing)
    }

    @Test func aLoopWrapsFromTheOutMarkBackToTheInMarkOncePerPass() {
        var t = MediaTransport(duration: 60, loops: true, markIn: 10, markOut: 40)
        t.play(at: 0)
        #expect(t.status(at: 3600) == .playing)              // a loop never ends
        #expect(t.position(at: 29.999) < 40 && t.loopCount(at: 29.999) == 0)
        #expect(t.loopCount(at: 30) == 1)                    // exactly at the out mark the pass is over
        #expect(abs(t.position(at: 30) - 10) < 1e-9)
        #expect(abs(t.position(at: 35) - 15) < 1e-9)
        #expect(t.loopCount(at: 59.999) == 1 && t.loopCount(at: 60) == 2)
        #expect(t.position(at: 45) >= 10 && t.position(at: 45) < 40)
    }

    @Test func aLoopWithOnlyAnInMarkWrapsAtTheClipEnd() {
        var t = MediaTransport(duration: 20, loops: true, markIn: 5)
        t.play(at: 0)
        #expect(t.position(at: 14.5) == 19.5)
        #expect(t.loopCount(at: 15) == 1)
        #expect(abs(t.position(at: 16) - 6) < 1e-9)
    }

    @Test func aClipWithOnlyAnOutMarkStartsAtZeroAndStopsAtTheMark() {
        var t = MediaTransport(duration: 60, loops: false, markOut: 12)
        t.play(at: 0)
        #expect(t.status(at: 11.9) == .playing && t.status(at: 12) == .ended)
        #expect(t.position(at: 99) == 12)
    }

    @Test func seekingStaysInsideTheMarks() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 40)
        t.seek(to: 5, at: 0)
        #expect(t.position(at: 0) == 10)
        t.seek(to: 55, at: 0)
        #expect(t.position(at: 0) == 40)
        var l = MediaTransport(duration: 60, loops: true, markIn: 10, markOut: 40)
        l.seek(to: 55, at: 0)
        #expect(l.position(at: 0) == 10)                     // a loop that is sent to its end starts the pass again
    }

    @Test func stopGoesBackToTheInMark() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 40)
        t.play(at: 0); t.pause(at: 5)
        #expect(t.position(at: 9) == 15)
        t.stop()
        #expect(t.status(at: 9) == .idle && t.position(at: 9) == 10)
    }

    @Test func pausingALoopKeepsItsPlaceInsideTheMarks() {
        var t = MediaTransport(duration: 60, loops: true, markIn: 10, markOut: 40)
        t.play(at: 0)
        t.pause(at: 35)                                      // one pass (30 s) plus 5 s
        #expect(abs(t.position(at: 99) - 15) < 1e-9 && t.status(at: 99) == .paused)
        t.play(at: 100)
        #expect(abs(t.position(at: 101) - 16) < 1e-9)
    }

    @Test func marksThatCannotWorkAreIgnoredAndTheWholeClipPlays() {
        let cases: [(Double?, Double?)] = [(30.0, 30.0), (40.0, 10.0), (-1.0, nil), (Double.nan, nil), (nil, 0.0), (70.0, nil)]
        for (i, o) in cases {
            var t = MediaTransport(duration: 60, loops: false, markIn: i, markOut: o)
            t.play(at: 0)
            #expect(t.position(at: 2) == 2, "in \(String(describing: i)) out \(String(describing: o))")
            #expect(t.status(at: 60) == .ended)
        }
    }

    @Test func eachMarkIsJudgedOnItsOwnSoABadInMarkDoesNotDiscardAGoodOutMark() {
        var t = MediaTransport(duration: 60, loops: false, markIn: -1, markOut: 5)
        t.play(at: 0)
        #expect(t.status(at: 4.9) == .playing && t.status(at: 5) == .ended)
    }

    @Test func aMarkOutPastTheLengthIsTheLength() {
        var t = MediaTransport(duration: 60, loops: false, markIn: 10, markOut: 90)
        t.play(at: 0)
        #expect(t.status(at: 49.9) == .playing && t.status(at: 50) == .ended && t.position(at: 99) == 60)
    }

    @Test func aClipWithNoMarksBehavesAsBefore() {
        var plain = MediaTransport(duration: 60, loops: false)
        var marked = MediaTransport(duration: 60, loops: false, markIn: nil, markOut: nil)
        plain.play(at: 5); marked.play(at: 5)
        for now in [5.0, 7.5, 64.9, 65, 100] {
            #expect(plain.position(at: now) == marked.position(at: now) && plain.status(at: now) == marked.status(at: now))
        }
        #expect(plain == marked)
    }

    @Test func storedTransportsFromBeforeMarksStillDecode() throws {
        let old = #"{"duration":60,"loops":false,"phase":"idle","base":0,"anchor":0}"#
        let t = try JSONDecoder().decode(MediaTransport.self, from: Data(old.utf8))
        #expect(t.markIn == nil && t.markOut == nil && t.duration == 60)
        var marked = MediaTransport(duration: 60, loops: true, markIn: 10, markOut: 40)
        marked.play(at: 0)
        let again = try JSONDecoder().decode(MediaTransport.self, from: JSONEncoder().encode(marked))
        #expect(again == marked && again.markIn == 10 && again.markOut == 40)
    }
}
