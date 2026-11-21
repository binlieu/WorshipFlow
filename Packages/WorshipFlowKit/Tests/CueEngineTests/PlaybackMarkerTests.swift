// CUE-001 (AUTO-08): playback markers.
import Testing
import Foundation
@testable import CueEngine

private func marker(_ t: Double, _ tag: Int = 0) -> PlaybackMarker {
    PlaybackMarker(id: UUID(), time: t, actions: [.prop(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", tag))") ?? UUID(), isOn: true)])
}

private let frame = 1.0 / MarkerTracker.defaultFrameRate     // one frame at 59.94 fps, 16.683 ms

@Suite struct MarkerFiringTests {
    @Test func theDefaultFrameRateIs5994() {
        #expect(abs(MarkerTracker.defaultFrameRate - 59.94) < 0.001)
    }

    @Test(arguments: [0.5, 1.0, 3.3333, 5.0, 7.77, 12.5, 59.9, 120.016])
    func playbackAt5994FiresOnceWithinOneFrameOfTheMarker(_ time: Double) {
        let m = marker(time)
        var tracker = MarkerTracker(markers: [m])
        tracker.start(at: 0)
        var firedAt: [Double] = []
        var k = 1
        while Double(k) * frame < time + 2 {
            let t = Double(k) * frame
            if !tracker.advance(to: t).isEmpty { firedAt.append(t) }
            k += 1
        }
        #expect(firedAt.count == 1)
        if let f = firedAt.first { #expect(abs(f - time) <= frame, "fired at \(f) for marker at \(time)") }
    }

    @Test func aMarkerFiresWhenPlaybackReachesItNotBefore() {
        var t = MarkerTracker(markers: [marker(5)])
        t.start(at: 0)
        #expect(t.advance(to: 4.9).isEmpty)
        #expect(t.advance(to: 4.99).isEmpty)           // 10 ms short: more than half a frame, so not yet
        #expect(t.advance(to: 5.005).count == 1)
        #expect(t.advance(to: 6).isEmpty)              // never again
    }

    @Test func halfAFrameShortStillCountsAsReached() {
        var t = MarkerTracker(markers: [marker(5)])
        t.start(at: 0)
        #expect(t.advance(to: 4.9985).count == 1)       // 1.5 ms short: the same video frame
    }

    @Test func markersCrossedInOneStepComeBackInTimeOrderThenWrittenOrder() {
        let a = marker(10, 1), b = marker(5, 2), c = marker(10, 3), d = marker(12.5, 4)
        var t = MarkerTracker(markers: [a, b, c, d])
        t.start(at: 0)
        #expect(t.advance(to: 11).map(\.id) == [b.id, a.id, c.id])
        #expect(t.advance(to: 13).map(\.id) == [d.id])
    }

    @Test func aMarkerAtTimeZeroFiresWhenPlaybackStartsFromTheBeginning() {
        let m = marker(0)
        var t = MarkerTracker(markers: [m])
        t.start(at: 0)
        #expect(t.advance(to: frame).map(\.id) == [m.id])
    }

    @Test func theFirstPositionWithoutAStartIsTreatedAsAJumpSoAttachingMidClipFiresNothingOld() {
        var t = MarkerTracker(markers: [marker(5), marker(10)])
        #expect(t.advance(to: 30).isEmpty)
        #expect(t.position == 30)
    }

    @Test func markersCarryTheirActions() {
        let m = marker(1, 7)
        var t = MarkerTracker(markers: [m])
        t.start(at: 0)
        #expect(t.advance(to: 1.1).first?.actions == m.actions)
    }

    @Test func invalidPositionsAndMarkersAreIgnored() {
        var t = MarkerTracker(markers: [marker(.nan), marker(-1), marker(.infinity), marker(5)])
        t.start(at: 0)
        #expect(t.advance(to: .nan).isEmpty)
        #expect(t.advance(to: -3).isEmpty)
        #expect(t.advance(to: .infinity).isEmpty)
        #expect(t.position == 0)
        #expect(t.advance(to: 6).count == 1)
    }

    @Test func noMarkersNoTrouble() {
        var t = MarkerTracker(markers: [])
        t.start(at: 0)
        #expect(t.advance(to: 10).isEmpty)
    }
}

@Suite struct MarkerSeekTests {
    @Test func aSeekForwardDoesNotFireTheMarkersJumpedOver() {
        let m5 = marker(5), m10 = marker(10), m125 = marker(12.5)
        var t = MarkerTracker(markers: [m5, m10, m125])
        t.start(at: 0)
        #expect(t.advance(to: 1).isEmpty)
        t.seek(to: 11)
        #expect(t.advance(to: 11.1).isEmpty)
        #expect(t.advance(to: 12.6).map(\.id) == [m125.id])
    }

