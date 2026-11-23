// FIX-W item 1 (MEDIA, CUE-33; REVIEW-5 M1 and L5): a marker the playhead crossed since the last observer tick is delivered before a pause, a
// Stop or the clip's end stops the observer, once per crossing. The clock and positions are injected; no wall clock.
import Testing
import Foundation
import CueEngine
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXW_MarkerLastLookTests {
    func live(_ rig: MarkerRig, _ clip: MediaAsset) {
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.playForeground(clip.id)
        rig.markers.tick()
    }

    @Test func aMarkerNearTheEndOfAClipRunsWhenTheClipEndsBetweenTwoTicks() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [9.9])                      // the clip is 10 s long
        live(rig, clip)
        rig.media.clock.advance(9.0); rig.markers.tick()
        #expect(rig.fired.isEmpty)
        rig.media.clock.advance(2)                                     // ended, no tick in between
        #expect(rig.media.model.tick())
        #expect(rig.fired.map(\.time) == [9.9])
        #expect(!rig.scheduler.isRunning)
    }

    @Test func aMarkerCrossedJustBeforeAPauseRunsOnceAndNotAgainOnResume() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        live(rig, clip)
        rig.media.clock.advance(3.9); rig.markers.tick()
        rig.media.clock.advance(0.12)                                  // 4.02: crossed since the last tick
        rig.media.model.pause()
        #expect(rig.fired.map(\.time) == [4])
        #expect(!rig.scheduler.isRunning)
        rig.media.model.resume()
        rig.media.clock.advance(1); rig.markers.tick()
        #expect(rig.fired.map(\.time) == [4])
    }

    @Test func aMarkerThatRanJustBeforeAPauseDoesNotRunAgainOnResume() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        live(rig, clip)
        rig.media.clock.advance(4.0); rig.markers.tick()               // runs at its time
        #expect(rig.fired.count == 1)
        rig.media.clock.advance(0.004)                                 // inside half a frame after it
        rig.media.model.pause()
        rig.media.model.resume()
        rig.markers.tick()                                             // the first look after resuming, still at 4.004
        #expect(rig.fired.count == 1)
    }

    @Test func aMarkerCrossedJustBeforeStopRuns() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        live(rig, clip)
        rig.media.clock.advance(3.9); rig.markers.tick()
        rig.media.clock.advance(0.12)
        rig.media.model.stopForeground()
        #expect(rig.fired.map(\.time) == [4])
        #expect(!rig.scheduler.isRunning)
    }

    @Test func aMarkerCrossedJustBeforeTheScreensStopRuns() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        live(rig, clip)
        rig.media.clock.advance(3.9); rig.markers.tick()
        rig.media.clock.advance(0.12)
        rig.media.model.showStateChanged(isLive: false)
        #expect(rig.fired.map(\.time) == [4])
        #expect(!rig.scheduler.isRunning)
    }

    @Test func aSeekAcrossAMarkerStillRunsNothing() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        live(rig, clip)
        rig.media.clock.advance(3.9); rig.markers.tick()
        rig.media.model.seek(to: 6)                                    // jumps over 4 from 3.9
        rig.markers.tick()
        rig.media.model.stopForeground()
        #expect(rig.fired.isEmpty)
    }

    @Test func aLoopedBackgroundDoesNotRunAMarkerTwiceAcrossAPause() async throws {
        let rig = try MarkerRig()
        let clip = await rig.clip(markers: [4])
        await rig.media.model.setMarkIn(2, for: clip.id)
        await rig.media.model.setMarkOut(6, for: clip.id)
        rig.media.model.showStateChanged(isLive: true)
        rig.media.model.setBackground(clip.id)
        rig.markers.tick()
        rig.media.clock.advance(2.0); rig.markers.tick()              // exactly at 4
        rig.media.clock.advance(0.004)
        rig.media.model.pauseBackground()
        rig.media.model.resumeBackground()
        rig.markers.tick()
        #expect(rig.fired.count == 1)
    }

    @Test func nothingTicksWhileIdleWhenAClipWithoutMarkersIsStopped() async throws {
        let rig = try MarkerRig()
        let bare = await rig.clip("bare.mov")
        live(rig, bare)
        rig.media.clock.advance(2)
        rig.media.model.pause()
        rig.media.model.stopForeground()
        #expect(rig.scheduler.starts == 0 && rig.fired.isEmpty)
    }
}
