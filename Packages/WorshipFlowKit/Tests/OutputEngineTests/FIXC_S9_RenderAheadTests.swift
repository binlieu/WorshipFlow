// FIX-C / S9 (HW-002): SDI outputs render ahead on their own thread into a small bounded queue; the card's completion
// callback only takes a finished frame. Simulated: the card is a simulator and its "callback thread" is whichever thread
// calls `advance`. Nothing here is Hardware Verified.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

/// Records which threads called the scene provider (the first thing the renderer does for every frame).
final class ThreadLog: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [pthread_t] = []
    private var names: [String] = []
    private var count = 0
    func record() {
        lock.lock(); defer { lock.unlock() }
        count += 1
        let me = pthread_self()
        if !ids.contains(where: { pthread_equal($0, me) != 0 }) { ids.append(me); names.append(Thread.current.name ?? "") }
    }
    var calls: Int { lock.withLock { count } }
    var threadCount: Int { lock.withLock { ids.count } }
    var threadNames: [String] { lock.withLock { names } }
    func calledFrom(_ thread: pthread_t) -> Bool { lock.withLock { ids.contains { pthread_equal($0, thread) != 0 } } }
}

/// Which thread is advancing the card: that is the SDK's callback thread in these tests.
final class CallbackThreadMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var thread: pthread_t?
    func mark() { lock.withLock { thread = pthread_self() } }
    var value: pthread_t? { lock.withLock { thread } }
}

private func solid(_ r: Double, _ g: Double, _ b: Double) -> SceneDescription {
    SceneDescription(backgroundColor: ColorRGBA(red: r, green: g, blue: b), textLayers: [])
}

@MainActor
@Suite(.serialized) struct FIXC_S9_RenderAheadTests {
    private func output(_ device: SimulatedSDIDevice, connector: Int, pacing: SDIRenderPacing?, clock: (any SDIOutputClock)? = nil,
                        scene: @escaping @Sendable () -> SceneDescription) throws -> SDIOutput {
        let port = try device.openOutput(connector: connector)
        return SDIOutput(name: "S9-\(connector)", port: port, mode: .hd1080p5994, keying: .none, isSimulated: true,
                         sceneProvider: scene, clock: clock, renderPacing: pacing)
    }

