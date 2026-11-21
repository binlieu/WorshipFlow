// FIX-A (review findings R2 reporting, R4 canHide, R5, R14): one failing test per defect, written before the fix.
import Testing
import Foundation
import AppKit
import QuartzCore
import Metal
import Domain
import RenderEngine
@testable import OutputEngine

// MARK: R4

@MainActor
@Suite struct OutputWindowPolicyTests {
    private func scene() -> SceneDescription { SceneDescription(backgroundColor: .black, textLayers: []) }

    @Test func windowOutputWindowIsExcludedFromHide() {
        _ = NSApplication.shared
        let output = WindowOutput(sceneProvider: { SceneDescription(backgroundColor: .black, textLayers: []) })
        let window = output.makeWindow()
        #expect(window.canHide == false)
        #expect(window.hidesOnDeactivate == false)
    }

    @Test func displayOutputWindowIsExcludedFromHide() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.main ?? NSScreen.screens.first)
        let output = DisplayOutput(screen: screen, sceneProvider: { SceneDescription(backgroundColor: .black, textLayers: []) })
        let window = output.makeWindow()
        #expect(window.canHide == false)
        #expect(window.hidesOnDeactivate == false)
        #expect(window.styleMask.contains(.closable) == false)
    }

    @Test func aKeyboardCloseIsIgnoredButTheTitleBarButtonStillWorks() {
        #expect(OutputWindow.allowsClose(during: .keyDown) == false)          // Command-W
        #expect(OutputWindow.allowsClose(during: .leftMouseUp) == true)       // the red button
        #expect(OutputWindow.allowsClose(during: nil) == true)                // a programmatic close
    }
}

// MARK: R5

@Suite struct OutputWindowFitTests {
    let display = DisplayGeometry(id: 7, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))

    @Test func aWindowThatCoversItsDisplayIsLeftAlone() {
        #expect(OutputWindowFit.decide(windowFrame: display.frame, windowDisplayID: 7, target: display, name: "A") == .none)
        let almost = display.frame.insetBy(dx: 0.2, dy: 0.2)                   // rounding only
        #expect(OutputWindowFit.decide(windowFrame: almost, windowDisplayID: 7, target: display, name: "A") == .none)
    }

    @Test func aDisplayThatChangedSizeGetsItsWindowReframed() {
        let old = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(OutputWindowFit.decide(windowFrame: old, windowDisplayID: 7, target: display, name: "A") == .reframe(display.frame))
    }

    @Test func aDisplayThatMovedGetsItsWindowReframed() {
        let old = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        #expect(OutputWindowFit.decide(windowFrame: old, windowDisplayID: 7, target: display, name: "A") == .reframe(display.frame))
    }

    @Test func aWindowOnTheWrongDisplayIsMovedBackThenFaultedIfItStays() {
        // Right frame, wrong display: try once, then give up loudly.
        #expect(OutputWindowFit.decide(windowFrame: display.frame, windowDisplayID: 3, target: display, name: "A") == .reframe(display.frame))
        let verdict = OutputWindowFit.decide(windowFrame: display.frame, windowDisplayID: 3, target: display, name: "Audience", afterReframe: true)
        guard case .fault(let message) = verdict else { Issue.record("expected a fault, got \(verdict)"); return }
        #expect(message.contains("Audience"))
        // A window with no screen at all is the same case.
        #expect(OutputWindowFit.decide(windowFrame: display.frame, windowDisplayID: nil, target: display, name: "A") == .reframe(display.frame))
    }

    @Test func aReframeThatDidNotTakeIsAFault() {
        let stuck = CGRect(x: 0, y: 0, width: 800, height: 600)
        if case .fault = OutputWindowFit.decide(windowFrame: stuck, windowDisplayID: 7, target: display, name: "A", afterReframe: true) {} else {
            Issue.record("a window that is still in the wrong place after a reframe must fault")
        }
    }

    @Test func aMissingDisplayIsAFault() {
        let verdict = OutputWindowFit.decide(windowFrame: display.frame, windowDisplayID: 7, target: nil, name: "Stage")
        guard case .fault(let message) = verdict else { Issue.record("expected a fault, got \(verdict)"); return }
        #expect(message.contains("Stage"))
    }
}

