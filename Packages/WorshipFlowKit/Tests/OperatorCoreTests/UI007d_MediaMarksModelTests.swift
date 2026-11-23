// UI-007d (MEDIA): mark in and mark out on a bin item, and what the live layers do with them. A fake prober, a hand-moved clock and an in-memory
// library; no player, no wall clock. Written before the implementation.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI007d_MediaMarksModelTests {
    @Test func marksAreSetAtATimeTypedOrAtThePlayheadAndClearedAndTheyPersist() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")                     // 10 s
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(8.5, for: clip.id)
        #expect(rig.model.asset(clip.id)?.markIn == 2 && rig.model.asset(clip.id)?.markOut == 8.5)
        #expect(rig.model.lastError == nil)
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.asset(clip.id)?.markIn == 2 && again.model.asset(clip.id)?.markOut == 8.5)
        await rig.model.setMarkIn(nil, for: clip.id)             // clear one
        #expect(rig.model.asset(clip.id)?.markIn == nil && rig.model.asset(clip.id)?.markOut == 8.5)
        await rig.model.clearMarks(for: clip.id)
        #expect(rig.model.asset(clip.id)?.markIn == nil && rig.model.asset(clip.id)?.markOut == nil)
    }

    @Test func aMarkThatDoesNotFitIsRefusedWithWordsAndNothingChanges() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(3, for: clip.id)
        await rig.model.setMarkOut(2, for: clip.id)              // out before in
        #expect(rig.model.asset(clip.id)?.markOut == nil)
        #expect(try #require(rig.model.lastError).contains("before"))
        rig.model.dismissError()
        await rig.model.setMarkOut(3, for: clip.id)              // out equal to in leaves nothing to play
        #expect(rig.model.asset(clip.id)?.markOut == nil && rig.model.lastError != nil)
        rig.model.dismissError()
        await rig.model.setMarkOut(11, for: clip.id)             // past the end of a 10 s clip
        #expect(rig.model.asset(clip.id)?.markOut == nil && rig.model.lastError != nil)
        rig.model.dismissError()
        await rig.model.setMarkIn(-1, for: clip.id)
        #expect(rig.model.asset(clip.id)?.markIn == 3 && rig.model.lastError != nil)
    }

    @Test func aPictureAndASoundHaveNoMarksToSetHere() async throws {
        let rig = try MediaRig()
        let picture = await rig.add("cross.png")
        await rig.model.setMarkIn(1, for: picture.id)
        #expect(rig.model.asset(picture.id)?.markIn == nil && rig.model.lastError != nil)
        rig.model.dismissError()
        let sound = await rig.add("song.mp3")
        await rig.model.setMarkIn(1, for: sound.id)            // a sound plays through the audio player, which does not honour marks yet
        #expect(rig.model.asset(sound.id)?.markIn == nil && rig.model.lastError != nil)
    }

    @Test func aClipPlayedOverTheWordsStartsAtItsInMarkAndEndsAtItsOutMark() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(5, for: clip.id)
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        let t0 = rig.clock.now()
        let readout = try #require(rig.model.foregroundReadout())
        #expect(readout.position == 2 && readout.duration == 10 && readout.rangeStart == 2 && readout.rangeEnd == 5)
        rig.clock.advance(2.9)
        #expect(!rig.model.tick() && rig.model.layers.foreground != nil)
        rig.clock.advance(0.1)                                   // 3 s of playing = the out mark
        #expect(rig.model.tick() && rig.model.layers.foreground == nil)
        #expect(t0 < rig.clock.now())
    }

    @Test func aClipSetToLoopRestartsAtTheInMarkWhenItReachesTheOutMark() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(5, for: clip.id)
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.model.setForegroundLoops(true)
        rig.clock.advance(3)
        #expect(rig.model.tick())
        let f = try #require(rig.model.layerParts.foreground)
        #expect(f.transport.position(at: rig.clock.now()) == 2 && f.transport.status(at: rig.clock.now()) == .playing)
    }

    @Test func aBackgroundLoopWrapsInsideItsMarks() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(5, for: clip.id)
        rig.model.setBackground(clip.id)
        let b = try #require(rig.model.layerParts.background)
        rig.clock.advance(4)                                     // one pass is 3 s
        #expect(abs(b.transport.position(at: rig.clock.now()) - 3) < 1e-9 && b.transport.loopCount(at: rig.clock.now()) == 1)
    }

    @Test func seekingTheLiveClipStaysInsideTheMarks() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(5, for: clip.id)
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        rig.model.seek(to: 9)
        #expect(rig.model.foregroundReadout()?.position == 5)
        rig.model.seek(to: 0)
        #expect(rig.model.foregroundReadout()?.position == 2)
    }

    @Test func editingMarksNeverChangesAClipThatIsOnAirNow() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(clip.id)
        let before = rig.model.layers.foreground
        await rig.model.setMarkIn(4, for: clip.id)
        await rig.model.setMarkOut(6, for: clip.id)
        #expect(rig.model.layers.foreground == before)          // it keeps playing as it was started; the new marks apply from the next start
        rig.model.stopForeground()
        rig.model.playForeground(clip.id)
        #expect(rig.model.foregroundReadout()?.position == 4)
    }

    @Test func aSlidesOwnBackgroundIsPlayedWithTheBinItemsCurrentMarksAndStoresNone() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        let stored = MediaSelection(asset: try #require(rig.model.asset(clip.id)))
        #expect(stored.markIn == nil)                            // what a slide keeps has no marks
        let json = String(decoding: try JSONEncoder().encode(stored), as: UTF8.self)
        #expect(!json.contains("mark"))
        let decoded = try JSONDecoder().decode(MediaSelection.self, from: Data(json.utf8))
        #expect(decoded == stored && decoded.markIn == nil && decoded.markOut == nil)      // a slide read back has no marks of its own
        let playing = MediaSelection.forPlayback(try #require(rig.model.asset(clip.id)))
        let playingJSON = String(decoding: try JSONEncoder().encode(playing), as: UTF8.self)
        #expect(playing.markIn == 2 && !playingJSON.contains("mark"))
        let played = stored.withMarks(of: rig.model.asset(clip.id))
        #expect(played.markIn == 2)
        var layers = MediaLayers()
        layers.setBackground(played, at: 0)
        #expect(layers.background?.transport.position(at: 0) == 2)
    }

    @Test func theSampleTheMarkerFeedReadsFollowsTheClockAndTheMarks() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        await rig.model.setMarkIn(2, for: clip.id)
        await rig.model.setMarkOut(5, for: clip.id)
        rig.model.showStateChanged(isLive: true)
        #expect(rig.model.playbackSample(.foreground) == nil)    // nothing on the layer
        rig.model.playForeground(clip.id)
        let s0 = try #require(rig.model.playbackSample(.foreground))
        #expect(s0.assetID == clip.id && s0.position == 2 && s0.rangeStart == 2 && s0.rangeEnd == 5 && s0.isPlaying && s0.loopCount == 0)
        rig.clock.advance(1)
        #expect(rig.model.playbackSample(.foreground)?.position == 3)
        rig.model.seek(to: 4)
        let s1 = try #require(rig.model.playbackSample(.foreground))
        #expect(s1.seekCount == s0.seekCount + 1 && s1.epoch == s0.epoch)
        rig.model.restartForeground()
        let s2 = try #require(rig.model.playbackSample(.foreground))
        #expect(s2.epoch == s0.epoch + 1)                        // played again: a new pass for the markers
        rig.model.pause()
        #expect(rig.model.playbackSample(.foreground)?.isPlaying == false)
    }

    @Test func noSampleWhileTheShowIsNotLive() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.setBackground(clip.id)                          // a background can be chosen with the screens stopped
        #expect(rig.model.playbackSample(.background) == nil)
        rig.model.showStateChanged(isLive: true)
        #expect(rig.model.playbackSample(.background) != nil)
        rig.model.showStateChanged(isLive: false)
        #expect(rig.model.playbackSample(.background) == nil)
    }
}

