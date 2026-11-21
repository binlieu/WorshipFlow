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
    private let gpu: SharedGPUState
    private let sampler: MTLSamplerState
    private let rasterizer = TextRasterizer()
    /// One opaque black pixel, stretched behind a foreground clip to letterbox it (MEDIA-03).
    private let blackTexture: MTLTexture

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
        var clipped = false
    }
    private var textCache: [TextKey: CachedText] = [:]
    private let textCacheLimit = 64
    /// Number of Core Text rasterisations performed (for tests and diagnostics).
    public private(set) var rasterizationCount = 0

    // Shape cache (SLIDE-001a): one rasterised bitmap per distinct shape, size and colour.
    private struct ShapeKey: Hashable {
        let shape: ShapeObject.Shape
        let fill: ColorRGBA?
        let strokeColor: ColorRGBA?
        let strokeWidth: Int        // hundredths of a pixel
        let width: Int
        let height: Int
    }
    private struct ShapeEntry {
        let texture: MTLTexture
        let bytes: Int
        var lastUsed: Int
    }
    private var shapes: [ShapeKey: ShapeEntry] = [:]
    private var shapeBytes = 0
    /// At most this many shape bitmaps and bytes are kept; the least recently used go first. A shape larger than
    /// `shapeSingleByteLimit` is not drawn (an object frame that large is far off the slide).
    static let shapeCacheLimit = 48
    static let shapeCacheByteLimit = 128 * 1024 * 1024
    static let shapeSingleByteLimit = 64 * 1024 * 1024
    /// Shapes held in the cache (for tests and diagnostics).
    var cachedShapeCount: Int { shapes.count }
    /// Number of shape bitmaps rasterised so far (for tests and diagnostics).
    public private(set) var shapeRasterizationCount = 0

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

    /// One textured rectangle in pixels, with the opacity it is drawn at and an optional clip (lyric and text-box bitmaps
    /// are clipped to their frame).
    private struct QuadDraw {
        let texture: MTLTexture
        let origin: SIMD2<Float>
        let size: SIMD2<Float>
        let uvOrigin: SIMD2<Float>
        let uvSize: SIMD2<Float>
        let opacity: Float
        let clip: NormalizedRect.PixelRect?
    }

    private struct QuadUniforms {
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
        var target: SIMD2<Float>
        var uvOrigin: SIMD2<Float>
        var uvSize: SIMD2<Float>
    }

    /// Shader compilations performed in this process (tests and diagnostics).
    static var shaderCompileCount: Int { SharedGPU.compileCount }

    /// Compiles the shaders and builds the pipeline for the 8-bit BGRA targets outputs use, ahead of time. The app
    /// calls this once at launch from a background task, so that opening screens never compiles on the main thread
    /// (R16). Safe from any thread and to call repeatedly; later compositors reuse the result.
    public static func warmUp(device: MTLDevice? = nil) {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { return }
        _ = try? SharedGPU.state(for: device).pipeline(for: .bgra8Unorm)
    }

    /// Problems found in the most recent frame, de-duplicated and in the order met (R2). A layer that cannot be drawn
    /// is left out of the frame and listed here; the list is empty again as soon as a frame has none. Image files that
    /// cannot be read are reported separately, by `unavailableImagePaths`. Safe to read from any thread.
    public var renderProblems: [String] { problemLock.lock(); defer { problemLock.unlock() }; return publishedProblems }
    private let problemLock = NSLock()
    private var publishedProblems: [String] = []
    private var frameProblems: [String] = []

    private func note(problem: String) {
        if !frameProblems.contains(problem) { frameProblems.append(problem) }
    }

    private static func snippet(_ text: String) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return flat.count > 24 ? String(flat.prefix(24)) + "…" : flat
    }

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else { throw RenderError.noMetalDevice }
        guard let queue = device.makeCommandQueue() else { throw RenderError.resourceCreation("command queue") }
        self.device = device
        self.queue = queue
        self.gpu = try SharedGPU.state(for: device)
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        sd.sAddressMode = .clampToEdge
        sd.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sd) else { throw RenderError.resourceCreation("sampler") }
        self.sampler = sampler
        let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
        bd.usage = .shaderRead
        bd.storageMode = .shared
        guard let black = device.makeTexture(descriptor: bd) else { throw RenderError.resourceCreation("black texture") }
        var opaqueBlack: [UInt8] = [0, 0, 0, 255]
        black.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &opaqueBlack, bytesPerRow: 4)
        self.blackTexture = black
        _ = try pipeline(for: .bgra8Unorm)   // fail early if the shaders do not link
    }

    private func pipeline(for format: MTLPixelFormat) throws -> MTLRenderPipelineState { try gpu.pipeline(for: format) }

    /// A command buffer on the compositor's queue, for the live path.
    public func makeCommandBuffer() -> MTLCommandBuffer? { queue.makeCommandBuffer() }

    // MARK: Offscreen rendering

    /// Renders to a new offscreen BGRA texture and reads it back. Used by tests and snapshots, not the live path.
    /// `video`, `backgroundMedia` and `foregroundMedia` are passed to `encode` as they are (tests use solid-colour textures).
    public func renderImage(scene: SceneDescription, width: Int, height: Int, video: MTLTexture? = nil,
                            backgroundMedia: MTLTexture? = nil, foregroundMedia: MTLTexture? = nil) throws -> RenderedFrame {
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td), let cb = queue.makeCommandBuffer() else {
            throw RenderError.resourceCreation("offscreen texture")
        }
        try encode(scene: scene, into: texture, video: video, commandBuffer: cb, imageLoading: .synchronous,
                   backgroundMedia: backgroundMedia, foregroundMedia: foregroundMedia)
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
    ///
    /// Media (MEDIA-002). `backgroundMedia` is drawn aspect-fill and `foregroundMedia` aspect-fit over black, each only
    /// when the scene names that media (`scene.backgroundMedia`, `scene.foregroundMedia`); a still and a video frame are
    /// both just textures. When the scene names a background media, the shared `video` is not drawn, so a frame that is
    /// not ready yet shows the background colour rather than the theme's loop.
    ///
    /// Draw order: background colour, background media (or the shared video), background image, foreground media,
    /// slide objects back to front, lyric text, overlay images.
    public func encode(scene: SceneDescription, into texture: MTLTexture, video: MTLTexture? = nil,
                       commandBuffer: MTLCommandBuffer, imageLoading: ImageLoading = .background,
                       backgroundMedia: MTLTexture? = nil, foregroundMedia: MTLTexture? = nil) throws {
        let width = texture.width, height = texture.height
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let pipeline = try pipeline(for: texture.pixelFormat)
        frameProblems.removeAll(keepingCapacity: true)
        defer {
            problemLock.lock(); publishedProblems = frameProblems; problemLock.unlock()
        }

        // Resolve text textures before encoding. A layer that cannot be drawn is skipped and reported: it never
        // keeps the rest of the scene from presenting (R2).
        var placed: [QuadDraw] = []
        for layer in scene.textLayers {
            if let draw = safeTextDraw(layer, width: width, height: height) { placed.append(draw) }
        }

        // Resolve image textures too, before the pass starts.
        frameCounter += 1
        drainFinishedImages()
        let backgroundImage = scene.backgroundImage.flatMap { imageDraw($0, width: width, height: height, loading: imageLoading) }
        let overlays = scene.overlayImages.compactMap { imageDraw($0, width: width, height: height, loading: imageLoading) }
        // Slide objects, back to front (SLIDE-001a).
        var objects: [QuadDraw] = []
        for layer in scene.objectLayers {
            switch layer {
            case .shape(let shape):
                if let draw = shapeDraw(shape, width: width, height: height) { objects.append(draw) }
            case .text(let text):
                if let draw = safeTextDraw(text, width: width, height: height) { objects.append(draw) }
            case .image(let image):
                if let d = imageDraw(image, width: width, height: height, loading: imageLoading) {
                    objects.append(QuadDraw(texture: d.texture, origin: d.origin, size: d.size, uvOrigin: d.uvOrigin,
                                            uvSize: d.uvSize, opacity: d.opacity, clip: nil))
                }
            }
        }
        evictImagesIfNeeded()
        evictShapesIfNeeded()

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

        // The shared video yields to a media background chosen in the scene.
        let backdrop: MTLTexture? = scene.backgroundMedia != nil ? backgroundMedia : (scene.showsVideo ? video : nil)
        if let backdrop, backdrop.width > 0, backdrop.height > 0 {
            let uv = Self.fillUV(sourceWidth: Double(backdrop.width), sourceHeight: Double(backdrop.height),
                                 width: Double(width), height: Double(height))
            var q = QuadUniforms(origin: .zero, size: target, target: target, uvOrigin: uv.origin, uvSize: uv.size)
            enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(backdrop, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        if let d = backgroundImage { draw(d, with: enc, target: target) }

        if scene.foregroundMedia != nil, let fg = foregroundMedia, fg.width > 0, fg.height > 0 {
            // Black first, so the bars around a clip are black whatever is underneath (and opaque on a keyed output).
            var full = QuadUniforms(origin: .zero, size: target, target: target, uvOrigin: .zero, uvSize: SIMD2<Float>(1, 1))
            enc.setVertexBytes(&full, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(blackTexture, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            // Aspect-fit, centred, on whole pixels.
            let scale = min(Double(width) / Double(fg.width), Double(height) / Double(fg.height))
            let w = max(1, (Double(fg.width) * scale).rounded()), h = max(1, (Double(fg.height) * scale).rounded())
            let x = ((Double(width) - w) / 2).rounded(), y = ((Double(height) - h) / 2).rounded()
            var q = QuadUniforms(origin: SIMD2<Float>(Float(x), Float(y)), size: SIMD2<Float>(Float(w), Float(h)),
                                 target: target, uvOrigin: .zero, uvSize: SIMD2<Float>(1, 1))
            enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(fg, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Objects, then lyric text. Each draw sets its own clip and opacity.
        for q in objects + placed { draw(q, with: enc, target: target, width: width, height: height) }

        if !overlays.isEmpty {
            enc.setScissorRect(MTLScissorRect(x: 0, y: 0, width: width, height: height))   // text drawing left a clip set
            for d in overlays { draw(d, with: enc, target: target) }
        }
        enc.endEncoding()
    }

    /// Texture coordinates that crop a source of the given size to cover a destination of the given size.
    static func fillUV(sourceWidth: Double, sourceHeight: Double, width: Double, height: Double) -> (origin: SIMD2<Float>, size: SIMD2<Float>) {
        let srcAspect = sourceWidth / sourceHeight, dstAspect = width / height
        var origin = SIMD2<Float>(0, 0), size = SIMD2<Float>(1, 1)
        if srcAspect > dstAspect {
            let w = Float(dstAspect / srcAspect)
            size.x = w
            origin.x = (1 - w) / 2
        } else {
            let h = Float(srcAspect / dstAspect)
            size.y = h
            origin.y = (1 - h) / 2
        }
        return (origin, size)
    }

    // MARK: Text and shape draws

    private func draw(_ q: QuadDraw, with enc: MTLRenderCommandEncoder, target: SIMD2<Float>, width: Int, height: Int) {
        var left = 0, top = 0, right = width, bottom = height
        if let clip = q.clip {
            left = max(0, clip.x); top = max(0, clip.y)
            right = min(width, clip.x + clip.width); bottom = min(height, clip.y + clip.height)
        }
        guard right > left, bottom > top else { return }
        enc.setScissorRect(MTLScissorRect(x: left, y: top, width: right - left, height: bottom - top))
        var uniforms = QuadUniforms(origin: q.origin, size: q.size, target: target, uvOrigin: q.uvOrigin, uvSize: q.uvSize)
        var opacity = q.opacity
        enc.setVertexBytes(&uniforms, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        enc.setFragmentBytes(&opacity, length: MemoryLayout<Float>.stride, index: 0)
        enc.setFragmentTexture(q.texture, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    /// `textDraw`, with a failure turned into a skipped layer and a reported problem.
    private func safeTextDraw(_ layer: TextLayer, width: Int, height: Int) -> QuadDraw? {
        do {
            return try textDraw(layer, width: width, height: height)
        } catch {
            note(problem: "Text layer skipped (\"\(Self.snippet(layer.text))\"): \(error)")
            return nil
        }
    }

    /// Rasterises (or fetches) a text layer and places it in its frame. Nil when there is nothing to draw.
    private func textDraw(_ layer: TextLayer, width: Int, height: Int) throws -> QuadDraw? {
        guard !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let frame = layer.frame.pixelRect(width: width, height: height)
        guard frame.width > 8, frame.height > 0 else { return nil }
        let opacity = Float(min(1, max(0, layer.opacity)))
        guard opacity > 0 else { return nil }
        let scale = Double(height) / Self.referenceHeight
        var scaled = layer.style
        scaled.fontSize *= scale
        scaled.outlineWidth *= scale
        if var shadow = scaled.shadow {
            shadow.offsetX *= scale
            shadow.offsetY *= scale
            shadow.blur *= scale
            scaled.shadow = shadow
        }
        let cached = try cachedText(layer.text, style: scaled, maxWidth: frame.width, alignment: layer.alignment)
        if cached.clipped { note(problem: "Text taller than the limit was clipped (\"\(Self.snippet(layer.text))\")") }
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
        return QuadDraw(texture: cached.texture, origin: SIMD2(Float(x), Float(y)),
                        size: SIMD2(Float(cached.width), Float(cached.height)), uvOrigin: .zero, uvSize: SIMD2(1, 1),
                        opacity: opacity, clip: frame)
    }

    /// The shape's bitmap placed on its frame. Nil when it draws nothing or fails to rasterise.
    private func shapeDraw(_ layer: ShapeLayer, width: Int, height: Int) -> QuadDraw? {
        let opacity = Float(min(1, max(0, layer.opacity)))
        let frame = layer.frame.pixelRect(width: width, height: height)
        guard opacity > 0, frame.width > 0, frame.height > 0, frame.width * frame.height * 4 <= Self.shapeSingleByteLimit else { return nil }
        let hasFill = (layer.fill?.alpha ?? 0) > 0
        let strokePixels = layer.strokeWidth * Double(height) / Self.referenceHeight
        let hasStroke = (layer.strokeColor?.alpha ?? 0) > 0 && strokePixels > 0
        guard hasFill || hasStroke else { return nil }
        let key = ShapeKey(shape: layer.shape, fill: hasFill ? layer.fill : nil, strokeColor: hasStroke ? layer.strokeColor : nil,
                           strokeWidth: hasStroke ? Int((strokePixels * 100).rounded()) : 0, width: frame.width, height: frame.height)
        let texture: MTLTexture
        if var hit = shapes[key] {
            hit.lastUsed = frameCounter
            shapes[key] = hit
            texture = hit.texture
        } else {
            guard let pixels = ShapeRasterizer.rasterize(shape: key.shape, fill: key.fill, strokeColor: key.strokeColor,
                                                         strokeWidth: Double(key.strokeWidth) / 100,
                                                         width: key.width, height: key.height) else {
                note(problem: "A shape could not be drawn (\(key.width)x\(key.height) px)")
                return nil
            }
            let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: key.width, height: key.height, mipmapped: false)
            td.usage = .shaderRead
            td.storageMode = .shared
            guard let tex = device.makeTexture(descriptor: td) else {
                note(problem: "A shape could not be drawn (no texture for \(key.width)x\(key.height) px)")
                return nil
            }
            pixels.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    tex.replace(region: MTLRegionMake2D(0, 0, key.width, key.height), mipmapLevel: 0, withBytes: base, bytesPerRow: key.width * 4)
                }
            }
            shapeRasterizationCount += 1
            shapes[key] = ShapeEntry(texture: tex, bytes: pixels.count, lastUsed: frameCounter)
            shapeBytes += pixels.count
            texture = tex
        }
        return QuadDraw(texture: texture, origin: SIMD2(Float(frame.x), Float(frame.y)),
                        size: SIMD2(Float(frame.width), Float(frame.height)), uvOrigin: .zero, uvSize: SIMD2(1, 1),
                        opacity: opacity, clip: nil)
    }

    /// Keeps the shape cache bounded. Shapes used by the frame being encoded are never dropped.
    private func evictShapesIfNeeded() {
        while shapes.count > Self.shapeCacheLimit || shapeBytes > Self.shapeCacheByteLimit {
            guard let victim = shapes.filter({ $0.value.lastUsed != frameCounter }).min(by: { $0.value.lastUsed < $1.value.lastUsed }) else { return }
            shapeBytes -= victim.value.bytes
            shapes[victim.key] = nil
        }
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
    ///
    /// In `.background` mode this never touches the file system (R7): a cached image is re-checked by asking the loader
    /// once a second, and the loader does the `stat` on its own thread. An image another screen has already decoded is
    /// taken from the shared store at once (R10), so it is in the very first frame.
    private func imageTexture(_ path: String, loading: ImageLoading) -> MTLTexture? {
        let t = now()
        if var entry = images[path] {
            entry.lastUsed = frameCounter
            if t - entry.checkedAt >= Self.modificationRecheckInterval {
                entry.checkedAt = t
                switch loading {
                case .synchronous:
                    // Offscreen rendering is not a live render thread: it may ask the file system itself.
                    if ImageDecoder.modificationDate(of: path) != entry.modified {
                        images[path] = entry
                        install(loadCenter.decodeNow(path))
                        return images[path]?.texture
                    }
                case .background:
                    loadCenter.requestInBackground(path, since: entry.texture == nil ? nil : entry.modified)
                }
            }
            images[path] = entry
        } else {
            switch loading {
            case .synchronous: install(loadCenter.decodeNow(path))
            case .background:
                if let shared = loadCenter.cachedOutcome(path) { install(shared) } else { loadCenter.requestInBackground(path) }
            }
        }
        return images[path]?.texture
    }

    /// Decodes (or takes from the shared store) every image `scene` draws and uploads it into this compositor, so the
    /// first frame that shows the scene already has them (R10). Reads the file system and decodes on the calling thread:
    /// call it from a background queue that owns this compositor, never from a render thread. Returns the image files
    /// that could not be read.
    @discardableResult
    public func prepare(scene: SceneDescription) -> Set<String> {
        frameCounter += 1
        var missing: Set<String> = []
        for path in scene.imagePaths {
            if images[path]?.texture == nil { install(loadCenter.decodeNow(path)) }
            if images[path]?.texture == nil { missing.insert(path) }
        }
        evictImagesIfNeeded()
        return missing
    }

    private func drainFinishedImages() {
        for outcome in loadCenter.takeFinished() { install(outcome) }
    }

    private func install(_ outcome: ImageLoadOutcome) {
        if outcome.unchanged {
            // Re-checked and still current: nothing to upload.
            if var entry = images[outcome.path] { entry.checkedAt = now(); images[outcome.path] = entry }
            return
        }
        if outcome.image == nil, var old = images[outcome.path], old.texture != nil {
            // A reload that failed (a momentary read error, a half-written file): keep what is on screen. The loader
            // has reported the path as unavailable; the old modification date stays so the next check tries again.
            old.checkedAt = now()
            old.lastUsed = frameCounter
            images[outcome.path] = old
            return
        }
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
        let entry = CachedText(texture: tex, width: raster.width, height: raster.height, clipped: raster.clipped)
        textCache[key] = entry
        return entry
    }
}
