// MEDIA-002: how an output gets the frames of the media a scene names. Outputs know ids and layers, never files.
//
// `MediaEngine.MediaRegistry` has exactly this method, so the app adopts the protocol with an empty extension
// (`extension MediaRegistry: MediaFrameSource {}`), the same way it adopts `VideoSourceFactory` for the looping video.
import Foundation
import CoreVideo
import Metal
import Domain

/// Called on an output's render thread for every frame: it must only look up, never open a file or wait on a decoder.
public protocol MediaFrameSource: AnyObject, Sendable {
    /// The newest BGRA frame for `media` in `layer`, or nil when there is none yet.
    func currentPixelBuffer(for media: SceneMedia, layer: MediaLayerSlot) -> CVPixelBuffer?
}

/// The textures for one frame's media layers. Hold it until the GPU has finished with the frame.
struct MediaFrameTextures {
    var background: VideoTexture?
    var foreground: VideoTexture?
    var hold: MediaFrameHold { MediaFrameHold([background?.keepAlive, foreground?.keepAlive].compactMap { $0 }) }
}

/// Keeps a frame's CVMetalTextures alive until a command buffer completes.
// @unchecked Sendable: the objects are only retained here and never read, so passing the hold to the GPU completion
// handler's thread cannot race.
final class MediaFrameHold: @unchecked Sendable {
    private let items: [AnyObject]
    init(_ items: [AnyObject]) { self.items = items }
    var count: Int { items.count }
}

/// One per render thread (it owns a Metal texture cache).
final class MediaFrameResolver {
    private let source: any MediaFrameSource
    private let cache: CVMetalTextureCache

    /// The texture cache keeps every texture it has handed out until it is flushed, which for a long service with
    /// several clips would grow without bound (R14). It is flushed this often; a flush frees only textures nothing
    /// references, so frames still in flight are untouched.
    static let flushInterval = 2.0
    private(set) var flushCount = 0
    private var lastFlush: Double
    private let clock: @Sendable () -> Double

    init(source: any MediaFrameSource, device: MTLDevice, clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) throws {
        self.clock = clock
        self.lastFlush = clock()
        var created: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &created) == kCVReturnSuccess, let created else {
            throw MediaFrameError.noTextureCache
        }
        self.source = source
        self.cache = created
    }

    func resolve(_ scene: SceneDescription) -> MediaFrameTextures {
        let t = clock()
        if t - lastFlush >= Self.flushInterval {
            lastFlush = t
            flushCount += 1
            CVMetalTextureCacheFlush(cache, 0)
        }
        var result = MediaFrameTextures()
        if let media = scene.backgroundMedia { result.background = texture(for: media, layer: .background) }
        if let media = scene.foregroundMedia { result.foreground = texture(for: media, layer: .foreground) }
        return result
    }

    private func texture(for media: SceneMedia, layer: MediaLayerSlot) -> VideoTexture? {
        guard let buffer = source.currentPixelBuffer(for: media, layer: layer),
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
                                                               .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return VideoTexture(texture: texture, keepAlive: cvTexture)
    }
}

enum MediaFrameError: Error, Sendable {
    case noTextureCache
}
