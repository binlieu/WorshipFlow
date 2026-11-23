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
    private var events = FrameEventLog()   // OUT-002b: reserved once; guarded by `lock`
    private var ring = TickRing()          // OUT-002d: the last ticks, preallocated; written once per tick under `lock`
    private var running = false
    private var errorText: String?
    private var ticks = 0
    private var submittedFrames = 0
    private let inFlight = DispatchSemaphore(value: 2)
    // OUT-002c: a scene with words or images not yet shown is prepared off this thread first; touched only from the render thread.
    private let gate: ScenePreparationGate

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
        let preparer = BackgroundScenePreparer()
        self.gate = ScenePreparationGate { scene, width, height, isWanted, done in
            preparer.prepare(scene, width, height, isWanted: isWanted, done: done)
        }
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
    var frameEvents: FrameEventLog { lock.lock(); defer { lock.unlock() }; return events }
    /// The recorded ticks, oldest first (OUT-002d).
    var tickSamples: [TickSample] { lock.lock(); defer { lock.unlock() }; return ring.snapshot() }
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
        lock.lock()
        // OUT-002b: a compare, and a few stores when notable. OUT-002d: a notable frame also copies the ring (the snapshot is not taken otherwise).
        if let outcome = stats.recordPresentation(at: t) { events.record(at: t, outcome, targetInterval: stats.targetInterval, ticks: ring.snapshot()) }
        lock.unlock()
    }

    private func fail(_ message: String) {
        lock.lock(); errorText = message; lock.unlock()
    }

    /// Called by the display link on the render thread. `linkTimestamp` and `linkTarget` are the link's own times (0 when it gave none); they are
    /// only recorded (OUT-002d).
    func tick(linkTimestamp: Double = 0, linkTarget: Double = 0) {
        let t0 = CACurrentMediaTime()   // OUT-002d clock read 1 of 4
        lock.lock(); ticks += 1; let isRunning = running; lock.unlock()
        guard isRunning, let compositor else { return }
        let size = layer.drawableSize
        guard size.width >= 1, size.height >= 1 else { return }
        guard inFlight.wait(timeout: .now()) == .success else {   // GPU behind: skip, never block
            let skipped = TickSample(start: t0, linkTimestamp: linkTimestamp, linkTarget: linkTarget, flags: TickSample.skipped)
            lock.lock(); ring.push(skipped); events.noteSkippedTick(); lock.unlock()   // OUT-002d
            return
        }

        var submitted = false
        // OUT-002d: where each phase ended (-1: not reached) and the tick's flags.
        var drawableEnd = -1.0, builtEnd = -1.0
        var flags: UInt8 = 0
        autoreleasepool {
            guard let drawable = layer.nextDrawable(), let cb = compositor.makeCommandBuffer() else { return }
            drawableEnd = CACurrentMediaTime()   // OUT-002d clock read 2 of 4
            var scene = gate.sceneToDraw(sceneProvider(), width: Int(size.width), height: Int(size.height))   // OUT-002c
            if gate.isHolding { flags |= TickSample.gateHolding }
            if gate.adoptedOnLastCall { flags |= TickSample.sceneChanged }
            // Without a registry there is no way to draw chosen media: leave the scene as it was before media layers
            // existed (the theme's shared video, if any).
            if mediaResolver == nil { scene.backgroundMedia = nil; scene.foregroundMedia = nil }
            let media = mediaResolver?.resolve(scene) ?? MediaFrameTextures()
            var video: MTLTexture?
            if scene.showsVideo, let frame = textureProvider?.currentTexture() {
                video = frame.texture
                if recent.last?.keepAlive !== frame.keepAlive { flags |= TickSample.newVideoFrame }   // OUT-002d
                recent.append(frame)
                if recent.count > 4 { recent.removeFirst(recent.count - 4) }   // keep CVMetalTextures alive while in flight
            }
            builtEnd = CACurrentMediaTime()   // OUT-002d clock read 3 of 4
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
        let end = CACurrentMediaTime()   // OUT-002d clock read 4 of 4
        let afterDrawable = drawableEnd >= 0 ? drawableEnd : end
        let afterBuild = builtEnd >= 0 ? builtEnd : afterDrawable
        let sample = TickSample(start: t0, linkTimestamp: linkTimestamp, linkTarget: linkTarget, drawable: afterDrawable - t0,
                                build: afterBuild - afterDrawable, encode: end - afterBuild, flags: flags)
        if !submitted { inFlight.signal() }
        // The lock the submitted count already took; only a tick that made no frame takes it for the first time here.
        lock.lock()
        if submitted { submittedFrames += 1 }
        ring.push(sample)
        events.noteTick(work: sample.work, period: stats.targetInterval)
        lock.unlock()
    }
}
