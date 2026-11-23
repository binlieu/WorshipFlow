// UI-007d (MEDIA, CUE-33): what the feed does with the player's position and the markers of the clip. Pure: a sample is handed in, the markers
// that were reached come out. No clock, no player, no timer. Written before the implementation (risky timing logic on the live path).
import Testing
import Foundation
import CueEngine
import Domain
@testable import OperatorCore

@Suite struct UI007d_MarkerFeedTests {
    let clip = UUID()

    func sample(_ position: Double, epoch: Int = 1, seeks: Int = 0, loops: Int = 0, playing: Bool = true, start: Double = 0, end: Double? = 60,
                asset: UUID? = nil) -> PlaybackSample {
        PlaybackSample(assetID: asset ?? clip, epoch: epoch, seekCount: seeks, position: position, loopCount: loops, isPlaying: playing,
                       rangeStart: start, rangeEnd: end)
    }

    func marker(_ time: Double, _ id: String = "") -> PlaybackMarker {
        PlaybackMarker(id: id.isEmpty ? UUID() : UUID(uuidString: id) ?? UUID(), time: time, actions: [.stopForeground])
    }

    func times(_ fired: [PlaybackMarker]) -> [Double] { fired.map(\.time) }

    @Test func aMarkerFiresOnceWhenPlaybackReachesIt() {
        var feed = MarkerFeed()
        let m = [marker(10)]
        #expect(feed.poll(.foreground, sample: sample(9.0), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(9.9), markers: m).isEmpty)
        #expect(times(feed.poll(.foreground, sample: sample(10.05), markers: m)) == [10])
        #expect(feed.poll(.foreground, sample: sample(10.2), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(30), markers: m).isEmpty)
    }

    @Test func severalMarkersPassedBetweenTwoPollsFireInTimeOrder() {
        var feed = MarkerFeed()
        let m = [marker(12), marker(10), marker(11)]
        _ = feed.poll(.foreground, sample: sample(9), markers: m)
        #expect(times(feed.poll(.foreground, sample: sample(12.5), markers: m)) == [10, 11, 12])
    }

    @Test func aMarkerAtTheInMarkFiresWhenTheClipStarts() {
        var feed = MarkerFeed()
        let m = [marker(10), marker(4)]                       // the one at 4 is before the in mark: playback never gets there
        #expect(times(feed.poll(.foreground, sample: sample(10, start: 10, end: 40), markers: m)) == [10])
        #expect(feed.poll(.foreground, sample: sample(20), markers: m).isEmpty)
    }

    @Test func aMarkerAfterTheOutMarkNeverFires() {
        var feed = MarkerFeed()
        let m = [marker(50)]
        _ = feed.poll(.foreground, sample: sample(10, start: 10, end: 40), markers: m)
        #expect(feed.poll(.foreground, sample: sample(39.9, start: 10, end: 40), markers: m).isEmpty)
    }

    @Test func aSeekForwardOverAMarkerDoesNotFireIt() {
        var feed = MarkerFeed()
        let m = [marker(10), marker(25)]
        _ = feed.poll(.foreground, sample: sample(5), markers: m)
        #expect(feed.poll(.foreground, sample: sample(20, seeks: 1), markers: m).isEmpty)      // the operator jumped from 5 to 20
        #expect(times(feed.poll(.foreground, sample: sample(25.1, seeks: 1), markers: m)) == [25])   // the next one still fires
    }

    @Test func aSeekBackMakesTheMarkerFireAgainWhenPlayedPastItAgain() {
        var feed = MarkerFeed()
        let m = [marker(10)]
        _ = feed.poll(.foreground, sample: sample(9), markers: m)
        #expect(times(feed.poll(.foreground, sample: sample(10.1), markers: m)) == [10])
        #expect(feed.poll(.foreground, sample: sample(5, seeks: 1), markers: m).isEmpty)       // back to 5: nothing fires on the jump
        #expect(times(feed.poll(.foreground, sample: sample(10.1, seeks: 1), markers: m)) == [10])   // a new crossing
        #expect(feed.poll(.foreground, sample: sample(11, seeks: 1), markers: m).isEmpty)
    }

    @Test func aSeekBackAndForthWithinOneFrameDoesNotFireTwice() {
        var feed = MarkerFeed()
        let m = [marker(10)]
        _ = feed.poll(.foreground, sample: sample(9.9), markers: m)
        #expect(times(feed.poll(.foreground, sample: sample(10.0), markers: m)) == [10])
        // 10.0 -> 9.99 -> 10.0, two seeks, less than a frame (16.7 ms at 59.94) apart
        #expect(feed.poll(.foreground, sample: sample(9.99, seeks: 1), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(10.0, seeks: 2), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(10.3, seeks: 2), markers: m).isEmpty)
    }

    @Test func aPositionThatStepsBackByLessThanAFrameIsJitterNotACrossing() {
        var feed = MarkerFeed()
        let m = [marker(10)]
        _ = feed.poll(.foreground, sample: sample(9.9), markers: m)
        _ = feed.poll(.foreground, sample: sample(10.01), markers: m)
        #expect(feed.poll(.foreground, sample: sample(10.003), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(10.02), markers: m).isEmpty)
    }