@Suite struct UI007d_MediaTimeTextTests {
    @Test func typedTimesAreReadInTheWaysAnOperatorWritesThem() {
        #expect(MediaTimeText.parse("12") == 12)
        #expect(MediaTimeText.parse("12.5") == 12.5)
        #expect(MediaTimeText.parse("1:05") == 65)
        #expect(MediaTimeText.parse("01:05.5") == 65.5)
        #expect(abs((MediaTimeText.parse(" 0:12.3 ") ?? 0) - 12.3) < 1e-9)
        #expect(MediaTimeText.parse("1:02:03") == 3723)
        #expect(MediaTimeText.parse("0") == 0)
    }

    @Test func textThatIsNoTimeIsRefused() {
        for text in ["", "  ", "abc", "-5", "1:75", "1:", ":30", "1::30", "1:2:3:4", "1e3", "nan", "inf", "1,5", "12s"] {
            #expect(MediaTimeText.parse(text) == nil, "\(text)")
        }
    }

    @Test func aTimeIsWrittenAsMinutesSecondsAndTenths() {
        #expect(MediaTimeText.format(0) == "00:00.0")
        #expect(MediaTimeText.format(65.5) == "01:05.5")
        #expect(MediaTimeText.format(12.34) == "00:12.3")
        #expect(MediaTimeText.format(59.96) == "01:00.0")     // rounds to the tenth, never shows 00:59.10
        #expect(MediaTimeText.format(.nan) == "00:00.0")
        #expect(abs((MediaTimeText.parse(MediaTimeText.format(83.7)) ?? 0) - 83.7) < 1e-9)
    }
}
