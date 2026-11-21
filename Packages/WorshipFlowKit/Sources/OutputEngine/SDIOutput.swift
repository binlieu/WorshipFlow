// HW-002 / SCRN-11, SCRN-10: an output that renders each published scene with the shared compositor into an offscreen
// texture at the video mode's size, reads it back as BGRA and feeds an SDIOutputSession as its frame provider.
//
// The clock is the device's completion callbacks (ADR-0005 decision 5), not a display link: the session asks for the
// next frame each time the card reports one finished, on whatever thread that arrives. Rendering and readback happen on
// that thread (or on this output's own queue for the first frames), never on the main thread.
// Simulated is the highest level this has reached: no card and no vendor SDK exist yet.
import Foundation
import Metal
import Domain
import RenderEngine
import SDIEngine

/// Render and readback time per frame, measured around the compositor, the GPU wait and the copy to memory.
public struct SDIRenderTiming: Sendable, Equatable {
    public var frames = 0
    public var totalMs = 0.0
    public var worstMs = 0.0
    public var meanMs: Double { frames > 0 ? totalMs / Double(frames) : 0 }
}

/// Renders scenes to BGRA frames. Used from one thread at a time: calls are serialised by `lock`, because the first
/// frames come from the output's own queue and later ones from the card's callback thread.
/// `@unchecked Sendable`: every stored property after init is touched only while holding `lock`.
final class SDIFrameRenderer: @unchecked Sendable {
    private let width: Int
    private let height: Int
    private let sceneProvider: SceneProvider
    private let videoSource: (any VideoSourceFactory)?
    private let mediaSource: (any MediaFrameSource)?

    private let lock = NSLock()
    private var compositor: Compositor?
    private var texture: MTLTexture?
    private var textureProvider: (any VideoTextureProvider)?
    private var mediaResolver: MediaFrameResolver?
    private var recent: [VideoTexture] = []
    private var ring: [[UInt8]]
    private var nextSlot = 0
    private var failed: String?
    private var lastSceneOpaque = false
    private(set) var reallocations = 0
    private var timing = SDIRenderTiming()

    init(width: Int, height: Int, ringSize: Int, sceneProvider: @escaping SceneProvider,
         videoSource: (any VideoSourceFactory)?, mediaSource: (any MediaFrameSource)?) {
        self.width = width
        self.height = height
        self.sceneProvider = sceneProvider
        self.videoSource = videoSource
        self.mediaSource = mediaSource
        self.ring = Array(repeating: [UInt8](repeating: 0, count: width * height * 4), count: max(2, ringSize))
    }

    var renderTiming: SDIRenderTiming { lock.withLock { timing } }
    var bufferReallocations: Int { lock.withLock { reallocations } }
    func resetTiming() { lock.withLock { timing = SDIRenderTiming() } }
    var lastError: String? { lock.withLock { failed } }
    var sceneIsOpaque: Bool { lock.withLock { lastSceneOpaque } }
    var unavailableImagePaths: Set<String> { lock.withLock { compositor?.unavailableImagePaths ?? [] } }
    var renderProblems: [String] { lock.withLock { compositor?.renderProblems ?? [] } }