    @Test func aSeekBackwardReArmsMarkersAfterTheNewPosition() {
        let m5 = marker(5), m10 = marker(10), m125 = marker(12.5)
        var t = MarkerTracker(markers: [m5, m10, m125])
        t.start(at: 0)
        #expect(t.advance(to: 13).map(\.id) == [m5.id, m10.id, m125.id])
        t.seek(to: 7)
        #expect(t.advance(to: 13).map(\.id) == [m10.id, m125.id])     // 5 is before the new position: stays quiet
    }

    @Test func seekingToTheStartReArmsEverythingAfterIt() {
        let m5 = marker(5)
        var t = MarkerTracker(markers: [m5])
        t.start(at: 0)
        _ = t.advance(to: 6)
        t.seek(to: 0)
        #expect(t.advance(to: 6).map(\.id) == [m5.id])
    }

    @Test func landingExactlyOnAMarkerDoesNotFireItButLandingAFrameBeforeDoes() {
        let m = marker(10)
        var t = MarkerTracker(markers: [m])
        t.seek(to: 10)
        #expect(t.advance(to: 10.01).isEmpty)
        t.seek(to: 10 - 2 * frame)
        #expect(t.advance(to: 10.0).map(\.id) == [m.id])
    }

    @Test func aBackwardStepOfMoreThanAFrameWithoutASeekCallIsTreatedAsASeekBack() {
        let m5 = marker(5)
        var t = MarkerTracker(markers: [m5])
        t.start(at: 0)
        #expect(t.advance(to: 6).count == 1)
        #expect(t.advance(to: 3).isEmpty)
        #expect(t.position == 3)
        #expect(t.advance(to: 5.5).map(\.id) == [m5.id])
    }

    @Test func aBackwardWobbleOfLessThanAFrameIsIgnored() {
        var t = MarkerTracker(markers: [marker(5)])
        t.start(at: 0)
        #expect(t.advance(to: 5.01).count == 1)
        #expect(t.advance(to: 5.01 - frame / 2).isEmpty)
        #expect(t.position == 5.01)
        #expect(t.advance(to: 5.03).isEmpty)
    }

    @Test func startingAgainRestartsFromThatPosition() {
        let m5 = marker(5)
        var t = MarkerTracker(markers: [m5])
        t.start(at: 0)
        _ = t.advance(to: 6)
        t.start(at: 0)
        #expect(t.advance(to: 6).map(\.id) == [m5.id])
        t.start(at: 5)                                    // restarting exactly on the marker includes it
        #expect(t.advance(to: 5.02).map(\.id) == [m5.id])
    }
}

@Suite struct MarkerPauseTests {
    @Test func pausingExactlyOnAMarkerFiresItOnce() {
        let m = marker(5)
        var t = MarkerTracker(markers: [m])
        t.start(at: 0)
        #expect(t.advance(to: 4.9).isEmpty)
        #expect(t.pause(at: 5.0).map(\.id) == [m.id])
        #expect(t.pause(at: 5.0).isEmpty)                 // still paused there
        #expect(t.advance(to: 5.0).isEmpty)
        #expect(t.advance(to: 5.0167).isEmpty)           // resumed
    }

    @Test func pausingExactlyOnAMarkerAfterAFreshStartFiresItOnce() {
        let m = marker(5)
        var t = MarkerTracker(markers: [m])
        t.start(at: 5)
        #expect(t.pause(at: 5).map(\.id) == [m.id])
        #expect(t.pause(at: 5).isEmpty)
    }

