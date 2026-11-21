// MEDIA-002: how outputs turn a scene's media ids into textures. No window; a fake frame source and the GPU.
import Testing
import Foundation
import CoreVideo
import Metal
import Domain
import RenderEngine
@testable import OutputEngine

final class FakeFrames: MediaFrameSource, @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String: CVPixelBuffer] = [:]
    private var asked: [String] = []
    var requests: [String] { lock.lock(); defer { lock.unlock() }; return asked }

    func set(_ media: SceneMedia, _ layer: MediaLayerSlot, _ buffer: CVPixelBuffer?) {
        lock.lock(); frames[key(media, layer)] = buffer; lock.unlock()
    }
    private func key(_ media: SceneMedia, _ layer: MediaLayerSlot) -> String { "\(media)-\(layer)" }

    func currentPixelBuffer(for media: SceneMedia, layer: MediaLayerSlot) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        asked.append(key(media, layer))
        return frames[key(media, layer)]
    }
}

func solidBuffer(width: Int, height: Int, bgra: (UInt8, UInt8, UInt8, UInt8), format: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
    let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
    var out: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, width, height, format, attrs as CFDictionary, &out) == kCVReturnSuccess, let buffer = out else { return nil }
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer), format == kCVPixelFormatType_32BGRA else { return buffer }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width { row[x * 4] = bgra.0; row[x * 4 + 1] = bgra.1; row[x * 4 + 2] = bgra.2; row[x * 4 + 3] = bgra.3 }
    }
    return buffer
}

@Suite struct MediaFrameResolverTests {
    let device = MTLCreateSystemDefaultDevice()

    @Test func asksOnlyForWhatTheSceneNames() throws {
        let device = try #require(device)
        let frames = FakeFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let empty = resolver.resolve(SceneDescription(backgroundColor: .black, textLayers: []))
        #expect(empty.background == nil && empty.foreground == nil && frames.requests.isEmpty)

        let bg = UUID(), fg = UUID()
        frames.set(.video(bg), .background, solidBuffer(width: 8, height: 4, bgra: (0, 255, 0, 255)))
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.backgroundMedia = .video(bg)
        scene.foregroundMedia = .image(fg)                      // no frame for it yet
        let r = resolver.resolve(scene)
        #expect(r.background?.texture.width == 8 && r.background?.texture.height == 4)
        #expect(r.foreground == nil)
        #expect(frames.requests == ["video(\(bg))-background", "image(\(fg))-foreground"])
        #expect(r.hold.count == 1)
    }

    @Test func ignoresFramesInAnUnusableFormat() throws {
        let device = try #require(device)
        let frames = FakeFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let id = UUID()
        frames.set(.video(id), .foreground, solidBuffer(width: 8, height: 8, bgra: (0, 0, 0, 0), format: kCVPixelFormatType_32ARGB))
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.foregroundMedia = .video(id)
        #expect(resolver.resolve(scene).foreground == nil)
    }

    /// The whole hand-off: scene ids, frame source, Metal textures, compositor.
    @Test func resolvedTexturesReachTheCompositor() throws {
        let device = try #require(device)
        let compositor = try Compositor(device: device)
        let frames = FakeFrames()
        let resolver = try MediaFrameResolver(source: frames, device: device)
        let bg = UUID(), fg = UUID()
        frames.set(.image(bg), .background, solidBuffer(width: 16, height: 16, bgra: (0, 255, 0, 255)))     // green (B, G, R, A)
        frames.set(.video(fg), .foreground, solidBuffer(width: 32, height: 16, bgra: (0, 0, 255, 255)))     // red
        var scene = SceneDescription(backgroundColor: .black, textLayers: [])
        scene.backgroundMedia = .image(bg)
        scene.foregroundMedia = .video(fg)
        let t = resolver.resolve(scene)
        let f = try compositor.renderImage(scene: scene, width: 64, height: 64, backgroundMedia: t.background?.texture,
                                           foregroundMedia: t.foreground?.texture)
        let middle = f.pixel(x: 32, y: 32), bar = f.pixel(x: 32, y: 4)
        #expect(middle.red == 255 && middle.green == 0 && middle.blue == 0)     // the clip, red
        #expect(bar.red == 0 && bar.green == 0 && bar.blue == 0 && bar.alpha == 255)   // letterbox, black over the green background
    }
}
