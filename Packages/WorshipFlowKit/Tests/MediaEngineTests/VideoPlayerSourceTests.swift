// MEDIA-02 / MEDIA-03: the transport-driven player and the registry. Real AVFoundation decoding of tiny movies; no
// window, no audio (the movies have no sound track and the players are muted).
import Testing
import Foundation
import CoreVideo
import Domain
@testable import MediaEngine

/// Counts calls from any thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func bump() { lock.lock(); n += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// A movie that is red for the first second and blue for the second.
func redThenBlue(in dir: URL) async throws -> URL {
    let url = dir.appendingPathComponent("rb-\(UUID().uuidString).mov")
    try await TestMedia.writeMovie(to: url, segments: [(1, TestMedia.red), (1, TestMedia.blue)])
    return url
}

func isRed(_ b: CVPixelBuffer?) -> Bool { b.flatMap(TestMedia.centre(of:)).map { $0.r > 150 && $0.b < 110 } ?? false }
func isBlue(_ b: CVPixelBuffer?) -> Bool { b.flatMap(TestMedia.centre(of:)).map { $0.b > 150 && $0.r < 110 } ?? false }

@Suite(.serialized) struct VideoPlayerSourceTests {
    @Test func missingFileThrows() {
        #expect(throws: MediaError.self) { try VideoPlayerSource(url: URL(fileURLWithPath: "/nonexistent/clip.mov"), loops: false) }
    }

    @Test func playingDeliversFramesAndPositionAdvances() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        #expect(source.status() == .idle)
        source.play()
        #expect(source.status() == .playing)
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })
        #expect(source.deliveredFrameCount > 0)
        source.stop()
        #expect(source.status() == .idle && source.position() == 0)
    }

    @Test func pauseHoldsAndSeekMovesTheFrame() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        source.play()
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })
        source.pause()
        let held = source.position()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(source.status() == .paused && source.position() == held)
        // Seeking while paused stays paused and shows the frame at the new position.
        source.seek(to: 1.6)
        #expect(source.status() == .paused && abs(source.position() - 1.6) < 1e-9)
        #expect(await TestMedia.wait { isBlue(source.latestPixelBuffer()) })
        source.seek(to: 0.2)
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })
    }

    @Test func aClipThatDoesNotLoopReportsItsEnd() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        let ended = Counter()
        source.setOnEnded { ended.bump() }
        source.seek(to: 1.5)
        source.play()
        // An output pulls frames continuously while it runs; do the same, since the decoder is paced by its consumer.
        #expect(await TestMedia.wait { _ = source.latestPixelBuffer(); return source.status() == .ended })
        #expect(await TestMedia.wait { _ = source.latestPixelBuffer(); return ended.value >= 1 }, "ended count \(ended.value) \(source.diagnostics)")
        #expect(ended.value == 1)
        #expect(isBlue(source.latestPixelBuffer()))           // the last frame stays up
        // Playing again after the end starts from the beginning.
        source.play()
        #expect(source.status() == .playing)
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })
    }

    @Test func aLoopingSourceWrapsAndNeverEnds() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: true, duration: 2)
        let ended = Counter()
        source.setOnEnded { ended.bump() }
        source.seek(to: 1.7)
        source.play()
        try await Task.sleep(nanoseconds: 800_000_000)         // past the loop point
        #expect(source.status() == .playing && ended.value == 0)
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })   // wrapped back to the red half
    }

    @Test func appliesAnExternalTransport() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        var t = MediaTransport(duration: 2, loops: false)
        t.seek(to: 1.4, at: 100)
        source.apply(t, at: 100)
        #expect(source.currentTransport == t && source.status(at: 100) == .idle)
        t.play(at: 100)
        source.apply(t, at: 100)
        #expect(source.status(at: 100) == .playing)
        #expect(await TestMedia.wait { isBlue(source.latestPixelBuffer()) })
        source.apply(t, at: 100)                                // applying the same state again changes nothing
        #expect(source.currentTransport == t)
    }
}

