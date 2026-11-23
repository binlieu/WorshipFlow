// OUT-001: the render-thread half of an output. Pulls a scene, composites it into the next drawable and
// presents it, off the main thread, without blocking: if the GPU is behind, the tick is skipped.
import Foundation
import QuartzCore
import Metal
import Domain
import RenderEngine

// @unchecked Sendable: `compositor`, `textureProvider` and `recent` are touched only from the render thread
// (tick) after `prepare()`; shared mutable state (`stats`, `running`, `errorText`) is guarded by `lock`.
final class OutputRenderer: @unchecked Sendable {
    private let layer: CAMetalLayer
    private let sceneProvider: SceneProvider
    private let videoSource: (any VideoSourceFactory)?
    private let mediaSource: (any MediaFrameSource)?
    private let lock = NSLock()
    private var stats: FrameStatistics
    private var running = false
    private var errorText: String?
    private var ticks = 0
    private var submittedFrames = 0
    private let inFlight = DispatchSemaphore(value: 2)

    private var compositor: Compositor?
    private var textureProvider: (any VideoTextureProvider)?
    private var recent: [VideoTexture] = []
    private var mediaResolver: MediaFrameResolver?

    init(layer: CAMetalLayer, sceneProvider: @escaping SceneProvider, videoSource: (any VideoSourceFactory)?, targetInterval: Double,
         mediaSource: (any MediaFrameSource)? = nil) {
        self.layer = layer
        self.sceneProvider = sceneProvider
        self.videoSource = videoSource
        self.mediaSource = mediaSource
        self.stats = FrameStatistics(targetInterval: targetInterval)
    }

    func prepare() throws {
        let compositor = try Compositor()
        layer.device = compositor.device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.maximumDrawableCount = 3
        layer.isOpaque = true
        layer.displaySyncEnabled = true
        if let videoSource { textureProvider = try videoSource.makeTextureProvider(device: compositor.device) }
        if let mediaSource { mediaResolver = try MediaFrameResolver(source: mediaSource, device: compositor.device) }
        self.compositor = compositor
        lock.lock(); running = true; lock.unlock()
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }

    var statistics: FrameStatistics { lock.lock(); defer { lock.unlock() }; return stats }
    /// (display-link ticks received, frames submitted to the GPU) for diagnostics.
    var counters: (ticks: Int, submitted: Int) { lock.lock(); defer { lock.unlock() }; return (ticks, submittedFrames) }
    var lastError: String? { lock.lock(); defer { lock.unlock() }; return errorText }
    /// Image files the compositor could not read (OUT-003). `compositor` is assigned once in `prepare()`, before
    /// the output runs; the set itself is lock-guarded inside the compositor.
    var unavailableImagePaths: Set<String> { compositor?.unavailableImagePaths ?? [] }

    /// Layers the compositor left out of the last frame because they could not be drawn (R2). `compositor` is assigned
    /// once in `prepare()`; the list itself is lock-guarded inside the compositor.
    var renderProblems: [String] { compositor?.renderProblems ?? [] }

    func setTargetInterval(_ interval: Double) {
        lock.lock(); stats.targetInterval = interval; lock.unlock()
    }

    private func record(presentedAt t: Double) {
        lock.lock(); stats.recordPresentation(at: t); lock.unlock()
    }

    private func fail(_ message: String) {
        lock.lock(); errorText = message; lock.unlock()
    }

    /// Called by the display link on the render thread.
    func tick() {
        lock.lock(); ticks += 1; let isRunning = running; lock.unlock()
        guard isRunning, let compositor else { return }
        let size = layer.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        guard inFlight.wait(timeout: .now()) == .success else { return }   // GPU behind: skip, never block

        var submitted = false
        autoreleasepool {
            guard let drawable = layer.nextDrawable(), let cb = compositor.makeCommandBuffer() else { return }
            var scene = sceneProvider()
            // Without a registry there is no way to draw chosen media: leave the scene as it was before media layers
            // existed (the theme's shared video, if any).
            if mediaResolver == nil { scene.backgroundMedia = nil; scene.foregroundMedia = nil }
            let media = mediaResolver?.resolve(scene) ?? MediaFrameTextures()
            var video: MTLTexture?
            if scene.showsVideo, let frame = textureProvider?.currentTexture() {
                video = frame.texture
                recent.append(frame)
                if recent.count > 4 { recent.removeFirst(recent.count - 4) }   // keep CVMetalTextures alive while in flight
            }
            do {
                try compositor.encode(scene: scene, into: drawable.texture, video: video, commandBuffer: cb,
                                      backgroundMedia: media.background?.texture, foregroundMedia: media.foreground?.texture,
                                      objectMedia: media.objectTextures)
            } catch {
                fail("\(error)")
                return
            }
            drawable.addPresentedHandler { [weak self] d in
                let t = d.presentedTime
                if t > 0 { self?.record(presentedAt: t) }
            }
            cb.present(drawable)
            let sem = inFlight
            let held = media.hold          // the frames' textures must outlive the GPU work that reads them
            cb.addCompletedHandler { _ in withExtendedLifetime(held) { _ = sem.signal() } }
            cb.commit()
            submitted = true
        }
        if !submitted { inFlight.signal() } else { lock.lock(); submittedFrames += 1; lock.unlock() }
    }
}