    @Test func aLoopFiresEachMarkerOncePerPassIncludingOneAtTheOutMark() {
        var feed = MarkerFeed()
        let m = [marker(20), marker(40)]                       // out mark at 40: a marker exactly there belongs to the pass that ends
        let s = { (p: Double, loops: Int) in self.sample(p, loops: loops, start: 10, end: 40) }
        _ = feed.poll(.foreground, sample: s(10, 0), markers: m)
        #expect(times(feed.poll(.foreground, sample: s(20.05, 0), markers: m)) == [20])
        #expect(feed.poll(.foreground, sample: s(39.9, 0), markers: m).isEmpty)
        // wrapped: the pass is over, the marker at the out mark fires, the new pass has not reached 20 yet
        #expect(times(feed.poll(.foreground, sample: s(10.2, 1), markers: m)) == [40])
        #expect(times(feed.poll(.foreground, sample: s(20.05, 1), markers: m)) == [20])
        #expect(feed.poll(.foreground, sample: s(30, 1), markers: m).isEmpty)
        #expect(times(feed.poll(.foreground, sample: s(10.1, 2), markers: m)) == [40])
    }

    @Test func aWrapThatAlreadyPassedAMarkerOfTheNewPassFiresBothInOrder() {
        var feed = MarkerFeed()
        let m = [marker(11), marker(39)]
        let s = { (p: Double, loops: Int) in self.sample(p, loops: loops, start: 10, end: 40) }
        _ = feed.poll(.foreground, sample: s(38, 0), markers: m)
        #expect(times(feed.poll(.foreground, sample: s(11.5, 1), markers: m)) == [39, 11])     // the rest of the old pass, then the new one
    }

    @Test func nothingFiresWhileTheClipIsNotLive() {
        var feed = MarkerFeed()
        let m = [marker(10)]
        _ = feed.poll(.foreground, sample: sample(9), markers: m)
        #expect(feed.poll(.foreground, sample: nil, markers: m).isEmpty)       // the show stopped or the clip left the layer
        #expect(!feed.isTracking(.foreground))
        // it comes back later: a new start from where it is, without remembering the old pass
        #expect(feed.poll(.foreground, sample: sample(10.5), markers: m).isEmpty)
        #expect(feed.isTracking(.foreground))
    }

    @Test func aClipStartedAgainStartsANewPassThatFiresItsMarkersAgain() {
        var feed = MarkerFeed()
        let m = [marker(0), marker(10)]
        #expect(times(feed.poll(.foreground, sample: sample(0), markers: m)) == [0])
        #expect(times(feed.poll(.foreground, sample: sample(10.2), markers: m)) == [10])
        #expect(times(feed.poll(.foreground, sample: sample(0, epoch: 2), markers: m)) == [0])      // played again from the start
        #expect(times(feed.poll(.foreground, sample: sample(10.2, epoch: 2), markers: m)) == [10])
    }

    @Test func anotherClipOnTheLayerStartsFresh() {
        var feed = MarkerFeed()
        let other = UUID()
        _ = feed.poll(.foreground, sample: sample(9), markers: [marker(10)])
        #expect(feed.poll(.foreground, sample: sample(10.5, asset: other), markers: [marker(10)]).isEmpty)   // arrived already past it
    }

    @Test func aMarkerAddedWhilePlayingFiresWhenReachedAndOneBehindThePlayheadDoesNot() {
        var feed = MarkerFeed()
        _ = feed.poll(.foreground, sample: sample(9), markers: [])
        let ahead = marker(15), behind = marker(5)
        feed.markersChanged(.foreground, markers: [ahead, behind])
        #expect(times(feed.poll(.foreground, sample: sample(15.1), markers: [ahead, behind])) == [15])
    }

    @Test func aMarkerMovedAheadOfThePlayheadIsArmedAgain() {
        var feed = MarkerFeed()
        let m = marker(5)
        _ = feed.poll(.foreground, sample: sample(4), markers: [m])
        #expect(times(feed.poll(.foreground, sample: sample(5.1), markers: [m])) == [5])
        var moved = m; moved.time = 20
        feed.markersChanged(.foreground, markers: [moved])
        #expect(times(feed.poll(.foreground, sample: sample(20.1), markers: [moved])) == [20])
    }

    @Test func aPausedClipFiresNothingAndAPausedSeekDoesNotFireOnResume() {
        var feed = MarkerFeed()
        let m = [marker(10), marker(30)]
        _ = feed.poll(.foreground, sample: sample(5), markers: m)
        #expect(feed.poll(.foreground, sample: sample(5, playing: false), markers: m).isEmpty)
        #expect(feed.poll(.foreground, sample: sample(25, seeks: 1, playing: false), markers: m).isEmpty)   // seeked while paused over 10
        #expect(feed.poll(.foreground, sample: sample(25.2, seeks: 1), markers: m).isEmpty)
        #expect(times(feed.poll(.foreground, sample: sample(30.1, seeks: 1), markers: m)) == [30])
    }

    @Test func eachLayerKeepsItsOwnPlace() {
        var feed = MarkerFeed()
        let other = UUID()
        _ = feed.poll(.foreground, sample: sample(9), markers: [marker(10)])
        _ = feed.poll(.background, sample: sample(9, asset: other), markers: [marker(10)])
        #expect(times(feed.poll(.background, sample: sample(10.1, asset: other), markers: [marker(10)])) == [10])
        #expect(times(feed.poll(.foreground, sample: sample(10.1), markers: [marker(10)])) == [10])
    }

    @Test func aMarkerThatIsNotARealTimeIsIgnored() {
        var feed = MarkerFeed()
        let m = [marker(.nan), marker(-1), marker(5)]
        _ = feed.poll(.foreground, sample: sample(1), markers: m)
        #expect(times(feed.poll(.foreground, sample: sample(6), markers: m)) == [5])
    }
}