    /// The frame for the next slot, or nil when it could not be drawn (the session then repeats the last frame).
    func frame() -> SDIFrame? {
        lock.lock(); defer { lock.unlock() }
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            try prepareIfNeeded()
            guard let compositor, let texture else { return nil }
            var scene = sceneProvider()
            lastSceneOpaque = SDIOutput.isOpaque(scene)
            if mediaResolver == nil { scene.backgroundMedia = nil; scene.foregroundMedia = nil }
            let media = mediaResolver?.resolve(scene) ?? MediaFrameTextures()
            var video: MTLTexture?
            if scene.showsVideo, let frame = textureProvider?.currentTexture() {
                video = frame.texture
                recent.append(frame)
                if recent.count > 4 { recent.removeFirst(recent.count - 4) }
            }
            guard let cb = compositor.makeCommandBuffer() else { throw RenderError.resourceCreation("command buffer") }
            try compositor.encode(scene: scene, into: texture, video: video, commandBuffer: cb,
                                  backgroundMedia: media.background?.texture, foregroundMedia: media.foreground?.texture)
            cb.commit()
            cb.waitUntilCompleted()
            withExtendedLifetime(media.hold) {}
            if let error = cb.error { throw RenderError.pipeline("\(error)") }
            let slot = nextSlot
            nextSlot = (nextSlot + 1) % ring.count
            read(texture, into: slot)
            failed = nil
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            timing.frames += 1
            timing.totalMs += elapsed
            timing.worstMs = max(timing.worstMs, elapsed)
            return SDIFrame(width: width, height: height, bgra: ring[slot])
        } catch {
            failed = "\(error)"
            return nil
        }
    }

    /// Writes the pixels into the slot's own array. If something (the card, the session) still holds that array the
    /// write copies it first; that is counted, and does not happen in steady state with a ring larger than the frames in flight.
    private func read(_ texture: MTLTexture, into slot: Int) {
        let before = ring[slot].withUnsafeBufferPointer { $0.baseAddress }
        let w = width, h = height
        ring[slot].withUnsafeMutableBytes { raw in
            if let base = raw.baseAddress {
                texture.getBytes(base, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
            }
        }
        let after = ring[slot].withUnsafeBufferPointer { $0.baseAddress }
        if before != after { reallocations += 1 }
    }

    private func prepareIfNeeded() throws {
        guard compositor == nil else { return }
        let compositor = try Compositor()
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = compositor.device.makeTexture(descriptor: td) else { throw RenderError.resourceCreation("offscreen texture") }
        if let videoSource { textureProvider = try videoSource.makeTextureProvider(device: compositor.device) }
        if let mediaSource { mediaResolver = try MediaFrameResolver(source: mediaSource, device: compositor.device) }
        self.texture = texture
        self.compositor = compositor
    }
}

@MainActor
public final class SDIOutput: OutputTarget {
    public static let opaqueKeyWarning = "Nothing will key: background is opaque. Give this screen a theme with a transparent background, such as the lower third."

    /// True when a keyed output of this scene would send a key that is white everywhere, so nothing would be keyed out.
    /// Conservative: a background colour with any transparency, and no video, image or media layer behind the text, is not opaque.
    public nonisolated static func isOpaque(_ scene: SceneDescription) -> Bool {
        scene.backgroundColor.alpha >= 1 || scene.showsVideo || scene.backgroundImage != nil
            || scene.backgroundMedia != nil || scene.foregroundMedia != nil
    }

    public let name: String
    public private(set) var status: OutputStatus = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: (@MainActor (OutputStatus) -> Void)?
    public var refreshRate: Double { mode.framesPerSecond }

    private let port: any SDIOutputPort
    private let mode: SDIVideoMode
    private let keying: SDIKeying
    private let isSimulated: Bool
    private let clock: (any SDIOutputClock)?
    private let renderer: SDIFrameRenderer
    private let session: SDIOutputSession
    private let queue = DispatchQueue(label: "WorshipFlow.sdi.start", qos: .userInteractive)
    private var clockRunning = false
    private var lostDevice = false

    /// - Parameters:
    ///   - clock: drives the card's completions in real time. Nil leaves the clock to the caller (tests use a manual one).
    ///   - prerollFrames, maxBufferedFrames: the session's buffering; the frame ring is sized from them.
    public init(name: String, port: any SDIOutputPort, mode: SDIVideoMode, keying: SDIKeying, isSimulated: Bool,
                sceneProvider: @escaping SceneProvider, videoSource: (any VideoSourceFactory)? = nil,
                mediaSource: (any MediaFrameSource)? = nil, clock: (any SDIOutputClock)? = nil,
                prerollFrames: Int = 3, maxBufferedFrames: Int = 5) {
        self.name = name
        self.port = port
        self.mode = mode
        self.keying = keying
        self.isSimulated = isSimulated
        self.clock = clock
        let renderer = SDIFrameRenderer(width: mode.width, height: mode.height, ringSize: max(prerollFrames, maxBufferedFrames) + 5,
                                        sceneProvider: sceneProvider, videoSource: videoSource, mediaSource: mediaSource)
        self.renderer = renderer
        self.session = SDIOutputSession(port: port, mode: mode, keying: keying, prerollFrames: prerollFrames,
                                        maxBufferedFrames: maxBufferedFrames) { _ in renderer.frame() }
    }

