// OUT-001: shared implementation of a window-backed output: CAMetalLayer view, display link on a render
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

final class DisplayLinkTarget: NSObject {
    private let handler: @Sendable () -> Void
    init(handler: @escaping @Sendable () -> Void) { self.handler = handler }
    @objc func fire(_ link: CADisplayLink) { handler() }
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
    private var window: NSWindow?
    private var view: MetalLayerView?
    private var renderer: OutputRenderer?
    private var thread: RunLoopThread?
    private var link: CADisplayLink?
    private var linkTarget: DisplayLinkTarget?
    private var observers: [NSObjectProtocol] = []

    init(name: String, sceneProvider: @escaping SceneProvider, videoSource: (any VideoSourceFactory)?) {
        self.name = name
        self.sceneProvider = sceneProvider
        self.videoSource = videoSource
    }

    public var statistics: FrameStatistics { renderer?.statistics ?? FrameStatistics(targetInterval: 1.0 / 60.0) }
    public var isOccluded: Bool {
        guard status == .running, let w = window else { return false }
        return !w.occlusionState.contains(.visible)
    }
    public var lastRenderError: String? { renderer?.lastError }
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
                                      targetInterval: 1.0 / refreshRate)
        do {
            try renderer.prepare()
        } catch {
            window.orderOut(nil)
            throw error
        }

        let thread = RunLoopThread()
        thread.start(name: "WorshipFlow.render.\(name)")
        let target = DisplayLinkTarget { [weak renderer] in renderer?.tick() }
        let link = view.displayLink(target: target, selector: #selector(DisplayLinkTarget.fire(_:)))
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
        observers.append(nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.status == .running else { return }
                if let problem = self.availabilityProblem() { self.finish(reason: problem) }
                else if let screen = self.window?.screen {
                    self.refreshRate = Double(screen.maximumFramesPerSecond)
                    if self.refreshRate > 0 { self.renderer?.setTargetInterval(1.0 / self.refreshRate) }
                }
            }
        })
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
