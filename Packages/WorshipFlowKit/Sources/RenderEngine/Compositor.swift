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

    // Image cache (OUT-003). Keyed by path; an entry is reloaded when the file's modification date changes.
    private struct ImageEntry {
        var texture: MTLTexture?        // nil: the file could not be read
        var modified: Date?
        var checkedAt: Double
        var lastUsed: Int
        var bytes: Int
    }
    private var images: [String: ImageEntry] = [:]
    private let loadCenter = ImageLoadCenter()
    private var frameCounter = 0
    private var imageBytes = 0
    /// At most this many images are kept; the least recently used are dropped first.
    static let imageCacheLimit = 64
    static let imageCacheByteLimit = 256 * 1024 * 1024
    private static let modificationRecheckInterval = 1.0
    /// Images currently held in the cache (for tests and diagnostics).
    var cachedImageCount: Int { images.count }
    /// Number of image files decoded so far (for tests and diagnostics).
    public var imageDecodeCount: Int { loadCenter.decodeCount }
    /// Image files that were missing or could not be decoded the last time they were tried. Safe to read from any thread.
    public var unavailableImagePaths: Set<String> { loadCenter.unavailablePaths }

    /// Where image decoding happens when an image is not cached yet.
    public enum ImageLoading: Sendable {
        /// Decode on the calling thread. Offscreen rendering and tests.
        case synchronous
        /// Decode on a background queue and skip the image until it is ready. The live render thread never waits for a decode.
        case background
    }

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

    // Text, images (premultiplied) and video (opaque) are composited with premultiplied "over".
    // `opacity` scales all four premultiplied components, so the result stays premultiplied.
    fragment float4 quad_fragment(VOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler s [[sampler(0)]],
                                  constant float &opacity [[buffer(0)]]) {
        return tex.sample(s, in.uv) * opacity;
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
        try encode(scene: scene, into: texture, video: nil, commandBuffer: cb, imageLoading: .synchronous)
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
    /// Draw order: background colour, video, background image, text, overlay images.
    public func encode(scene: SceneDescription, into texture: MTLTexture, video: MTLTexture? = nil,
                       commandBuffer: MTLCommandBuffer, imageLoading: ImageLoading = .background) throws {
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

        // Resolve image textures too, before the pass starts.
        frameCounter += 1
        drainFinishedImages()
        let backgroundImage = scene.backgroundImage.flatMap { imageDraw($0, width: width, height: height, loading: imageLoading) }
        let overlays = scene.overlayImages.compactMap { imageDraw($0, width: width, height: height, loading: imageLoading) }
        evictImagesIfNeeded()

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
        var fullOpacity: Float = 1
        enc.setFragmentBytes(&fullOpacity, length: MemoryLayout<Float>.stride, index: 0)

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

        if let d = backgroundImage { draw(d, with: enc, target: target) }

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

        if !overlays.isEmpty {
            enc.setScissorRect(MTLScissorRect(x: 0, y: 0, width: width, height: height))   // text drawing left a clip set
            for d in overlays { draw(d, with: enc, target: target) }
        }
        enc.endEncoding()
    }

    // MARK: Images

    private struct ImageDraw {
        let texture: MTLTexture
        let origin: SIMD2<Float>
        let size: SIMD2<Float>
        let uvOrigin: SIMD2<Float>
        let uvSize: SIMD2<Float>
        let opacity: Float
    }

    private func draw(_ d: ImageDraw, with enc: MTLRenderCommandEncoder, target: SIMD2<Float>) {
        var q = QuadUniforms(origin: d.origin, size: d.size, target: target, uvOrigin: d.uvOrigin, uvSize: d.uvSize)
        var opacity = d.opacity
        enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        enc.setFragmentBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
        enc.setFragmentTexture(d.texture, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// Placement of an image layer, or nil when it has nothing to draw (no texture yet, empty frame, zero opacity).
    private func imageDraw(_ layer: ImageLayer, width: Int, height: Int, loading: ImageLoading) -> ImageDraw? {
        guard let texture = imageTexture(layer.path, loading: loading), texture.width > 0, texture.height > 0 else { return nil }
        let opacity = Float(min(1, max(0, layer.opacity)))
        let frame = layer.frame.pixelRect(width: width, height: height)
        guard opacity > 0, frame.width > 0, frame.height > 0 else { return nil }
        let iw = Double(texture.width), ih = Double(texture.height)
        let fw = Double(frame.width), fh = Double(frame.height)
        switch layer.contentMode {
        case .fit:
            let scale = min(fw / iw, fh / ih)
            let w = max(1, (iw * scale).rounded()), h = max(1, (ih * scale).rounded())
            let x = Double(frame.x) + ((fw - w) / 2).rounded(), y = Double(frame.y) + ((fh - h) / 2).rounded()
            return ImageDraw(texture: texture, origin: SIMD2(Float(x), Float(y)), size: SIMD2(Float(w), Float(h)),
                             uvOrigin: .zero, uvSize: SIMD2(1, 1), opacity: opacity)
        case .fill:
            // Cover the frame: crop the source to the frame's aspect ratio.
            let srcAspect = iw / ih, dstAspect = fw / fh
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
            return ImageDraw(texture: texture, origin: SIMD2(Float(frame.x), Float(frame.y)), size: SIMD2(Float(fw), Float(fh)),
                             uvOrigin: uvOrigin, uvSize: uvSize, opacity: opacity)
        }
    }

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    /// The cached texture for `path`, loading or reloading it when needed. Nil while unavailable or not decoded yet.
    private func imageTexture(_ path: String, loading: ImageLoading) -> MTLTexture? {
        let t = now()
        var needsLoad = false
        if var entry = images[path] {
            entry.lastUsed = frameCounter
            if t - entry.checkedAt >= Self.modificationRecheckInterval {
                entry.checkedAt = t
                if ImageDecoder.modificationDate(of: path) != entry.modified { needsLoad = true }
            }
            images[path] = entry
        } else {
            needsLoad = true
        }
        if needsLoad {
            switch loading {
            case .synchronous: install(loadCenter.decodeNow(path))
            case .background: loadCenter.requestInBackground(path)
            }
        }
        return images[path]?.texture
    }

    private func drainFinishedImages() {
        for outcome in loadCenter.takeFinished() { install(outcome) }
    }

    private func install(_ outcome: ImageLoadOutcome) {
        if let old = images[outcome.path] { imageBytes -= old.bytes }
        var texture: MTLTexture?
        var bytes = 0
        if let image = outcome.image {
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: image.width, height: image.height, mipmapped: false)
            td.usage = .shaderRead
            td.storageMode = .shared
            if let tex = device.makeTexture(descriptor: td) {
                image.pixels.withUnsafeBytes { raw in
                    if let base = raw.baseAddress {
                        tex.replace(region: MTLRegionMake2D(0, 0, image.width, image.height), mipmapLevel: 0,
                                    withBytes: base, bytesPerRow: image.width * 4)
                    }
                }
                texture = tex
                bytes = image.width * image.height * 4
            }
        }
        images[outcome.path] = ImageEntry(texture: texture, modified: outcome.modified, checkedAt: now(),
                                          lastUsed: frameCounter, bytes: bytes)
        imageBytes += bytes
    }

    /// Keeps the cache bounded. Images used by the frame being encoded are never dropped.
    private func evictImagesIfNeeded() {
        while images.count > Self.imageCacheLimit || imageBytes > Self.imageCacheByteLimit {
            guard let victim = images.filter({ $0.value.lastUsed != frameCounter }).min(by: { $0.value.lastUsed < $1.value.lastUsed }) else { return }
            imageBytes -= victim.value.bytes
            images[victim.key] = nil
        }
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