    // MARK: Readout

    public var statistics: FrameStatistics {
        let s = session.statistics.scheduler
        return FrameStatistics(targetInterval: 1.0 / max(1, refreshRate), presentedFrames: s.completed + s.late,
                               droppedFrames: s.dropped, lateFrames: s.late)
    }

    public var lastRenderError: String? { renderer.lastError }
    public var unavailableImagePaths: [String] { renderer.unavailableImagePaths.sorted() }
    public var renderProblems: [String] { renderer.renderProblems }
    public var renderTiming: SDIRenderTiming { renderer.renderTiming }
    var bufferReallocations: Int { renderer.bufferReallocations }
    /// Forgets the timings so far (a benchmark does this after its warm-up).
    func resetRenderTiming() { renderer.resetTiming() }

    public var diagnostics: String {
        let s = session.statistics
        return "sdi \(mode.name), scheduled \(s.scheduler.scheduled), completed \(s.scheduler.completed), late \(s.scheduler.late), "
            + "dropped \(s.scheduler.dropped), repeated \(s.repeatedFrames), buffered \(port.bufferedFrameCount), "
            + String(format: "render %.2f ms mean, %.2f ms worst", renderer.renderTiming.meanMs, renderer.renderTiming.worstMs)
    }

    public var sdiReport: SDIOutputReport? {
        var warnings: [String] = []
        if case .external = keying, renderer.sceneIsOpaque, renderer.renderTiming.frames > 0 { warnings.append(Self.opaqueKeyWarning) }
        return SDIOutputReport(health: session.health, repeatedFrames: session.statistics.repeatedFrames, warnings: warnings,
                               isSimulated: isSimulated, modeName: mode.name)
    }

    public var stoppedByDeviceLoss: Bool { lostDevice }

    // MARK: Control

    /// Checks the card accepts the mode and keying, then starts the session on this output's queue: the first frames are
    /// rendered there, not on the caller's thread. A problem found after that arrives as a stop with a reason.
    public func start() throws {
        guard status != .running else { return }
        guard port.supports(mode: mode, keying: keying) else {
            if case .external = keying { throw SDIError.keyingUnavailable(connector: port.connector) }
            throw SDIError.unsupportedMode(mode.name)
        }
        session.onStop = { [weak self] reason in
            Task { @MainActor in self?.sessionStopped(reason) }
        }
        lostDevice = false
        status = .running
        let session = session, clock = clock
        queue.async { [weak self] in
            do {
                try session.start()
                clock?.start()
                Task { @MainActor in self?.clockStarted() }
            } catch {
                // `onStop` has already reported the failure.
            }
        }
    }

    private func clockStarted() {
        if status == .running { clockRunning = clock != nil } else { clock?.stop() }
    }

    public func stop() { finish(reason: nil) }

    /// Tests: returns when the work `start()` queued has finished, so the first frames are scheduled.
    func waitUntilStarted() { queue.sync {} }

    private func sessionStopped(_ reason: SDIStopReason) {
        guard status == .running else { return }
        switch reason {
        case .requested: finish(reason: nil)
        case .failed(let error):
            lostDevice = error == .deviceDisconnected
            finish(reason: error.description)
        }
    }

    private func finish(reason: String?) {
        guard status == .running else { return }
        status = .stopped(reason: reason)
        session.onStop = nil
        session.stop()
        port.close()
        if clockRunning { clock?.stop(); clockRunning = false }
    }
}
