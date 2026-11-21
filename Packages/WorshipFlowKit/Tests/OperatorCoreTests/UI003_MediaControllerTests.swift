// UI-003 Part 1: what the media controller row drives. A clip over the slide can loop; a background video can be
// paused, restarted and sought like the clip; an image has no clock.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI003_MediaControllerTests {
    @Test func aLoopingClipStartsAgainInsteadOfEnding() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")                       // 10 s
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.model.setForegroundLoops(true)
        #expect(rig.model.foregroundLoops)
        rig.clock.advance(10.5)
        #expect(rig.model.tick())                                  // it reached its end ...
        let readout = try #require(rig.model.foregroundReadout())  // ... and is still there, playing from the start
        #expect(readout.isPlaying && readout.position < 1)
    }

    @Test func aClipThatDoesNotLoopEndsAndTheNextClipStartsWithoutLooping() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.clock.advance(10.5)
        #expect(rig.model.tick())
        #expect(rig.model.foregroundReadout() == nil)
        rig.model.setForegroundLoops(true)                          // nothing is playing: no clip to loop
        #expect(!rig.model.foregroundLoops)
        rig.model.playForeground(clip.id)
        #expect(!rig.model.foregroundLoops)                         // a new clip begins without looping
    }

    @Test func theLoopChoiceGoesWhenTheClipIsStopped() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.model.setForegroundLoops(true)
        rig.model.stopForeground()
        #expect(!rig.model.foregroundLoops)
    }

    @Test func aLoopingClipSurvivesThePlayerReportingItsEnd() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.model.setForegroundLoops(true)
        rig.clock.advance(10)
        #expect(rig.model.playerReportedEnd())
        #expect(rig.model.foregroundReadout()?.isPlaying == true)
    }

    @Test func restartingTheClipGoesBackToTheStartAndPlays() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.clock.advance(4)
        rig.model.pause()
        rig.model.restartForeground()
        let r = try #require(rig.model.foregroundReadout())
        #expect(r.isPlaying && r.position < 0.5)
    }

    // MARK: Background

    @Test func aBackgroundVideoCanBePausedSoughtAndRestarted() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("waves.mov")
        rig.model.setBackground(loop.id)
        rig.clock.advance(3)
        #expect(rig.model.backgroundReadout()?.isPlaying == true)
        rig.model.pauseBackground()
        #expect(rig.model.backgroundReadout()?.status == .paused)
        rig.model.seekBackground(to: 7)
        #expect(rig.model.backgroundReadout()?.position == 7)
        rig.model.resumeBackground()
        #expect(rig.model.backgroundReadout()?.isPlaying == true)
        rig.model.restartBackground()
        #expect((rig.model.backgroundReadout()?.position ?? 9) < 0.5)
        #expect(rig.layerChanges.count >= 4)                       // the players are told each time
    }

    @Test func aBackgroundPictureHasNoClock() async throws {
        let rig = try MediaRig()
        let still = await rig.add("title.png")
        rig.model.setBackground(still.id)
        #expect(rig.model.backgroundReadout() == nil)
    }

    @Test func aBackgroundVideoKeepsLoopingAfterItsLength() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("waves.mov")
        rig.model.setBackground(loop.id)
        rig.clock.advance(25)
        #expect(rig.model.tick() == false)
        let r = try #require(rig.model.backgroundReadout())
        #expect(r.isPlaying && abs(r.position - 5) < 0.01)
    }
}
