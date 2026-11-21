// OUT-001: adapts MediaEngine's looping source to OutputEngine's texture hand-off protocol.
import Foundation
import Metal
import CoreVideo
import MediaEngine
import OutputEngine

extension LoopingVideoSource: @retroactive VideoSourceFactory {
    public func makeTextureProvider(device: MTLDevice) throws -> any VideoTextureProvider {
        try LoopingTextureProvider(source: self, device: device)
    }
}

/// One per render thread: owns a CVMetalTextureCache and converts the newest decoded frame to a texture.
final class LoopingTextureProvider: VideoTextureProvider {
    private let source: LoopingVideoSource
    private let converter: VideoTextureConverter
    private var lastBuffer: CVPixelBuffer?
    private var lastFrame: VideoTexture?
    private var count = 0

    init(source: LoopingVideoSource, device: MTLDevice) throws {
        self.source = source
        self.converter = try VideoTextureConverter(device: device)
    }

    func currentTexture() -> VideoTexture? {
        guard let buffer = source.latestPixelBuffer() else { return lastFrame }
        if let lastBuffer, lastBuffer === buffer, let lastFrame { return lastFrame }
        guard let frame = converter.texture(from: buffer) else { return lastFrame }
        let vt = VideoTexture(texture: frame.texture, keepAlive: frame.keepAlive as AnyObject)
        lastBuffer = buffer
        lastFrame = vt
        count += 1
        if count % 120 == 0 { converter.flush() }
        return vt
    }
}
