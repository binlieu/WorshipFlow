// UI-007d (MEDIA): the real player honours the marks. A tiny movie that is red for its first second and blue for its second, decoded by
// AVFoundation, no window and no sound. The transport rules themselves (position, end, wrap) are tested as pure values in MediaRulesTests; this
// proves the player is where the transport says: it starts at the in mark, stops at the out mark, and loops inside the marks.
import Testing
import Foundation
import CoreVideo
import Domain
@testable import MediaEngine

@Suite(.serialized) struct UI007d_PlayerMarksTests {
    @Test func aClipWithAnInMarkStartsAtThePictureOfTheInMark() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2, markIn: 1)
        #expect(source.position() == 1)                                   // idle, ready at the in mark
        source.play()
        var sawRed = false
        #expect(await TestMedia.wait { let b = source.latestPixelBuffer(); if isRed(b) { sawRed = true }; return isBlue(b) })
        #expect(!sawRed)                                                  // the red first second was never shown
        source.stop()
        #expect(source.position() == 1)                                   // stop goes back to the in mark, not to zero
    }

    @Test func aClipWithAnOutMarkStopsThereAndReportsItsEndOnce() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let ended = Counter()
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2, markOut: 1)
        source.setOnEnded { ended.bump() }
        source.play()
        #expect(await TestMedia.wait { source.status() == .ended })
        #expect(await TestMedia.wait { ended.value == 1 })
        var sawBlue = false
        for _ in 0..<20 { if isBlue(source.latestPixelBuffer()) { sawBlue = true }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(!sawBlue && ended.value == 1)
        #expect(source.position() == 1)
    }

    @Test func aLoopStaysInsideItsMarks() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: true, duration: 2, markIn: 1)    // only the blue second loops
        source.play()
        #expect(await TestMedia.wait { isBlue(source.latestPixelBuffer()) })
        var sawRed = false
        for _ in 0..<150 { if isRed(source.latestPixelBuffer()) { sawRed = true }; try await Task.sleep(nanoseconds: 20_000_000) }    // 3 s: it wraps at least twice
        #expect(!sawRed)
        #expect(source.status() == .playing)
        source.stop()
    }

    @Test func theRegistryOpensAClipWithTheMarksOfItsSelection() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let registry = MediaRegistry()
        let id = UUID()
        registry.register(id: id, kind: .video, url: url, duration: 2)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: id, kind: .video, duration: 2, markIn: 1), at: MediaClock.now())
        registry.apply(layers)
        let source = try #require(registry.videoSource(in: .foreground))
        #expect(source.currentTransport.markIn == 1)
        var sawRed = false
        #expect(await TestMedia.wait { let b = registry.currentPixelBuffer(for: .video(id), layer: .foreground); if isRed(b) { sawRed = true }; return isBlue(b) })
        #expect(!sawRed)
        registry.closeAll()
    }
}
