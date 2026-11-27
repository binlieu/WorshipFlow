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

    private struct CachedText {
        let texture: MTLTexture
        let width: Int
        let height: Int
        var clipped = false
        // UI-005h: the text block's line boxes inside the bitmap, and how many lines there are.
        var lineBoxLeft = 0.0
        var lineBoxTop = 0.0
        var blockWidth = 0.0
        var blockHeight = 0.0
        var lineCount = 0
        /// Pixels with ink, bitmap coordinates (empty when there is none).
        var ink = CGRect.zero
    }
    /// FIX-J item 2: the lyrics' bitmaps, and (apart) those of text that changes every second. Each gives up its least recently used entry one
    /// at a time, so a full cache never loses the whole slide, and a ticking clock never pushes a lyric out.
    private var lyricCache = LRUCache<TextRasterKey, CachedText>(limit: Compositor.lyricCacheLimit)
    private var tickingCache = LRUCache<TextRasterKey, CachedText>(limit: Compositor.tickingCacheLimit)
    static let lyricCacheLimit = 64
    static let tickingCacheLimit = 16
    /// Entries in the lyric cache and in the ticking-text cache (for tests and diagnostics).
    var textCacheCount: Int { lyricCache.count }
    var tickingCacheCount: Int { tickingCache.count }
    /// Set by `TextWarmer`: bitmaps and fit decisions made here are also put in the shared store for the outputs' compositors.
    var publishesRasters = false
    /// Number of Core Text rasterisations performed (for tests and diagnostics).
    public private(set) var rasterizationCount = 0

    // FIX-J item 1: fitting. One status per slide's words, theme blocks and aspect, computed on the first frame that needs it.
    private var fitCache = LRUCache<FitKey, TextFitStatus>(limit: 128)
    private var lastFit: (layers: [TextLayer], plate: TextPlate?, width: Int, height: Int, status: TextFitStatus)?
    /// Fitting computations made so far (for tests and diagnostics): one per distinct slide and theme, never one per frame.
    public private(set) var fitComputationCount = 0

    // UI-005h: gradient backgrounds (one frame-sized bitmap per gradient and output size) and plates (one per size, radius, colours and bar).
    // Both are built on the first frame that needs them and reused; `looksCacheLimit` of each are kept.
    private struct GradientKey: Hashable {
        let gradient: GradientBackground
        let width: Int
        let height: Int
    }
    private struct PlateKey: Hashable {
        let width: Int
        let height: Int
        let radius: Int           // hundredths of a pixel
        let fill: ColorRGBA
        let barX: Int, barY: Int, barWidth: Int, barHeight: Int
        let barTop: ColorRGBA, barBottom: ColorRGBA
    }
    private var gradients: [GradientKey: MTLTexture] = [:]
    private var plates: [PlateKey: MTLTexture] = [:]
    private let looksCacheLimit = 8
    /// Gradient and plate bitmaps rasterised so far (for tests and diagnostics).
    public private(set) var looksRasterizationCount = 0

    // Shape cache (SLIDE-001a): one rasterised bitmap per distinct shape, size and colour.
    struct ShapeKey: Hashable {
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

    // MARK: Fitting (FIX-J)

    /// What fitting decides for `scene`'s text at an output of `width` x `height`: the factor and whether the words fit. The measure is made at
    /// the reference size, so every output size of one slide gives the same answer. Computed once per slide and theme and kept; a scene whose
    /// text has no fit floor is `.unchanged`.
    public func fitStatus(scene: SceneDescription, width: Int, height: Int) throws -> TextFitStatus {
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        // The frame loop asks every frame: no allocation unless the words changed (an array compare, and the answer of the frame before).
        guard scene.textLayers.contains(where: { $0.fitFloor != nil }) else { return .unchanged }
        if let last = lastFit, last.width == width, last.height == height, last.plate == scene.plate, last.layers == scene.textLayers { return last.status }
        let platePresent = scene.plate != nil
        let group = TextFitter.group(scene.textLayers)
        guard !group.isEmpty else { return .unchanged }
        let refW = TextFitter.referenceWidth(width: width, height: height)
        let key = FitKey(layers: group.map { FitLayerKey(text: $0.text, style: $0.style, frame: $0.frame, alignment: $0.alignment,
                                                          inPlate: platePresent && $0.inPlate, floor: $0.fitFloor ?? 0) },
                         plate: scene.plate, referenceWidth: refW)
        func remember(_ status: TextFitStatus) -> TextFitStatus {
            lastFit = (scene.textLayers, scene.plate, width, height, status)
            return status
        }
        if let hit = fitCache.value(for: key) { return remember(hit) }
        if let shared = SharedTextStore.shared.fit(for: key) {      // prepared ahead of Go Live
            fitCache.insert(shared, for: key)
            return remember(shared)
        }
        let status = TextFitter.status(layers: group.map { var l = $0; l.inPlate = platePresent && l.inPlate; return l }, plate: scene.plate,
                                       referenceWidth: refW, rasterizer: rasterizer)
        fitComputationCount += 1
        fitCache.insert(status, for: key)
        if publishesRasters { SharedTextStore.shared.put(status, for: key) }
        return remember(status)
    }

    /// UI-007c: the fit of one text object, which has its own factor (a text box shrinks alone, not with the lyrics). The same measure and the same floor
    /// as the lyrics' fit; computed once per words, style, frame and output shape and kept.
    private func objectFitStatus(_ layer: TextLayer, width: Int, height: Int) -> TextFitStatus {
        guard let floor = layer.fitFloor else { return .unchanged }
        // OUT-002f: the frame loop asks every frame. A box seen on the frame before, unchanged and at the same size, gets its answer with no key and no
        // hash: a compare of the layer (the same compare the lyric path makes) and no allocation.
        for last in lastObjectFits where last.width == width && last.height == height && last.layer == layer { return last.status }
        let refW = TextFitter.referenceWidth(width: width, height: height)
        objectFitKeyBuildCount += 1
        let key = FitKey(layers: [FitLayerKey(text: layer.text, style: layer.style, frame: layer.frame, alignment: layer.alignment, inPlate: false, floor: floor)],
                         plate: nil, referenceWidth: refW)
        func remember(_ status: TextFitStatus) -> TextFitStatus {
            if lastObjectFits.count >= Self.lastObjectFitLimit { lastObjectFits.removeFirst() }
            lastObjectFits.append((layer, width, height, status))
            return status
        }
        if let hit = fitCache.value(for: key) { return remember(hit) }
        if let shared = SharedTextStore.shared.fit(for: key) {      // OUT-002f: prepared ahead of Go Live (the gate's warmer, or the Preview warm)
            fitCache.insert(shared, for: key)
            return remember(shared)
        }
        let status = TextFitter.status(layers: [layer], plate: nil, referenceWidth: refW, rasterizer: rasterizer)
        objectFitComputationCount += 1
        fitCache.insert(status, for: key)
        if publishesRasters { SharedTextStore.shared.put(status, for: key) }
        return remember(status)
    }

    /// OUT-002f: the text boxes with a fit floor drawn on the last frames, each with its answer; at most `lastObjectFitLimit`, oldest first out.
    private var lastObjectFits: [(layer: TextLayer, width: Int, height: Int, status: TextFitStatus)] = []
    private static let lastObjectFitLimit = 16

    /// OUT-002f: forgets what this compositor kept of text, fits and shapes, so a warm that follows finds nothing here and publishes it all to the
    /// shared stores. Used by the warmer's one long-lived compositor (an output's own compositor never calls it).
    func resetPreparedCaches() {
        lyricCache.removeAll()
        tickingCache.removeAll()
        fitCache.removeAll()
        lastFit = nil
        lastObjectFits.removeAll(keepingCapacity: true)
        shapes.removeAll()
        shapeBytes = 0
    }

    /// OUT-002f (REVIEW-5 M6): lays out, fits and rasterises what a scene's slide objects need (text boxes, fit-to-box text, shapes), as drawing the
    /// scene would, so that with `publishesRasters` the shared stores hold it before the first frame. Text that changes every second is left out.
    func prepareObjects(scene: SceneDescription, width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        for layer in scene.objectLayers {
            switch layer {
            case .text(let text) where !text.ticks:
                _ = try? placeText(text, width: width, height: height, fit: text.fitFloor == nil ? .unchanged : objectFitStatus(text, width: width, height: height))
            case .shape(let shape):
                _ = shapeDraw(shape, width: width, height: height)
            default:
                break
            }
        }
    }

    /// UI-007c: text objects fitted so far, one per distinct text box and output shape, never one per frame (tests and diagnostics).
    public private(set) var objectFitComputationCount = 0
    /// OUT-002f (tests and diagnostics): fit keys built for text objects (an array allocation and a hash of the words and style each time).
    var objectFitKeyBuildCount = 0

    // MARK: Offscreen rendering

    /// Renders to a new offscreen BGRA texture and reads it back. Used by tests and snapshots, not the live path.
    /// `video`, `backgroundMedia` and `foregroundMedia` are passed to `encode` as they are (tests use solid-colour textures).
    public func renderImage(scene: SceneDescription, width: Int, height: Int, video: MTLTexture? = nil,
                            backgroundMedia: MTLTexture? = nil, foregroundMedia: MTLTexture? = nil,
                            objectMedia: [UUID: MTLTexture] = [:]) throws -> RenderedFrame {
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td), let cb = queue.makeCommandBuffer() else {
            throw RenderError.resourceCreation("offscreen texture")
        }
        try encode(scene: scene, into: texture, video: video, commandBuffer: cb, imageLoading: .synchronous,
                   backgroundMedia: backgroundMedia, foregroundMedia: foregroundMedia, objectMedia: objectMedia)
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
    ///
    /// UI-007c: `objectMedia` holds the current frame of each clip a video object names (by the media bin's id); an object whose clip has no frame
    /// yet draws nothing. A frame fills the object's frame (cropped to it) and is clipped to it.
    public func encode(scene: SceneDescription, into texture: MTLTexture, video: MTLTexture? = nil,
                       commandBuffer: MTLCommandBuffer, imageLoading: ImageLoading = .background,
                       backgroundMedia: MTLTexture? = nil, foregroundMedia: MTLTexture? = nil,
                       objectMedia: [UUID: MTLTexture] = [:]) throws {
        let width = texture.width, height = texture.height
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        let pipeline = try pipeline(for: texture.pixelFormat)
        frameProblems.removeAll(keepingCapacity: true)
        defer {
            problemLock.lock(); publishedProblems = frameProblems; problemLock.unlock()
        }

        // Resolve text textures before encoding. A layer that cannot be drawn is skipped and reported: it never
        // keeps the rest of the scene from presenting (R2).
        // UI-005h: with a plate, the layers marked `inPlate` are stacked on it and drawn right after it; the others are placed as ever.
        var placed: [QuadDraw] = []
        var plateDraws: [QuadDraw] = []
        let platedLayers = scene.plate == nil ? [] : scene.textLayers.filter(\.inPlate)
        let fit = (try? fitStatus(scene: scene, width: width, height: height)) ?? .unchanged
        for layer in scene.textLayers where scene.plate == nil || !layer.inPlate {
            if let draw = safeTextDraw(layer, width: width, height: height, fit: fit) { placed.append(draw) }
        }
        if let plate = scene.plate, !platedLayers.isEmpty {
            do {
                if let result = try placePlate(plate, layers: platedLayers, width: width, height: height, fit: fit) {
                    plateDraws = [result.draw].compactMap { $0 } + result.texts.map(\.draw)
                }
            } catch {
                note(problem: "Plate skipped: \(error)")
            }
        }
        let gradientDraw = scene.backgroundGradient.flatMap { gradientTexture($0, width: width, height: height) }

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
                // UI-007c: a text box with "Shrink to fit box" has its own factor; every other one is drawn as it always was.
                let objectFit = text.fitFloor == nil ? TextFitStatus.unchanged : objectFitStatus(text, width: width, height: height)
                if let draw = safeTextDraw(text, width: width, height: height, fit: objectFit) { objects.append(draw) }
            case .video(let clip):
                if let frame = objectMedia[clip.mediaID], let draw = videoDraw(clip, frame, width: width, height: height) { objects.append(draw) }
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

        // UI-005h: a gradient is the colour layer: under the loop or a chosen background, over the clear colour.
        if let gradientDraw {
            var q = QuadUniforms(origin: .zero, size: target, target: target, uvOrigin: .zero, uvSize: SIMD2<Float>(1, 1))
            enc.setVertexBytes(&q, length: MemoryLayout<QuadUniforms>.stride, index: 0)
            enc.setFragmentTexture(gradientDraw, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

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
        for q in objects + plateDraws + placed { draw(q, with: enc, target: target, width: width, height: height) }

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

    /// UI-007c: a clip's frame in its object's frame: aspect-fill (the excess cropped), clipped to the frame, at the object's opacity.
    private func videoDraw(_ clip: VideoLayer, _ frame: MTLTexture, width: Int, height: Int) -> QuadDraw? {
        guard frame.width > 0, frame.height > 0, clip.opacity > 0 else { return nil }
        let rect = clip.frame.pixelRect(width: width, height: height)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let uv = Self.fillUV(sourceWidth: Double(frame.width), sourceHeight: Double(frame.height), width: Double(rect.width), height: Double(rect.height))
        return QuadDraw(texture: frame, origin: SIMD2(Float(rect.x), Float(rect.y)), size: SIMD2(Float(rect.width), Float(rect.height)),
                        uvOrigin: uv.origin, uvSize: uv.size, opacity: Float(clip.opacity), clip: rect)
    }

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
    private func safeTextDraw(_ layer: TextLayer, width: Int, height: Int, fit: TextFitStatus = .unchanged) -> QuadDraw? {
        do {
            return try textDraw(layer, width: width, height: height, fit: fit)
        } catch {
            note(problem: "Text layer skipped (\"\(Self.snippet(layer.text))\"): \(error)")
            return nil
        }
    }

    private func textDraw(_ layer: TextLayer, width: Int, height: Int, fit: TextFitStatus = .unchanged) throws -> QuadDraw? {
        try placeText(layer, width: width, height: height, fit: fit)?.draw
    }

    private struct PlacedText {
        let draw: QuadDraw
        let item: TextLayoutItem
    }

    /// A text bitmap's quad cut down to its ink (plus a pixel): a big soft shadow makes the padded bitmap several times the size of the words,
    /// and every transparent pixel of a quad is still blended. The pixels that are drawn are the same ones, at the same places. Used for the
    /// looks that place text by line boxes; the earlier placement keeps drawing the whole bitmap, byte for byte as before.
    private func inkQuad(_ c: CachedText, origin: SIMD2<Float>, opacity: Float, clip: NormalizedRect.PixelRect?) -> QuadDraw {
        let ink = c.ink
        guard ink.width > 0, ink.height > 0, c.width > 0, c.height > 0 else {
            return QuadDraw(texture: c.texture, origin: origin, size: SIMD2(Float(c.width), Float(c.height)), uvOrigin: .zero, uvSize: SIMD2(1, 1), opacity: opacity, clip: clip)
        }
        let x0 = max(0, Int(ink.minX) - 1), y0 = max(0, Int(ink.minY) - 1)
        let x1 = min(c.width, Int(ink.maxX) + 1), y1 = min(c.height, Int(ink.maxY) + 1)
        let w = Float(c.width), h = Float(c.height)
        return QuadDraw(texture: c.texture, origin: SIMD2(origin.x + Float(x0), origin.y + Float(y0)), size: SIMD2(Float(x1 - x0), Float(y1 - y0)),
                        uvOrigin: SIMD2(Float(x0) / w, Float(y0) / h), uvSize: SIMD2(Float(x1 - x0) / w, Float(y1 - y0) / h), opacity: opacity, clip: clip)
    }

    /// The style at the output's size: sizes, outline and shadow are points at the 1080-line reference height.
    private func scaled(_ style: TextStyle, height: Int, factor: Double = 1) -> TextStyle {
        let scale = Double(height) / Self.referenceHeight
        var scaled = TextFitter.scaled(style, by: factor)
        scaled.fontSize *= scale
        scaled.outlineWidth *= scale
        if var shadow = scaled.shadow {
            shadow.offsetX *= scale
            shadow.offsetY *= scale
            shadow.blur *= scale
            scaled.shadow = shadow
        }
        return scaled
    }

    /// Rasterises (or fetches) a text layer and places it in its frame. Nil when there is nothing to draw.
    ///
    /// A style without a line height is placed by its padded bitmap, as it always was. A style with one is placed by its line boxes, like a
    /// web page: the block's edges (the widest line, the lines' pitch times their count) sit on the frame's edge or centre, the text wraps at
    /// the frame's width, and the bitmap's padding (for outline, shadow and marks) hangs outside it.
    private func placeText(_ layer: TextLayer, width: Int, height: Int, fit: TextFitStatus = .unchanged) throws -> PlacedText? {
        guard !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let frame = layer.frame.pixelRect(width: width, height: height)
        guard frame.width > 8, frame.height > 0 else { return nil }
        let opacity = Float(min(1, max(0, layer.opacity)))
        guard opacity > 0 else { return nil }
        // FIX-J: a layer with a fit floor is drawn at the group's factor, and, when it cannot fit even at the floor, clipped to the title-safe frame.
        let fitted = layer.fitFloor != nil
        let style = scaled(layer.style, height: height, factor: fitted ? fit.factor : 1)
        let lineBoxMode = layer.style.lineHeight != nil
        let pad = TextRasterizer.padding(for: style)
        let cached = try cachedText(layer.text, style: style, maxWidth: lineBoxMode ? frame.width + 2 * pad.x : frame.width, alignment: layer.alignment, ticks: layer.ticks)
        if cached.clipped { note(problem: "Text taller than the limit was clipped (\"\(Self.snippet(layer.text))\")") }
        let item: (box: LayoutBox, origin: SIMD2<Float>, clip: NormalizedRect.PixelRect)
        if lineBoxMode {
            let fx = layer.frame.x * Double(width), fy = layer.frame.y * Double(height)
            let fw = layer.frame.width * Double(width), fh = layer.frame.height * Double(height)
            let bx: Double
            switch layer.alignment {
            case .leading: bx = fx
            case .center: bx = fx + (fw - cached.blockWidth) / 2
            case .trailing: bx = fx + fw - cached.blockWidth
            }
            let by: Double
            switch layer.verticalAlignment {
            case .top: by = fy
            case .center: by = fy + (fh - cached.blockHeight) / 2
            case .bottom: by = fy + fh - cached.blockHeight
            }
            // Whole pixels, so glyph edges are sampled exactly and stay as sharp as they were rasterised.
            let origin = SIMD2(Float((bx - cached.lineBoxLeft).rounded()), Float((by - cached.lineBoxTop).rounded()))
            let clip = fitted && !fit.fits
                ? frame      // exactly the block's frame: no room for padding, the words that do not fit are cut at the title-safe edge
                : NormalizedRect.PixelRect(x: frame.x - pad.x, y: frame.y - pad.y, width: frame.width + 2 * pad.x, height: frame.height + 2 * pad.y)
            item = (LayoutBox(x: bx, y: by, width: cached.blockWidth, height: cached.blockHeight), origin, clip)
        } else {
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
            item = (LayoutBox(x: Double(x), y: Double(y), width: Double(cached.width), height: Double(cached.height)),
                    SIMD2(Float(x), Float(y)), frame)
        }
        let draw = lineBoxMode
            ? inkQuad(cached, origin: item.origin, opacity: opacity, clip: item.clip)
            : QuadDraw(texture: cached.texture, origin: item.origin, size: SIMD2(Float(cached.width), Float(cached.height)),
                       uvOrigin: .zero, uvSize: SIMD2(1, 1), opacity: opacity, clip: item.clip)
        return PlacedText(draw: draw, item: TextLayoutItem(text: layer.text, box: item.box, fontSize: style.fontSize,
                                                           weight: layer.style.weight ?? 400, lineCount: cached.lineCount, inPlate: false))
    }

    // MARK: Plate (UI-005h)

    private struct PlateResult {
        let plate: LayoutBox
        let bar: LayoutBox?
        let draw: QuadDraw?
        let texts: [PlacedText]
    }

    /// Stacks the plated layers inside the plate's padding (beside its bar), sizes the plate to them, sits it `bottomMargin` above the bottom
    /// of the frame and fetches its bitmap. Nil when no plated layer has anything to show: no words, no plate.
    private func placePlate(_ plate: TextPlate, layers: [TextLayer], width: Int, height: Int, fit: TextFitStatus = .unchanged) throws -> PlateResult? {
        let scale = Double(height) / Self.referenceHeight
        let shown = layers.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.opacity > 0 }
        guard !shown.isEmpty else { return nil }
        let plateX = plate.x * Double(width), plateW = plate.width * Double(width)
        let padX = plate.paddingX * scale, padY = plate.paddingY * scale
        let barW = (plate.bar?.width ?? 0) * scale, gap = plate.bar.map { $0.gap * scale } ?? 0
        let textLeft = plateX + padX + (plate.bar == nil ? 0 : barW + gap)
        let textWidth = plateX + plateW - padX - textLeft
        guard textWidth > 8 else { return nil }

        var blocks: [(layer: TextLayer, style: TextStyle, cached: CachedText)] = []
        for layer in shown {
            let style = scaled(layer.style, height: height, factor: layer.fitFloor != nil ? fit.factor : 1)
            let pad = TextRasterizer.padding(for: style)
            let cached = try cachedText(layer.text, style: style, maxWidth: Int(textWidth.rounded()) + 2 * pad.x, alignment: layer.alignment, ticks: layer.ticks)
            if cached.clipped { note(problem: "Text taller than the limit was clipped (\"\(Self.snippet(layer.text))\")") }
            blocks.append((layer, style, cached))
        }
        let contentHeight = blocks.reduce(0) { $0 + $1.cached.blockHeight }
        let plateHeight = contentHeight + 2 * padY
        let plateBottom = Double(height) - plate.bottomMargin * scale
        let plateTop = plateBottom - plateHeight

        // FIX-J: words that cannot fit even at the floor are clipped, with their plate, to the title-safe frame.
        let unfit = !fit.fits && shown.contains { $0.fitFloor != nil }
        let safe = TextFitter.titleSafe.pixelRect(width: width, height: height)
        var texts: [PlacedText] = []
        var y = plateTop + padY
        for block in blocks {
            let c = block.cached
            let bx: Double
            switch block.layer.alignment {
            case .leading: bx = textLeft
            case .center: bx = textLeft + (textWidth - c.blockWidth) / 2
            case .trailing: bx = textLeft + textWidth - c.blockWidth
            }
            let origin = SIMD2(Float((bx - c.lineBoxLeft).rounded()), Float((y - c.lineBoxTop).rounded()))
            let draw = inkQuad(c, origin: origin, opacity: Float(block.layer.opacity), clip: unfit ? safe : nil)
            texts.append(PlacedText(draw: draw, item: TextLayoutItem(text: block.layer.text, box: LayoutBox(x: bx, y: y, width: c.blockWidth, height: c.blockHeight),
                                                                    fontSize: block.style.fontSize, weight: block.layer.style.weight ?? 400,
                                                                    lineCount: c.lineCount, inPlate: true)))
            y += c.blockHeight
        }

        let left = Int(plateX.rounded()), top = Int(plateTop.rounded())
        let right = Int((plateX + plateW).rounded()), bottom = Int(plateBottom.rounded())
        var barBox: LayoutBox?
        var barKey: (x: Int, y: Int, w: Int, h: Int)?
        if let bar = plate.bar, barW > 0 {
            let bl = Int((plateX + padX).rounded()), bt = Int((plateTop + padY).rounded())
            let br = Int((plateX + padX + barW).rounded()), bb = Int((plateTop + padY + contentHeight).rounded())
            barBox = LayoutBox(x: plateX + padX, y: plateTop + padY, width: barW, height: contentHeight)
            barKey = (bl - left, bt - top, max(1, br - bl), max(1, bb - bt))
            _ = bar
        }
        let box = LayoutBox(x: plateX, y: plateTop, width: plateW, height: plateHeight)
        guard right > left, bottom > top else { return PlateResult(plate: box, bar: barBox, draw: nil, texts: texts) }
        let key = PlateKey(width: right - left, height: bottom - top, radius: Int((plate.cornerRadius * scale * 100).rounded()), fill: plate.fill,
                           barX: barKey?.x ?? 0, barY: barKey?.y ?? 0, barWidth: barKey?.w ?? 0, barHeight: barKey?.h ?? 0,
                           barTop: plate.bar?.top ?? .clear, barBottom: plate.bar?.bottom ?? .clear)
        guard let texture = plateTexture(key) else {
            note(problem: "A plate could not be drawn (\(key.width)x\(key.height) px)")
            return PlateResult(plate: box, bar: barBox, draw: nil, texts: texts)
        }
        // FIX-J item 8: the plate is as opaque as the most opaque of the layers on it (all fading out, it fades too).
        let plateOpacity = Float(shown.map(\.opacity).max() ?? 1)
        let draw = QuadDraw(texture: texture, origin: SIMD2(Float(left), Float(top)), size: SIMD2(Float(key.width), Float(key.height)),
                            uvOrigin: .zero, uvSize: SIMD2(1, 1), opacity: plateOpacity, clip: unfit ? safe : nil)
        return PlateResult(plate: box, bar: barBox, draw: draw, texts: texts)
    }

    private func plateTexture(_ key: PlateKey) -> MTLTexture? {
        if let hit = plates[key] { return hit }
        let bar = key.barWidth > 0 ? (x: key.barX, y: key.barY, width: key.barWidth, height: key.barHeight, top: key.barTop, bottom: key.barBottom) : nil
        guard let pixels = LooksRasterizer.plate(width: key.width, height: key.height, radius: Double(key.radius) / 100, fill: key.fill, bar: bar),
              let texture = makeTexture(pixels, width: key.width, height: key.height) else { return nil }
        looksRasterizationCount += 1
        if plates.count >= looksCacheLimit { plates.removeAll(keepingCapacity: true) }
        plates[key] = texture
        return texture
    }

    private func gradientTexture(_ gradient: GradientBackground, width: Int, height: Int) -> MTLTexture? {
        let key = GradientKey(gradient: gradient, width: width, height: height)
        if let hit = gradients[key] { return hit }
        guard let pixels = LooksRasterizer.gradient(gradient, width: width, height: height),
              let texture = makeTexture(pixels, width: width, height: height) else {
            note(problem: "A gradient background could not be drawn (\(width)x\(height) px)")
            return nil
        }
        looksRasterizationCount += 1
        if gradients.count >= looksCacheLimit { gradients.removeAll(keepingCapacity: true) }
        gradients[key] = texture
        return texture
    }

    private func makeTexture(_ pixels: [UInt8], width: Int, height: Int) -> MTLTexture? {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = .shaderRead
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td) else { return nil }
        pixels.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: base, bytesPerRow: width * 4)
            }
        }
        return texture
    }

    // MARK: Layout report (UI-005h)

    /// Where `scene`'s text, plate and bar go at `width` x `height`, in output pixels: the line boxes' edges as laid out (a layer drawn
    /// without a line height reports its padded bitmap). Rasterises like a frame would; for measuring, not for the live path.
    public func layoutReport(scene: SceneDescription, width: Int, height: Int) throws -> SceneLayoutReport {
        guard width > 0, height > 0 else { throw RenderError.invalidSize }
        var report = SceneLayoutReport()
        let platedLayers = scene.plate == nil ? [] : scene.textLayers.filter(\.inPlate)
        let fit = try fitStatus(scene: scene, width: width, height: height)
        for layer in scene.textLayers where scene.plate == nil || !layer.inPlate {
            if let placed = try placeText(layer, width: width, height: height, fit: fit) { report.texts.append(placed.item) }
        }
        if let plate = scene.plate, let result = try placePlate(plate, layers: platedLayers, width: width, height: height, fit: fit) {
            report.plate = result.plate
            report.bar = result.bar
            report.texts = result.texts.map(\.item) + report.texts
        }
        return report
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
            let pixels: [UInt8]
            if let prepared = SharedTextStore.shared.shape(for: key) {      // OUT-002f: rasterised ahead of Go Live: no bitmap drawing on this frame
                pixels = prepared
            } else if let made = ShapeRasterizer.rasterize(shape: key.shape, fill: key.fill, strokeColor: key.strokeColor,
                                                           strokeWidth: Double(key.strokeWidth) / 100,
                                                           width: key.width, height: key.height) {
                pixels = made
                shapeRasterizationCount += 1
                if publishesRasters { SharedTextStore.shared.put(shape: made, for: key) }
            } else {
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

    /// The clock the image re-check interval is measured on. A test seam (KI-060): tests move it by hand instead of waiting.
    var uptime: @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }
    private func now() -> Double { uptime() }

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

    private func cachedText(_ text: String, style: TextStyle, maxWidth: Int, alignment: TextAlignment, ticks: Bool = false) throws -> CachedText {
        let key = TextRasterKey(text: text, style: style, maxWidth: maxWidth, alignment: alignment)
        if let hit = ticks ? tickingCache.value(for: key) : lyricCache.value(for: key) { return hit }
        let raster: RasterizedText
        if let prepared = SharedTextStore.shared.raster(for: key) {      // rasterised ahead of Go Live (TextWarmer): no Core Text on this frame
            raster = prepared
        } else {
            raster = try rasterizer.rasterize(text, style: style, maxWidth: maxWidth, alignment: alignment)
            rasterizationCount += 1
            if publishesRasters { SharedTextStore.shared.put(raster, for: key) }
        }
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
        let entry = CachedText(texture: tex, width: raster.width, height: raster.height, clipped: raster.clipped,
                               lineBoxLeft: raster.lineBoxLeft, lineBoxTop: raster.lineBoxTop, blockWidth: raster.blockWidth,
                               blockHeight: raster.blockHeight, lineCount: raster.lineCount, ink: raster.inkBounds)
        if ticks { tickingCache.insert(entry, for: key) } else { lyricCache.insert(entry, for: key) }
        return entry
    }
}
