// OUT-001: shared implementation of a window-backed output: CAMetalLayer view, Metal display link (OUT-002e) on a render
// thread, status reporting, and safe shutdown when the window closes or the display disappears.
import AppKit
import QuartzCore
import Domain
import RenderEngine

final class MetalLayerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    var metalLayer: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); syncDrawableSize() }
    override func layout() { super.layout(); syncDrawableSize() }

    func syncDrawableSize() {
        guard let layer = metalLayer else { return }
        let scale = window?.backingScaleFactor ?? 1
        layer.contentsScale = scale
        layer.drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
    }
}

/// OUT-002e: receives the Metal display link's callbacks on the render thread. The drawable comes with the callback, already acquired by the
/// system, so the render thread never waits for the swap queue (`nextDrawable()` waited one whole refresh whenever the queue was one frame deep).
final class MetalLinkTarget: NSObject, CAMetalDisplayLinkDelegate {
    /// Called with the callback's target timestamp, the target presentation timestamp and the drawable (OUT-002d records the times; nothing acts on them).
    private let handler: @Sendable (Double, Double, CAMetalDrawable) -> Void
    init(handler: @escaping @Sendable (Double, Double, CAMetalDrawable) -> Void) { self.handler = handler }
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        handler(update.targetTimestamp, update.targetPresentationTimestamp, update.drawable)
    }
}

