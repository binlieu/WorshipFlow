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
/// `@unchecked Sendable`: the render state is touched only while holding `lock`; the readout values (what the operator window reads on the
/// main actor) only while holding `readoutLock`. FIX-T item 6 (M5): `lock` is held across the GPU wait, so a readout never takes it.
final class SDIFrameRenderer: @unchecked Sendable {
    private let width: Int
    private let height: Int
    private let sceneProvider: SceneProvider
    private let videoSource: (any VideoSourceFactory)?
    private let mediaSource: (any MediaFrameSource)?

    private let lock = NSLock()
    private var compositor: Compositor?
    private var texture: MTLTexture?
    /// UI-005h: the frame is copied by the GPU into this shared buffer in the same command buffer, then to the ring by one memory copy.
    private var readbackBuffer: MTLBuffer?
    private var textureProvider: (any VideoTextureProvider)?
    private var mediaResolver: MediaFrameResolver?
    private var recent: [VideoTexture] = []
    private var ring: [[UInt8]]
    private var nextSlot = 0
    /// FIX-T item 6 (M5): the values the main actor reads, copied here at the end of a frame under a short lock of their own.
    private let readoutLock = NSLock()
    private var failed: String?
    private var lastSceneOpaque = false
    private var reallocations = 0
    /// Render side of `reallocations`: counted under `lock`, copied to the readout at the end of the frame.
    private var ringReallocations = 0
    private var timing = SDIRenderTiming()
    private var unavailable: Set<String> = []
    private var problems: [String] = []

    init(width: Int, height: Int, ringSize: Int, sceneProvider: @escaping SceneProvider,
         videoSource: (any VideoSourceFactory)?, mediaSource: (any MediaFrameSource)?) {
        self.width = width
        self.height = height
        self.sceneProvider = sceneProvider
        self.videoSource = videoSource
        self.mediaSource = mediaSource
        self.ring = (0..<max(2, ringSize)).map { _ in [UInt8](repeating: 0, count: width * height * 4) }
    }

    var renderTiming: SDIRenderTiming { readoutLock.withLock { timing } }
    var bufferReallocations: Int { readoutLock.withLock { reallocations } }
    func resetTiming() { readoutLock.withLock { timing = SDIRenderTiming() } }
    var lastError: String? { readoutLock.withLock { failed } }
    var sceneIsOpaque: Bool { readoutLock.withLock { lastSceneOpaque } }
    var unavailableImagePaths: Set<String> { readoutLock.withLock { unavailable } }
    var renderProblems: [String] { readoutLock.withLock { problems } }

    /// The frame for the next slot, or nil when it could not be drawn (the session then repeats the last frame).
    func frame() -> SDIFrame? {
        lock.lock(); defer { lock.unlock() }
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            try prepareIfNeeded()
            guard let compositor, let texture else { return nil }
            var scene = sceneProvider()
            let opaque = SDIOutput.isOpaque(scene)
            readoutLock.withLock { lastSceneOpaque = opaque }
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
            let copied = encodeReadback(of: texture, on: cb)
            cb.commit()
            cb.waitUntilCompleted()
            withExtendedLifetime(media.hold) {}
            if let error = cb.error { throw RenderError.pipeline("\(error)") }
            let slot = nextSlot
            nextSlot = (nextSlot + 1) % ring.count
            read(texture, into: slot, copied: copied)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let paths = compositor.unavailableImagePaths, issues = compositor.renderProblems, again = ringReallocations
            readoutLock.withLock {
                failed = nil
                timing.frames += 1
                timing.totalMs += elapsed
                timing.worstMs = max(timing.worstMs, elapsed)
                unavailable = paths
                problems = issues
                reallocations = again
            }
            return SDIFrame(width: width, height: height, bgra: ring[slot])
        } catch {
            readoutLock.withLock { failed = "\(error)" }
            return nil
        }
    }

    /// Adds a GPU copy of the rendered frame into the shared readback buffer to the frame's command buffer. `getBytes` on the texture itself
    /// costs about 1 ms for a flat picture and about 5 ms for one with a gradient or a photograph (measured with `wf-looks-probe readback`); the
    /// GPU copy and a memory copy cost about 0.2 ms more than the render itself either way. False when the copy could not be encoded, in which
    /// case `read` falls back to `getBytes`.
    private func encodeReadback(of texture: MTLTexture, on commandBuffer: MTLCommandBuffer) -> Bool {
        let length = width * height * 4
        if readbackBuffer == nil { readbackBuffer = texture.device.makeBuffer(length: length, options: .storageModeShared) }
        guard let buffer = readbackBuffer, buffer.length >= length, let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: buffer, destinationOffset: 0, destinationBytesPerRow: width * 4, destinationBytesPerImage: length)
        blit.endEncoding()
        return true
    }

    /// Writes the pixels into the slot's own array. If something (the card, the session) still holds that array the
    /// write copies it first; that is counted, and does not happen in steady state with a ring larger than the frames in flight.
    private func read(_ texture: MTLTexture, into slot: Int, copied: Bool) {
        let before = ring[slot].withUnsafeBufferPointer { $0.baseAddress }
        let w = width, h = height
        let source = copied ? readbackBuffer?.contents() : nil
        ring[slot].withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            if let source { memcpy(base, source, w * h * 4) }
            else { texture.getBytes(base, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0) }
        }
        let after = ring[slot].withUnsafeBufferPointer { $0.baseAddress }
        if before != after { ringReallocations += 1 }
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