    @Test func pausingJustBeforeAMarkerDoesNotFireAndResumingFiresIt() {
        let m = marker(5)
        var t = MarkerTracker(markers: [m])
        t.start(at: 0)
        #expect(t.pause(at: 4.95).isEmpty)
        #expect(t.advance(to: 5.01).map(\.id) == [m.id])
    }
}

@Suite struct MarkerLoopTests {
    @Test func aLoopingClipFiresEveryMarkerOnEveryPass() {
        let ids = [marker(5), marker(10), marker(12.5)]
        var t = MarkerTracker(markers: ids, duration: 15, loops: true)
        t.start(at: 0)
        var counts: [UUID: Int] = [:]
        var clock = 0.0
        let step = 0.05
        for _ in 0..<Int(45.0 / step) {                     // three full passes
            clock += step
            let position = clock.truncatingRemainder(dividingBy: 15)
            for m in t.advance(to: position) { counts[m.id, default: 0] += 1 }
        }
        #expect(ids.map { counts[$0.id] ?? 0 } == [3, 3, 3])
    }

    @Test func aMarkerNearTheEndStillFiresInThePassThatWrapsBeforeReachingIt() {
        let late = marker(14.9)
        var t = MarkerTracker(markers: [late], duration: 15, loops: true)
        t.start(at: 0)
        #expect(t.advance(to: 14.0).isEmpty)
        // The next frame the player reports is already in the next pass.
        #expect(t.advance(to: 0.02).map(\.id) == [late.id])
        #expect(t.advance(to: 14.95).map(\.id) == [late.id])    // and it fires again the next time around
    }

    @Test func aMarkerAtTheStartFiresOnEveryWrapAndMarkersBeyondTheEndNever() {
        let first = marker(0), beyond = marker(20)
        var t = MarkerTracker(markers: [first, beyond], duration: 15, loops: true)
        t.start(at: 0)
        #expect(t.advance(to: frame).map(\.id) == [first.id])
        #expect(t.advance(to: 14.99).isEmpty)
        #expect(t.advance(to: 0.02).map(\.id) == [first.id])
        #expect(t.advance(to: 14.99).isEmpty)
    }

    @Test func withoutALoopFlagAWrapIsJustASeekBackAndMarkersFireAgainWhenReachedAgain() {
        let m = marker(5)
        var t = MarkerTracker(markers: [m], duration: 15, loops: false)
        t.start(at: 0)
        #expect(t.advance(to: 14.9).map(\.id) == [m.id])
        #expect(t.advance(to: 0.02).isEmpty)
        #expect(t.advance(to: 5.01).map(\.id) == [m.id])
    }

    @Test func aLoopWithoutAKnownDurationReArmsOnTheBackwardStep() {
        let m = marker(5)
        var t = MarkerTracker(markers: [m], duration: nil, loops: true)
        t.start(at: 0)
        #expect(t.advance(to: 14.9).map(\.id) == [m.id])
        #expect(t.advance(to: 0.02).isEmpty)
        #expect(t.advance(to: 5.01).map(\.id) == [m.id])
    }

    @Test func aMarkerAtTheClipEndFiresInAPlainClipButNotOneBeyondIt() {
        let atEnd = marker(15), beyond = marker(16)
        var t = MarkerTracker(markers: [atEnd, beyond], duration: 15)
        t.start(at: 0)
        #expect(t.advance(to: 15).map(\.id) == [atEnd.id])
        #expect(t.advance(to: 20).isEmpty)
    }
}

@Suite struct MarkerEditingTests {
    @Test func replacingMarkersWhilePlayingKeepsFiredOnesQuietAndArmsNewOnesAfterThePlayhead() {
        let m5 = marker(5), m20 = marker(20), old = marker(3)
        var t = MarkerTracker(markers: [m5])
        t.start(at: 0)
        _ = t.advance(to: 11)
        t.replaceMarkers([m5, m20, old])
        #expect(t.advance(to: 12).isEmpty)
        #expect(t.advance(to: 21).map(\.id) == [m20.id])
    }

    @Test func aMarkerMovedLaterIsArmedAgain() {
        var m = marker(5)
        var t = MarkerTracker(markers: [m])
        t.start(at: 0)
        _ = t.advance(to: 6)
        m.time = 8
        t.replaceMarkers([m])
        #expect(t.advance(to: 9).map(\.id) == [m.id])
    }

    @Test func markersAreCodable() throws {
        let m = marker(4.25, 3)
        let back = try JSONDecoder().decode(PlaybackMarker.self, from: JSONEncoder().encode(m))
        #expect(back == m)
    }
}
