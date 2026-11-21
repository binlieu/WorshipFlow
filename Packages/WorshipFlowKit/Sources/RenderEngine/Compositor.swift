// OUT-001: Metal compositor. Shaders are compiled from Swift source strings (ADR-0001).
// Not thread-safe: use one Compositor per render thread.
import Foundation
import Metal
import Domain

public struct RenderedFrame: Sendable {
    public let width: Int
    public let height: Int
    /// Premultiplied BGRA, top row first.
    public let bgra: [UInt8]

    public func pixel(x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard x >= 0, y >= 0, x < width, y < height else { return (0, 0, 0, 0) }
        let i = (y * width + x) * 4
        return (red: bgra[i + 2], green: bgra[i + 1], blue: bgra[i], alpha: bgra[i + 3])
    }
}

public final class Compositor {
    public static let referenceHeight = 1080.0

    public let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelines: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    private let sampler: MTLSamplerState
    private let rasterizer = TextRasterizer()

    private struct TextKey: Hashable {
        let text: String
        let style: TextStyle
        let maxWidth: Int
        let alignment: TextAlignment
    }
    private struct CachedText {
        let texture: MTLTexture
        let width: Int
        let height: Int
    }
    private var textCache: [TextKey: CachedText] = [:]
    private let textCacheLimit = 64
    /// Number of Core Text rasterisations performed (for tests and diagnostics).
    public private(set) var rasterizationCount = 0

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Quad {
        float2 origin;     // pixels, top-left origin
        float2 size;       // pixels
        float2 target;     // target size in pixels
        float2 uvOrigin;
        float2 uvSize;
    };
    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VOut quad_vertex(uint vid [[vertex_id]], constant Quad &q [[buffer(0)]]) {
        float2 c = float2(float(vid & 1), float((vid >> 1) & 1));
        float2 px = q.origin + c * q.size;
        VOut o;
        o.position = float4(px.x / q.target.x * 2.0 - 1.0, 1.0 - px.y / q.target.y * 2.0, 0.0, 1.0);
        o.uv = q.uvOrigin + c * q.uvSize;
        return o;
    }