    /// The completion callback does not render: the scene provider (called once per rendered frame) never runs on the
    /// thread that delivers completions, in either pacing, and runs on the output's own render thread.
    @Test(arguments: [SDIRenderPacing.free, SDIRenderPacing.lockstep])
    func theCallbackPathDoesNoRendering(pacing: SDIRenderPacing) async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let log = ThreadLog()
        let marker = CallbackThreadMarker()
        let out = try output(device, connector: 1, pacing: pacing) { log.record(); return solid(0, 0.4, 0) }
        try out.start(); out.waitUntilStarted()
        await Task.detached { marker.mark(); device.advance(frames: 60) }.value
        let callbackThread = try #require(marker.value)
        #expect(log.calls > 0)
        #expect(!log.calledFrom(callbackThread), "a frame was rendered on the SDK callback thread")
        #expect(!log.calledFrom(pthread_self()), "a frame was rendered on the main thread")
        #expect(log.threadNames.allSatisfy { $0 == "WorshipFlow.sdi.render" }, "rendered on \(log.threadNames)")
        out.stop()
    }

    /// A renderer slower than the frame period gives repeated frames, never late or dropped ones.
    @Test func aSlowRendererCausesRepeatsNotLateFrames() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let out = try output(device, connector: 1, pacing: .free) { Thread.sleep(forTimeInterval: 0.03); return solid(0, 0, 0.5) }
        try out.start(); out.waitUntilStarted()
        await advanceOffMain(device, frames: 90)
        let s = out.statistics
        let report = try #require(out.sdiReport)
        #expect(s.presentedFrames == 90)
        #expect(s.lateFrames == 0 && s.droppedFrames == 0)
        #expect(report.repeatedFrames > 30, "expected repeats from a 30 ms renderer against a fast clock, got \(report.repeatedFrames)")
        #expect(report.health == .ok)
        out.stop()
    }

    /// Acceptance for the new path: 600 frames, zero late and zero dropped, and no buffer allocated in steady state.
    @Test func sixHundredFramesInFreePacingHaveZeroLateAndZeroDropped() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let out = try output(device, connector: 1, pacing: .free) { lowerThirdScene() }
        try out.start(); out.waitUntilStarted()
        await advanceOffMain(device, frames: 600)
        let s = out.statistics
        #expect(s.presentedFrames == 600)
        #expect(s.droppedFrames == 0 && s.lateFrames == 0)
        #expect(out.bufferReallocations == 0)
        #expect(out.renderTiming.frames > 0)
        let shown = try #require(device.lastDisplayed(onConnector: 1))
        #expect(shown.pixel(960, 800).r == 255)                 // a real rendered frame, not the black fallback
        out.stop()
    }

    /// Four outputs share nothing mutable: each has its own render thread, queue and buffers, and each connector shows
    /// its own scene.
    @Test func fourOutputsShareNothingMutable() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let colours: [(Double, Double, Double)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]
        let logs = (0..<4).map { _ in ThreadLog() }
        var outs: [SDIOutput] = []
        for c in 1...4 {
            let (r, g, b) = colours[c - 1]
            let log = logs[c - 1]
            outs.append(try output(device, connector: c, pacing: .free) { log.record(); return solid(r, g, b) })
        }
        for o in outs { try o.start(); o.waitUntilStarted() }
        await advanceOffMain(device, frames: 40)
        for (i, o) in outs.enumerated() {
            let p = try #require(device.lastDisplayed(onConnector: i + 1)).pixel(100, 100)
            let (r, g, b) = colours[i]
            #expect(abs(p.r - Int(r * 255)) <= 2 && abs(p.g - Int(g * 255)) <= 2 && abs(p.b - Int(b * 255)) <= 2, "output \(i + 1) shows \(p)")
            #expect(logs[i].threadCount == 1)
            #expect(o.statistics.lateFrames == 0 && o.statistics.droppedFrames == 0)
        }
        // Distinct render threads: no two outputs share one.
        for i in 0..<4 { for j in (i + 1)..<4 { #expect(logs[i].threadNames.count == 1 && logs[j].threadNames.count == 1) } }
        for o in outs { o.stop() }
    }

    /// Stopping while the render thread is in the middle of a frame returns, leaves no thread rendering, and the output can start again.
    @Test func stopWhileTheRenderThreadIsMidFrameIsClean() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let log = ThreadLog()
        let slow = Slow()
        let out = try output(device, connector: 1, pacing: .free) { log.record(); slow.pause(); return solid(0.2, 0.2, 0.2) }
        try out.start(); out.waitUntilStarted()
        #expect(await waitFor { log.calls >= 2 })
        slow.delay = 0.25                                                     // the next frame takes a quarter second
        try await Task.sleep(for: .milliseconds(60))                          // the thread is now inside that frame
        let began = Date()
        out.stop()
        #expect(Date().timeIntervalSince(began) < 2, "stop() did not return promptly")
        #expect(out.status == .stopped(reason: nil))
        let after = log.calls
        try await Task.sleep(for: .milliseconds(400))
        #expect(log.calls == after, "the render thread kept rendering after stop()")
        slow.delay = 0
        // The stopped output's port is closed; starting again means a new output on the same connector.
        let again = try output(device, connector: 1, pacing: .free) { log.record(); slow.pause(); return solid(0.2, 0.2, 0.2) }
        try again.start(); again.waitUntilStarted()
        #expect(await waitFor { log.calls > after })
        await advanceOffMain(device, frames: 5)
        #expect(again.statistics.presentedFrames >= 5)
        again.stop()
    }

    /// Unplugging the card while rendering ahead: the output stops with the reason and the render thread ends.
    @Test func anUnplugEndsTheRenderThread() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let log = ThreadLog()
        let out = try output(device, connector: 1, pacing: .free) { log.record(); return solid(0.2, 0.2, 0.2) }
        try out.start(); out.waitUntilStarted()
        await advanceOffMain(device, frames: 10)
        device.simulateUnplug()
        #expect(await waitFor { out.status != .running })
        #expect(out.stoppedByDeviceLoss)
        let after = log.calls
        try await Task.sleep(for: .milliseconds(200))
        #expect(log.calls == after, "the render thread kept rendering after the card was unplugged")
    }

    /// Real time: the simulated clock drives completions at the mode's rate, the render thread keeps ahead of it, and a
    /// light scene is shown without late or dropped frames and without a run of repeats.
    @Test func aRealTimeClockIsKeptAheadOf() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let clock = SimulatedClockDriver(device: device, mode: .hd1080p5994)
        let out = try output(device, connector: 1, pacing: .free, clock: clock) { lowerThirdScene() }
        try out.start(); out.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(1500))
        let s = out.statistics
        let report = try #require(out.sdiReport)
        out.stop()
        #expect(s.presentedFrames >= 50, "only \(s.presentedFrames) frames in 1.5 s")
        #expect(s.lateFrames == 0 && s.droppedFrames == 0)
        #expect(report.repeatedFrames * 2 <= s.presentedFrames, "\(report.repeatedFrames) of \(s.presentedFrames) frames were repeats")
    }

    /// The queue is bounded: with nobody taking frames the renderer stops at the depth, it does not run away.
    @Test func theQueueIsBounded() async throws {
        let rendered = Counter()
        let ahead = SDIRenderAhead(depth: 3, pacing: .free, frameInterval: 0.016) { rendered.bump(); return SDIFrame(width: 1, height: 1, bgra: [0, 0, 0, 255]) }
        ahead.start(prefill: 0, timeout: 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(rendered.value == 3)
        #expect(ahead.next() != nil)                                          // taking one lets exactly one more be rendered
        try await Task.sleep(for: .milliseconds(100))
        #expect(rendered.value == 4)
        ahead.stop()
    }

    /// An empty queue answers nil at once (the session turns that into a repeat); it never waits in free pacing.
    @Test func anEmptyQueueAnswersAtOnceInFreePacing() async throws {
        let ahead = SDIRenderAhead(depth: 2, pacing: .free, frameInterval: 0.016) { Thread.sleep(forTimeInterval: 0.5); return SDIFrame(width: 1, height: 1, bgra: [0, 0, 0, 255]) }
        ahead.start(prefill: 0, timeout: 0)
        let began = Date()
        #expect(ahead.next() == nil)
        #expect(Date().timeIntervalSince(began) < 0.1)
        ahead.stop()
    }
}