/// FIX-C S9: how the card's completion callback gets its next frame from the render thread.
public enum SDIRenderPacing: Sendable, Equatable {
    /// Real operation: the render thread works ahead into a small bounded queue and the callback only takes a finished
    /// frame, repeating the last one (and counting it) when none is ready. The callback never waits.
    case free
    /// Manual clock (tests): the callback asks the render thread for exactly one frame and waits for it, so each
    /// completion shows the scene as it is at that moment. Selected automatically for a simulated card with no clock.
    case lockstep
}

/// FIX-V item 4: how many teardowns are queued and not finished; read on the main actor, changed on the output's queue.
private final class TeardownCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var pending: Int { lock.withLock { count } }
    func begin() { lock.withLock { count += 1 } }
    func end() { lock.withLock { count -= 1 } }
}

@MainActor
public final class SDIOutput: OutputTarget {
    public static let opaqueKeyWarning = "Nothing will key: background is opaque. Give this screen a theme with a transparent background, such as the lower third."

    /// True when a keyed output of this scene would send a key that is white everywhere, so nothing would be keyed out.
    /// Conservative: a background colour with any transparency, and no video, image or media layer behind the text, is not opaque.
    /// FIX-J item 8: a gradient background (drawn over the whole frame, its last colour continuing past the last stop) whose stops are all fully
    /// opaque makes the frame opaque, whatever the colour under it; one with any transparent stop does not.
    public nonisolated static func isOpaque(_ scene: SceneDescription) -> Bool {
        scene.backgroundColor.alpha >= 1 || scene.showsVideo || scene.backgroundImage != nil
            || scene.backgroundMedia != nil || scene.foregroundMedia != nil
            || (scene.backgroundGradient.map { !$0.stops.isEmpty && $0.stops.allSatisfy { $0.color.alpha >= 1 } } ?? false)
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
    private let ahead: SDIRenderAhead
    private let prefill: Int
    private let queue = DispatchQueue(label: "WorshipFlow.sdi.start", qos: .userInteractive)
    private var clockRunning = false
    /// FIX-V item 4: stops queued on `queue` that have not finished.
    private let teardowns = TeardownCounter()
    private var lostDevice = false

    /// - Parameters:
    ///   - clock: drives the card's completions in real time. Nil leaves the clock to the caller (tests use a manual one).
    ///   - prerollFrames, maxBufferedFrames: the session's buffering; the frame ring is sized from them.
    public init(name: String, port: any SDIOutputPort, mode: SDIVideoMode, keying: SDIKeying, isSimulated: Bool,
                sceneProvider: @escaping SceneProvider, videoSource: (any VideoSourceFactory)? = nil,
                mediaSource: (any MediaFrameSource)? = nil, clock: (any SDIOutputClock)? = nil,
                prerollFrames: Int = 3, maxBufferedFrames: Int = 5, renderPacing: SDIRenderPacing? = nil) {
        self.name = name
        self.port = port
        self.mode = mode
        self.keying = keying
        self.isSimulated = isSimulated
        self.clock = clock
        // FIX-C S9: the queue holds the preroll (at least 3) frames; the ring covers those, the card's buffer, the session's
        // last frame and the one being drawn, so steady state allocates nothing.
        // FIX-C S11: the preroll is the larger of the caller's (3 by default) and the device's own minimum, and the card's
        // buffer cap stays above it.
        let prerollFrames = max(prerollFrames, port.minimumPrerollFrames)
        let maxBufferedFrames = max(maxBufferedFrames, prerollFrames + 2)
        let depth = max(3, prerollFrames)
        let pacing = renderPacing ?? ((isSimulated && clock == nil) ? .lockstep : .free)
        let renderer = SDIFrameRenderer(width: mode.width, height: mode.height, ringSize: max(prerollFrames, maxBufferedFrames) + 5 + depth,
                                        sceneProvider: sceneProvider, videoSource: videoSource, mediaSource: mediaSource)
        self.renderer = renderer
        let ahead = SDIRenderAhead(depth: depth, pacing: pacing, frameInterval: 1.0 / mode.framesPerSecond) { renderer.frame() }
        self.ahead = ahead
        self.prefill = min(depth, max(1, prerollFrames))
        self.session = SDIOutputSession(port: port, mode: mode, keying: keying, prerollFrames: prerollFrames,
                                        maxBufferedFrames: maxBufferedFrames) { _ in ahead.next() }
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
            // FIX-T item 6 (M4): the port was opened (and its connector claimed) before this output was made. A start that fails must not leave
            // it open, or every retry on that connector fails with "unavailable" for a cause that is long gone.
            port.close()
            if case .external = keying { throw SDIError.keyingUnavailable(connector: port.connector) }
            throw SDIError.unsupportedMode(mode.name)
        }
        session.onStop = { [weak self] reason in
            Task { @MainActor in self?.sessionStopped(reason) }
        }
        lostDevice = false
        status = .running
        let session = session, clock = clock, ahead = ahead, prefill = prefill
        queue.async { [weak self] in
            ahead.start(prefill: prefill, timeout: 1)
            do {
                try session.start()
                clock?.start()
                Task { @MainActor in self?.clockStarted() }
            } catch {
                // `onStop` has already reported the failure.
                ahead.stop()
            }
        }
    }