    // Both text (premultiplied) and video (opaque) textures are composited with premultiplied "over".
    fragment float4 quad_fragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]]) {
        return tex.sample(s, in.uv);
    }
    """

    private struct QuadUniforms {
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
        var target: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
        var uvSize: SIMD2<Float>
    }

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RenderError.resourceCreation("command queue") }
        self.device = device
        self.queue = queue
        do {
            self.library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw RenderError.shaderCompilation("\(error)")
        }
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sd) else { throw RenderError.resourceCreation("sampler") }
        self.sampler = sampler
        _ = try pipeline(for: .bgra8Unorm)   // fail early if the shaders do not link
    }

    private func pipeline(for format: MTLPixelFormat) throws -> MTLRenderPipelineState {
        if let p = pipelines[format] { return p }
        guard let vf = library.makeFunction(name: "quad_vertex"), let ff = library.makeFunction(name: "quad_fragment") else {
            throw RenderError.shaderCompilation("missing shader function")
        }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vf
        d.fragmentFunction = ff
        let a = d.colorAttachments[0]!
        a.pixelFormat = format
        a.isBlendingEnabled = true
        a.rgbBlendOperation = .add
        a.alphaBlendOperation = .add
        a.sourceRGBBlendFactor = .one
        a.sourceAlphaBlendFactor = .one
        a.destinationRGBBlendFactor = .oneMinusSourceAlpha
        a.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            let p = try device.makeRenderPipelineState(descriptor: d)
            pipelines[format] = p
            return p
        } catch {
            throw RenderError.pipeline("\(error)")
        }
    }

    /// A command buffer on the compositor's queue, for the live path.
    public func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    // MARK: Offscreen rendering

    /// Renders to a new offscreen BGRA texture and reads it back. Used by tests and snapshots, not the live path.
    public func renderImage(scene: SceneDescription, width: Int, height: Int) throws -> RenderedFrame {
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td), let cb = queue.makeCommandBuffer() else {
            throw RenderError.resourceCreation("offscreen texture")
        }
        try encode(scene: scene, into: texture, video: nil, commandBuffer: cb)
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw RenderError.pipeline("\(error)") }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                texture.getBytes(base, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            }
        }
        return RenderedFrame(width: width, height: height, bgra: bytes)
    }

    // MARK: Live path

    /// Encodes the scene into `texture` on the caller's command buffer. The caller commits it.
    /// `video`, when supplied and `scene.showsVideo` is true, is drawn aspect-fill over the background colour.
    public func encode(scene: SceneDescription, into texture: MTLTexture, video: MTLTexture? = nil,
                       commandBuffer: MTLCommandBuffer) throws {
        let width = texture.width, height = texture.height
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let pipeline = try pipeline(for: texture.pixelFormat)

        // Resolve text textures before encoding so a rasterisation failure cannot leave a half-built pass.
        struct Placed { let cached: CachedText; let x: Int; let y: Int; let clip: NormalizedRect.PixelRect }
        var placed: [Placed] = []
        let scale = Double(height) / Self.referenceHeight
        for layer in scene.textLayers where !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let frame = layer.frame.pixelRect(width: width, height: height)
            guard frame.width > 8, frame.height > 0 else { continue }
            var scaled = layer.style
            scaled.fontSize *= scale
            scaled.outlineWidth *= scale
            let cached = try cachedText(layer.text, style: scaled, maxWidth: frame.width, alignment: layer.alignment)
            let x: Int
            switch layer.alignment {
            case .leading: x = frame.x
            case .center: x = frame.x + (frame.width - cached.width) / 2
            case .trailing: x = frame.x + frame.width - cached.width
            }
            let y: Int
            switch layer.verticalAlignment {
            case .top: y = frame.y
            case .center: y = frame.y + (frame.height - cached.height) / 2
            case .bottom: y = frame.y + frame.height - cached.height
            }
            placed.append(Placed(cached: cached, x: x, y: y, clip: frame))
        }

        let bg = scene.backgroundColor
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: bg.red * bg.alpha, green: bg.green * bg.alpha,
                                                            blue: bg.blue * bg.alpha, alpha: bg.alpha)
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw RenderError.resourceCreation("render encoder")
        }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentSamplerState(sampler, index: 0)
        let target = SIMD2<Float>(Float(width), Float(height))

        if scene.showsVideo, let video, video.width > 0, video.height > 0 {
            // Aspect-fill: crop the source so it covers the whole target.
            let srcAspect = Double(video.width) / Double(video.height)
            let dstAspect = Double(width) / Double(height)
            var uvOrigin = SIMD2<Float>(0, 0), uvSize = SIMD2<Float>(1, 1)
            if srcAspect > dstAspect {
                let w = Float(dstAspect / srcAspect)
                uvSize.x = w
                uvOrigin.x = (1 - w) / 2
            } else {
                let h = Float(srcAspect / dstAspect)
                uvSize.y = h
                uvOrigin.y = (1 - h) / 2
            }
            var q = QuadUniforms(origin: .zero, size: target, target: target, uvOrigin: uvOrigin, uvSize: uvSize)
            enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(video, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        for p in placed {
            let left = max(0, p.clip.x), top = max(0, p.clip.y)
            let right = min(width, p.clip.x + p.clip.width), bottom = min(height, p.clip.y + p.clip.height)
            guard right > left, bottom > top else { continue }
            enc.setScissorRect(MTLScissorRect(x: left, y: top, width: right - left, height: bottom - top))
            var q = QuadUniforms(origin: SIMD2<Float>(Float(p.x), Float(p.y)),
                                 size: SIMD2<Float>(Float(p.cached.width), Float(p.cached.height)),
                                 target: target, uvOrigin: .zero, uvSize: SIMD2<Float>(1, 1))
            enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(p.cached.texture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        enc.endEncoding()
    }

    // MARK: Text cache

    private func cachedText(_ text: String, style: TextStyle, maxWidth: Int, alignment: TextAlignment) throws -> CachedText {
        let key = TextKey(text: text, style: style, maxWidth: maxWidth, alignment: alignment)
        if let hit = textCache[key] { return hit }
        let raster = try rasterizer.rasterize(text, style: style, maxWidth: maxWidth, alignment: alignment)
        rasterizationCount += 1
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: raster.width, height: raster.height, mipmapped: false)
        td.usage = .shaderRead
        td.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: td) else { throw RenderError.resourceCreation("text texture") }
        raster.pixels.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                tex.replace(region: MTLRegionMake2D(0, 0, raster.width, raster.height), mipmapLevel: 0,
                            withBytes: base, bytesPerRow: raster.width * 4)
            }
        }
        if textCache.count >= textCacheLimit { textCache.removeAll(keepingCapacity: true) }
        let entry = CachedText(texture: tex, width: raster.width, height: raster.height)
        textCache[key] = entry
        return entry
    }
}
