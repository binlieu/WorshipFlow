// UI-007c (SLIDE, OUT): how an output gets the frames of the clips a slide's video objects name: the resolver asks only for them, never for a clip
// the scene does not name, a source that has none gives none, and the whole hand-off reaches the compositor.
import Testing
import Foundation
import CoreVideo
import Metal
import Domain
import RenderEngine
@testable import OutputEngine

final class FakeObjectFrames: MediaFrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [UUID: CVPixelBuffer] = [:]
    private var asked: [UUID] = []
    var requests: [UUID] { lock.lock(); defer { lock.unlock() }; return asked }
    func set(_ id: UUID, _ buffer: CVPixelBuffer?) { lock.lock(); frames[id] = buffer; lock.unlock() }

    func currentPixelBuffer(for media: SceneMedia, layer: MediaLayerSlot) -> CVPixelBuffer? { nil }
    func currentObjectPixelBuffer(for assetID: UUID) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        asked.append(assetID)
        return frames[assetID]
    }
}

@Suite struct UI007c_ObjectFramesTests {
    let device = MTLCreateSystemDefaultDevice()
    private let frame = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

    private func scene(_ ids: [UUID]) -> SceneDescription {
        var s = SceneDescription(backgroundColor: .black, textLayers: [])
        s.objectLayers = ids.map { .video(VideoLayer(mediaID: $0, frame: frame)) }
        return s
    }

    @Test func aSceneWithNoVideoObjectsAsksForNothingAndHoldsNothing() throws {
        let device = try #require(device)
        let frames = FakeObjectFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let r = resolver.resolve(SceneDescription(backgroundColor: .black, textLayers: []))
        #expect(r.objects.isEmpty && r.hold.count == 0 && frames.requests.isEmpty)
    }

    @Test func itAsksForEachClipTheSceneNamesOnceAndKeepsTheFramesItGot() throws {
        let device = try #require(device)
        let frames = FakeObjectFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let a = UUID(), b = UUID(), none = UUID()
        frames.set(a, solidBuffer(width: 8, height: 4, bgra: (0, 255, 0, 255)))
        frames.set(b, solidBuffer(width: 16, height: 9, bgra: (0, 0, 255, 255)))
        let r = resolver.resolve(scene([a, b, none, a]))                     // the same clip twice is one lookup
        #expect(frames.requests == [a, b, none])
        #expect(r.objects[a]?.texture.width == 8 && r.objects[b]?.texture.width == 16 && r.objects[none] == nil)
        #expect(r.hold.count == 2 && r.objectTextures.count == 2)
    }

    @Test func aFrameInAnUnusableFormatIsLeftOut() throws {
        let device = try #require(device)
        let frames = FakeObjectFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let id = UUID()
        frames.set(id, solidBuffer(width: 8, height: 8, bgra: (0, 0, 0, 0), format: kCVPixelFormatType_32ARGB))
        #expect(resolver.resolve(scene([id])).objects.isEmpty)
    }

    @Test func noMoreClipsThanTheLimitAreLookedUpForOneFrame() throws {
        let device = try #require(device)
        let frames = FakeObjectFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let ids = (0..<(MediaFrameResolver.objectVideoLimit + 5)).map { _ in UUID() }
        _ = resolver.resolve(scene(ids))
        #expect(frames.requests == Array(ids.prefix(MediaFrameResolver.objectVideoLimit)))
    }

    @Test func aSourceThatKnowsNoVideoObjectsGivesNoFrames() throws {
        let device = try #require(device)
        let frames = FakeFrames()                                              // the existing fake: it only knows the two layers
        let resolver = try MediaFrameResolver(source: frames, device: device)
        #expect(resolver.resolve(scene([UUID()])).objects.isEmpty)
    }

    /// The whole hand-off: scene ids, frame source, Metal textures, compositor.
    @Test func resolvedClipFramesReachTheCompositorInsideTheirFrame() throws {
        let device = try #require(device)
        let compositor = try Compositor(device: device)
        let frames = FakeObjectFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let id = UUID()
        frames.set(id, solidBuffer(width: 32, height: 16, bgra: (0, 0, 255, 255)))       // red
        let s = scene([id])
        let t = resolver.resolve(s)
        let f = try compositor.renderImage(scene: s, width: 64, height: 64, objectMedia: t.objectTextures)
        let inside = f.pixel(x: 32, y: 32), outside = f.pixel(x: 4, y: 4)
        #expect(inside.red == 255 && inside.green == 0 && inside.blue == 0)
        #expect(outside.red == 0 && outside.green == 0 && outside.blue == 0 && outside.alpha == 255)
    }
}