@Suite(.serialized) struct MediaRegistryTests {
    @Test func resolvesAVideoBackgroundAndAnImageForeground() async throws {
        let dir = try TestMedia.tempDirectory()
        let movie = try await redThenBlue(in: dir)
        let png = dir.appendingPathComponent("green.png")
        try TestMedia.writePNG(to: png, width: 40, height: 30, red: 0, green: 255, blue: 0)
        let registry = MediaRegistry()
        let loopID = UUID(), stillID = UUID()
        registry.register(id: loopID, kind: .video, url: movie, duration: 2)
        registry.register(id: stillID, kind: .image, url: png)

        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: loopID, kind: .video, duration: 2), at: 0)
        layers.startForeground(MediaSelection(assetID: stillID, kind: .image, duration: nil), at: 0)
        registry.apply(layers, at: 0)

        #expect(await TestMedia.wait { isRed(registry.currentPixelBuffer(for: .video(loopID), layer: .background)) })
        #expect(await TestMedia.wait { registry.currentPixelBuffer(for: .image(stillID), layer: .foreground) != nil })
        let still = registry.currentPixelBuffer(for: .image(stillID), layer: .foreground)
        #expect(still.flatMap(TestMedia.centre(of:)).map { $0.g > 240 && $0.r < 10 } == true)
        #expect(still.map { (CVPixelBufferGetWidth($0), CVPixelBufferGetHeight($0)) }! == (40, 30))
        // Asking for another id, or the wrong layer, gives nothing and opens nothing.
        #expect(registry.currentPixelBuffer(for: .video(UUID()), layer: .background) == nil)
        #expect(registry.currentPixelBuffer(for: .video(loopID), layer: .foreground) == nil)
        #expect(registry.unavailableAssetIDs.isEmpty)
    }

    @Test func clearingALayerClosesItsSource() async throws {
        let dir = try TestMedia.tempDirectory()
        let movie = try await redThenBlue(in: dir)
        let registry = MediaRegistry()
        let id = UUID()
        registry.register(id: id, kind: .video, url: movie, duration: 2)
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: id, kind: .video, duration: 2), at: 0)
        registry.apply(layers, at: 0)
        #expect(registry.videoSource(in: .foreground) != nil)
        layers.stopForeground()
        registry.apply(layers, at: 1)
        #expect(registry.videoSource(in: .foreground) == nil)
        #expect(registry.currentPixelBuffer(for: .video(id), layer: .foreground) == nil)
    }

    @Test func unknownOrMissingMediaIsReportedNotFatal() async throws {
        let registry = MediaRegistry()
        let unknown = UUID(), gone = UUID()
        registry.register(id: gone, kind: .video, url: URL(fileURLWithPath: "/nonexistent/x.mov"))
        var layers = MediaLayers()
        layers.setBackground(MediaSelection(assetID: unknown, kind: .video, duration: 5), at: 0)
        layers.startForeground(MediaSelection(assetID: gone, kind: .video, duration: 5), at: 0)
        registry.apply(layers, at: 0)
        #expect(registry.unavailableAssetIDs == [unknown, gone])
        #expect(registry.currentPixelBuffer(for: .video(gone), layer: .foreground) == nil)
        // An unreadable picture is reported once decoding fails.
        let bad = UUID()
        let dir = try TestMedia.tempDirectory()
        let junk = dir.appendingPathComponent("junk.png")
        try "nope".write(to: junk, atomically: true, encoding: .utf8)
        registry.register(id: bad, kind: .image, url: junk)
        layers.setBackground(MediaSelection(assetID: bad, kind: .image, duration: nil), at: 0)
        registry.apply(layers, at: 0)
        #expect(await TestMedia.wait { registry.unavailableAssetIDs.contains(bad) })
    }

    @Test func stillCacheIsBounded() async throws {
        let dir = try TestMedia.tempDirectory()
        let registry = MediaRegistry(stillLimit: 3)
        var layers = MediaLayers()
        for i in 0..<6 {
            let id = UUID(), png = dir.appendingPathComponent("s\(i).png")
            try TestMedia.writePNG(to: png, width: 8, height: 8, red: UInt8(i * 40), green: 0, blue: 0)
            registry.register(id: id, kind: .image, url: png)
            layers.setBackground(MediaSelection(assetID: id, kind: .image, duration: nil), at: 0)
            registry.apply(layers, at: 0)
            #expect(await TestMedia.wait { registry.currentPixelBuffer(for: .image(id), layer: .background) != nil })
        }
        registry.apply(layers, at: 0)
        #expect(registry.decodedStillCount <= 3)
    }

    @Test func aForegroundClipEndsThroughTheRegistry() async throws {
        let dir = try TestMedia.tempDirectory()
        let movie = try await redThenBlue(in: dir)
        let registry = MediaRegistry()
        let id = UUID()
        registry.register(id: id, kind: .video, url: movie, duration: 2)
        let ended = Counter()
        registry.setOnForegroundEnded { ended.bump() }
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: id, kind: .video, duration: 2), at: MediaClock.now())
        layers.seekForeground(to: 1.5, at: MediaClock.now())
        registry.apply(layers)
        #expect(await TestMedia.wait { ended.value == 1 })
    }
}