@MainActor
open class MetalOutput: OutputTarget {
    public let name: String
    public private(set) var status: OutputStatus = .idle {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: (@MainActor (OutputStatus) -> Void)?
    public private(set) var refreshRate: Double = 0

    private let sceneProvider: SceneProvider
    private let videoSource: (any VideoSourceFactory)?
    private let mediaSource: (any MediaFrameSource)?
    private var window: NSWindow?
    private var view: MetalLayerView?
    private var renderer: OutputRenderer?
    private var thread: RunLoopThread?
    private var link: CAMetalDisplayLink?
    private var linkTarget: MetalLinkTarget?
    private var observers: [NSObjectProtocol] = []

    init(name: String, sceneProvider: @escaping SceneProvider, videoSource: (any VideoSourceFactory)?,
         mediaSource: (any MediaFrameSource)? = nil) {
        self.name = name
        self.sceneProvider = sceneProvider
        self.videoSource = videoSource
        self.mediaSource = mediaSource
    }

    public var statistics: FrameStatistics { renderer?.statistics ?? FrameStatistics(targetInterval: 1.0 / 60.0) }
    public var frameEvents: FrameEventLog { renderer?.frameEvents ?? FrameEventLog(capacity: 0) }
    public var isOccluded: Bool {
        guard status == .running, let w = window else { return false }
        return !w.occlusionState.contains(.visible)
    }
    public var lastRenderError: String? { renderer?.lastError }
    public var unavailableImagePaths: [String] { (renderer?.unavailableImagePaths ?? []).sorted() }
    public var renderProblems: [String] { renderer?.renderProblems ?? [] }
    public var diagnostics: String {
        let c = renderer?.counters ?? (ticks: 0, submitted: 0)
        var text = "ticks \(c.ticks), submitted \(c.submitted)"
        if let w = window {
            let f = w.frame
            text += ", window \(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))x\(Int(f.height)) visible \(w.isVisible) occluded \(!w.occlusionState.contains(.visible)) screen \(w.screen?.localizedName ?? "none") level \(w.level.rawValue)"
        }
        if let l = view?.metalLayer { text += ", drawable \(Int(l.drawableSize.width))x\(Int(l.drawableSize.height))" }
        return text
    }

    // Hooks for subclasses.
    func makeWindow() -> NSWindow { fatalError("subclass must override makeWindow()") }
    /// Returns a reason if the output can no longer be shown (for example its display was unplugged).
    func availabilityProblem() -> String? { nil }
    var closeReason: String { "The output window was closed." }
    /// Re-checks the window against its display after a screen change and puts it right (R5). Returns a reason when it
    /// cannot be kept where it belongs.
    func reconcileGeometry() -> String? { nil }
    /// The output's window while it runs (for subclasses and tests).
    var outputWindow: NSWindow? { window }
    func syncDrawableSize() { view?.syncDrawableSize() }

    /// The lowest the display link accepts. Measured on a 60 Hz display (OUT-002e): values from 0.5 to 3 gave the same timing, so the system sets the
    /// latency; the value is kept explicit so that the intent (as little delay as possible) does not depend on a default.
    static let preferredFrameLatency: Float = 1

    /// The refresh rate the output runs at, as the display link's frame-rate range.
    static func frameRateRange(hz: Double) -> CAFrameRateRange {
        let f = Float(max(1, hz))
        return CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    public func start() throws {
        guard status != .running else { return }
        let window = makeWindow()
        window.isReleasedWhenClosed = false
        let view = MetalLayerView(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        guard let layer = view.metalLayer else { throw RenderError.resourceCreation("metal layer") }

        window.orderFrontRegardless()
        view.syncDrawableSize()
        let screen = window.screen ?? NSScreen.main
        let hz = Double(screen?.maximumFramesPerSecond ?? 60)
        refreshRate = hz > 0 ? hz : 60

        let renderer = OutputRenderer(layer: layer, sceneProvider: sceneProvider, videoSource: videoSource,
                                      targetInterval: 1.0 / refreshRate, mediaSource: mediaSource)
        do {
            try renderer.prepare()
        } catch {
            window.orderOut(nil)
            throw error
        }

        let thread = RunLoopThread()
        thread.start(name: "WorshipFlow.render.\(name)")
        let target = MetalLinkTarget { [weak renderer] timestamp, presentation, drawable in
            renderer?.tick(linkTimestamp: timestamp, linkTarget: presentation, drawable: drawable)
        }
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = target
        link.preferredFrameLatency = MetalOutput.preferredFrameLatency
        link.preferredFrameRateRange = MetalOutput.frameRateRange(hz: refreshRate)
        if let runLoop = thread.runLoop { link.add(to: runLoop, forMode: .common) }

        self.window = window
        self.view = view
        self.renderer = renderer
        self.thread = thread
        self.link = link
        self.linkTarget = target
        observe(window)
        status = .running
    }

    private func observe(_ window: NSWindow) {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(reason: self?.closeReason) }
        })
        // The window can also land on another display by itself (a display was removed and the system moved it).
        observers.append(nc.addObserver(forName: NSWindow.didChangeScreenNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                if let problem = self.reconcileGeometry() { self.finish(reason: problem) }
                else { self.followScreenRefreshRate() }     // OUT-002f: a window dragged to a display with another rate
            }
        })
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                if let problem = self.availabilityProblem() { self.finish(reason: problem) }
                else if let problem = self.reconcileGeometry() { self.finish(reason: problem) }
                else { self.followScreenRefreshRate() }
            }
        })
    }

    /// OUT-002f (REVIEW-5 L19): the rate of the display the window is on now. The target interval, the link's frame-rate range and `refreshRate` change
    /// together, and only when the rate changed (a window move within one display does nothing).
    private func followScreenRefreshRate() {
        guard let screen = window?.screen, let hz = Self.newRefreshRate(screenMaximum: screen.maximumFramesPerSecond, current: refreshRate) else { return }
        refreshRate = hz
        renderer?.setTargetInterval(1.0 / hz)
        link?.preferredFrameRateRange = MetalOutput.frameRateRange(hz: hz)
    }

    /// The rate to switch to for a display whose maximum is `screenMaximum` frames per second, or nil when the output already runs at it or the display gave none.
    nonisolated static func newRefreshRate(screenMaximum: Int, current: Double) -> Double? {
        let hz = Double(screenMaximum)
        return hz > 0 && hz != current ? hz : nil
    }

    public func stop() { finish(reason: nil) }

    private func finish(reason: String?) {
        guard status == .running else { return }
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        link?.invalidate()
        link = nil
        linkTarget = nil
        renderer?.stop()
        thread?.stop()
        thread = nil
        let w = window
        window = nil
        view = nil
        status = .stopped(reason: reason)
        w?.orderOut(nil)
        w?.close()
    }
}