final class Slow: @unchecked Sendable {
    private let lock = NSLock(); private var d = 0.0
    var delay: Double { get { lock.withLock { d } } set { lock.withLock { d = newValue } } }
    func pause() { let v = delay; if v > 0 { Thread.sleep(forTimeInterval: v) } }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func bump() { lock.withLock { n += 1 } }
    var value: Int { lock.withLock { n } }
}

/// Four simulated outputs at 1080p59.94 in free pacing, as in real operation: what the callback thread spends per
/// completion (the whole `advance` call, which runs four completions' worth of scheduling) against what the render
/// threads spend. Prints the numbers; asserts only a generous ceiling. Simulated: not a measurement of any real card.
@MainActor
@Suite(.serialized) struct FIXC_S9_FreePacingBenchmarkTests {
    @Test func theCallbackPathStaysCheapWithFourOutputsRenderingAhead() async throws {
        var state = ShowState()
        state.apply(.load(ShowDeck(presentationID: UUID(), slides: [
            SlideContent(primary: "Amazing grace, how sweet the sound", secondary: "Ân điển lạ lùng thay, tiếng ca sao ngọt ngào"),
        ])))
        state.apply(.trigger(index: 0))
        let scenes = [ScreenRole.audience, .stage, .broadcast, .audience].map { SceneComposer.scene(for: $0, state: state, clockText: "10:32") }
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        var outs: [SDIOutput] = []
        for c in 1...4 {
            let scene = scenes[c - 1]
            let port = try device.openOutput(connector: c)
            outs.append(SDIOutput(name: "free\(c)", port: port, mode: .hd1080p5994, keying: .none, isSimulated: true,
                                  sceneProvider: { scene }, renderPacing: .free))
        }
        for o in outs { try o.start(); o.waitUntilStarted() }
        await advanceOffMain(device, frames: 10)
        for o in outs { o.resetRenderTiming() }
        let frames = 600
        let times: [Double] = await Task.detached {
            var times: [Double] = []
            for _ in 0..<frames {
                let start = DispatchTime.now().uptimeNanoseconds
                device.advance(frames: 1)
                times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return times
        }.value
        let mean = times.reduce(0, +) / Double(frames)
        let p99 = times.sorted()[Int(Double(frames) * 0.99)]
        let timings = outs.map(\.renderTiming)
        let late = outs.reduce(0) { $0 + $1.statistics.lateFrames }, dropped = outs.reduce(0) { $0 + $1.statistics.droppedFrames }
        let repeats = outs.reduce(0) { $0 + ($1.sdiReport?.repeatedFrames ?? 0) }
        print(String(format: "FIX-C S9 BENCHMARK [free pacing] four 1920x1080 1080p59.94 outputs, %d frames: callback path per frame (all four outputs): mean %.3f ms, p99 %.3f ms, worst %.3f ms; render threads: %d frames rendered, mean %.3f ms, worst %.3f ms per frame; late %d, dropped %d, repeated %d (the clock here runs as fast as it can, so repeats are expected)",
                     frames, mean, p99, times.max() ?? 0, timings.map(\.frames).reduce(0, +), timings.map(\.meanMs).reduce(0, +) / 4,
                     timings.map(\.worstMs).max() ?? 0, late, dropped, repeats))
        #expect(mean < 4.0, "the callback path should only take finished frames")
        #expect(late == 0 && dropped == 0)
        for o in outs { o.stop() }
    }
}