    private func clockStarted() {
        if status == .running { clockRunning = clock != nil } else { clock?.stop() }
    }

    /// Stops the output and returns when its port is closed. The teardown runs on this output's own queue, after any start already queued
    /// there, so a stop never overtakes the start it follows (FIX-T item 6, M6).
    public func stop() { finish(reason: nil, wait: true) }

    /// FIX-T item 6 (M6): the same, without waiting: the main actor is not held for the teardown (up to about a second per output). A new
    /// output on the same connector waits with `waitUntilStopped()` before it opens the port.
    public func stopWithoutWaiting() { finish(reason: nil, wait: false) }

    /// Returns when every start and stop queued on this output has finished.
    public func waitUntilStopped() { queue.sync {} }

    /// FIX-V item 4: told (on the main actor) when a teardown has finished; the coordinator lets go of the output then.
    public var onTeardownFinished: (@MainActor () -> Void)?

    /// FIX-V item 4: a teardown queued by `finish` has not run to its end yet.
    public var isTearingDown: Bool { teardowns.pending > 0 }

    /// Tests: returns when the work `start()` queued has finished, so the first frames are scheduled.
    func waitUntilStarted() { queue.sync {} }

    private func sessionStopped(_ reason: SDIStopReason) {
        guard status == .running else { return }
        switch reason {
        case .requested: finish(reason: nil, wait: false)
        case .failed(let error):
            lostDevice = error == .deviceDisconnected
            finish(reason: error.description, wait: false)
        }
    }

    private func finish(reason: String?, wait: Bool) {
        guard status == .running else { return }
        status = .stopped(reason: reason)
        session.onStop = nil
        // FIX-T item 6 (M6): the teardown is queued behind any start still under way on the same serial queue, so the order is the order
        // requested; it used to stop the session first, so a start not yet run could enable the port after the stop.
        let session = session, ahead = ahead, port = port, clock = clock
        let stopClock = clockRunning
        clockRunning = false
        teardowns.begin()
        let teardowns = teardowns
        queue.async { [weak self] in
            session.stop()
            ahead.stop()
            port.close()
            if stopClock { clock?.stop() }
            teardowns.end()
            Task { @MainActor [weak self] in self?.onTeardownFinished?() }
        }
        if wait { queue.sync {} }
    }
}