// MARK: R2 reporting

@MainActor
private final class ProblemTarget: OutputTarget {
    let name = "problem target"
    var status: OutputStatus = .running
    var refreshRate = 60.0
    var statistics = FrameStatistics(targetInterval: 1.0 / 60.0)
    var lastRenderError: String?
    var diagnostics = ""
    var onStatusChange: (@MainActor (OutputStatus) -> Void)?
    var renderProblems: [String] = []
    func start() throws { status = .running }
    func stop() { status = .stopped(reason: nil) }
}

@MainActor
@Suite struct RenderProblemReportingTests {
    @Test func theOperatorReadoutCarriesTheOutputsRenderProblems() throws {
        let target = ProblemTarget()
        let profile = ScreenProfile(name: "Audience", role: .audience, destination: .window)
        let coordinator = OutputCoordinator(profiles: [profile],
                                            displays: { DisplaySnapshot(available: [1], operatorDisplay: 1) },
                                            makeTarget: { _, _ in target })
        coordinator.start()
        #expect(coordinator.readouts().first?.renderProblems == [])
        target.renderProblems = ["Text layer skipped (\"Verse 1\"): invalidSize"]
        #expect(coordinator.readouts().first?.renderProblems == ["Text layer skipped (\"Verse 1\"): invalidSize"])
        target.renderProblems = []
        #expect(coordinator.readouts().first?.renderProblems == [])        // cleared when the problem goes away
    }

    /// The render thread end to end, without a window: one impossible layer must not stop the frame.
    @Test func aFrameWithAnImpossibleLayerIsStillSubmitted() throws {
        let layer = CAMetalLayer()
        layer.drawableSize = CGSize(width: 160, height: 90)
        var broken = TextStyle(fontName: "Helvetica Neue", fontSize: 40, color: .white)
        broken.fontSize = 0
        let scene = SceneDescription(backgroundColor: .black, textLayers: [TextLayer(text: "bad", style: broken, frame: .full)],
                                     objectLayers: [.shape(ShapeLayer(shape: .rectangle, fill: .white, frame: .full))])
        let renderer = OutputRenderer(layer: layer, sceneProvider: { scene }, videoSource: nil, targetInterval: 1.0 / 60.0)
        try renderer.prepare()
        guard layer.nextDrawable() != nil else { return }        // no drawables without a display: nothing to show here
        renderer.tick()
        #expect(renderer.lastError == nil)
        #expect(renderer.counters.submitted == 1)
        #expect(renderer.renderProblems.count == 1)
        renderer.stop()
    }
}

// MARK: R14

@Suite struct TextureCacheFlushTests {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 100.0
        var now: Double { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: Double) { lock.lock(); t += s; lock.unlock() }
    }

    @Test func theTextureCacheIsFlushedPeriodicallyNotEveryFrame() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let clock = Clock()
        let resolver = try MediaFrameResolver(source: FakeFrames(), device: device, clock: { clock.now })
        let scene = SceneDescription(backgroundColor: .black, textLayers: [])
        _ = resolver.resolve(scene)
        #expect(resolver.flushCount == 0)
        clock.advance(1.0)
        _ = resolver.resolve(scene)
        #expect(resolver.flushCount == 0)                                    // too soon
        clock.advance(1.5)
        _ = resolver.resolve(scene)
        #expect(resolver.flushCount == 1)
        for _ in 0..<50 { clock.advance(0.01); _ = resolver.resolve(scene) }
        #expect(resolver.flushCount == 1)                                    // not every frame
        clock.advance(2.1)
        _ = resolver.resolve(scene)
        #expect(resolver.flushCount == 2)
    }
}
