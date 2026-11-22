// FIX-T item 6 (HW-002, HW-003): the SDI output path against the SIMULATED card only. Nothing here is Hardware Verified.
//  M4: a start that fails closes its port, so a retry on the same connector can open it.
//  M6: a stop is queued behind a start under way (it never overtakes it), and begins without holding the main actor.
//  M5: the operator window's readouts of the frame renderer never wait for a frame that is being drawn.
// No wall-clock assertions: a held call is released by the test itself; a fallback release only keeps a regression from hanging the run.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

/// Forwards to a simulated port, records the calls that matter in order, and can hold `enable` until released.
final class FIXTPort: SDIOutputPort, @unchecked Sendable {
    private let inner: SimulatedSDIOutputPort
    private let lock = NSLock()
    private var _events: [String] = []
    private var _inEnable = false
    private var gate: DispatchSemaphore?
    init(_ inner: SimulatedSDIOutputPort, holdEnable: Bool = false) {
        self.inner = inner
        if holdEnable { gate = DispatchSemaphore(value: 0) }
    }
    var events: [String] { lock.withLock { _events } }
    var isInsideEnable: Bool { lock.withLock { _inEnable } }
    func releaseEnable() { lock.withLock { gate }?.signal() }
    private func note(_ e: String) { lock.withLock { _events.append(e) } }

    var minimumPrerollFrames: Int { 0 }
    var connector: Int { inner.connector }
    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { inner.supports(mode: mode, keying: keying) }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws {
        note("enable")
        lock.withLock { _inEnable = true }
        let g = lock.withLock { gate }
        g?.wait()
        try inner.enable(mode: mode, keying: keying)
    }
    func disable() { note("disable"); inner.disable() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws { note("schedule"); try inner.schedule(frame, atFrame: frameIndex) }
    func startPlayback(atFrame frameIndex: Int64) { note("startPlayback"); inner.startPlayback(atFrame: frameIndex) }
    func stopPlayback() { note("stopPlayback"); inner.stopPlayback() }
    func close() { note("close"); inner.close() }
    var bufferedFrameCount: Int { inner.bufferedFrameCount }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? {
        get { inner.onFrameCompleted } set { inner.onFrameCompleted = newValue }
    }
    var onFailure: (@Sendable (SDIError) -> Void)? {
        get { inner.onFailure } set { inner.onFailure = newValue }
    }
}

final class FIXTFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _set = false
    func set() { lock.withLock { _set = true } }
    var isSet: Bool { lock.withLock { _set } }
}

final class FIXTFrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _frame: SDIFrame?
    func set(_ f: SDIFrame?) { lock.withLock { _frame = f } }
    var frame: SDIFrame? { lock.withLock { _frame } }
}

private let plainScene: SceneDescription = SceneDescription(backgroundColor: .black, textLayers: [])

@MainActor
@Suite(.serialized) struct FIXT_SDILifecycleTests {
    // MARK: M4

    @Test func aStartThatFailsClosesThePortSoTheConnectorCanBeOpenedAgain() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let out = SDIOutput(name: "x", port: try device.openOutput(connector: 2), mode: .hd1080p5994, keying: .external(fillAlphaMode: .premultiplied),
                            isSimulated: true, sceneProvider: { plainScene })
        #expect(throws: SDIError.self) { try out.start() }                 // keying on an even connector: the card refuses
        #expect(out.status != .running)
        // Before the fix this threw `connectorUnavailable`: the refused output never gave the connector back.
        let again = try device.openOutput(connector: 2)
        again.close()
    }

    @Test func aRefusedModeAlsoGivesTheConnectorBack() throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let odd = SDIVideoMode(width: 640, height: 480, frameDurationValue: 1000, timeScale: 30000, name: "480p30")
        let out = SDIOutput(name: "x", port: try device.openOutput(connector: 1), mode: odd, keying: .none, isSimulated: true, sceneProvider: { plainScene })
        #expect(throws: SDIError.self) { try out.start() }
        let again = try device.openOutput(connector: 1)
        again.close()
    }

    @Test func startFailStartAgainSucceedsOnTheSameConnector() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let failing = SDIOutput(name: "keyed", port: try device.openOutput(connector: 2), mode: .hd1080p5994,
                                keying: .external(fillAlphaMode: .premultiplied), isSimulated: true, sceneProvider: { plainScene })
        #expect(throws: SDIError.self) { try failing.start() }
        let plain = SDIOutput(name: "plain", port: try device.openOutput(connector: 2), mode: .hd1080p5994, keying: .none, isSimulated: true,
                              sceneProvider: { plainScene })
        try plain.start()
        plain.waitUntilStarted()
        #expect(plain.status == .running)
        plain.stop()
    }

    // MARK: M6

    @Test func aStopBegunWhileAStartIsStillUnderWayDoesNotWaitForItAndRunsAfterIt() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = FIXTPort(try device.openOutput(connector: 1), holdEnable: true)
        let out = SDIOutput(name: "x", port: port, mode: .hd1080p5994, keying: .none, isSimulated: true, sceneProvider: { plainScene })
        try out.start()                                                    // queues the start; the port holds it inside `enable`
        #expect(await waitFor { port.isInsideEnable })
        // If this waited for the start, the test would hang: the fallback below only keeps such a regression from stopping the run.
        let fired = FIXTFlag()
        let fallback = Task.detached { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { fired.set(); port.releaseEnable() } }
        out.stopWithoutWaiting()
        #expect(out.status == .stopped(reason: nil), "the output reads as stopped at once")
        #expect(port.events == ["enable"], "nothing was torn down yet: the stop is queued behind the start")
        port.releaseEnable()
        out.waitUntilStopped()
        fallback.cancel()
        #expect(!fired.isSet, "stopWithoutWaiting() waited for the start")
        let events = port.events
        #expect(events.first == "enable" && events.last == "close", "\(events)")
        // Nothing was scheduled or played after the port was closed, and the port is free again.
        #expect(events.firstIndex(of: "close") == events.indices.last, "\(events)")
        let again = try device.openOutput(connector: 1)
        again.close()
    }

    @Test func stopStillReturnsOnlyWhenThePortIsClosed() async throws {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let out = SDIOutput(name: "x", port: try device.openOutput(connector: 1), mode: .hd1080p5994, keying: .none, isSimulated: true,
                            sceneProvider: { plainScene })
        try out.start(); out.waitUntilStarted()
        out.stop()
        let again = try device.openOutput(connector: 1)                    // closed by the time stop() returned
        again.close()
    }

    @Test func aStopWithoutWaitingIsFollowedByAnOutputOnTheSameConnectorOnceItHasWaited() async throws {
        let h = SDIHarness([ScreenProfile(name: "Program", role: .broadcast, destination: sdiDest(1))])
        let id = try #require(h.coordinator.readouts().first?.id)
        h.coordinator.start(); h.settle()
        for round in 1...5 {
            h.coordinator.restart(id)                                       // stops without waiting, then opens the same connector again
            h.settle()
            #expect(h.readout(id)?.state == .running, "round \(round): \(String(describing: h.readout(id)?.state))")
        }
        h.coordinator.stop()
    }

    // MARK: M5

    @Test func theRendererReadoutsDoNotWaitForAFrameThatIsBeingDrawn() throws {
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        let renderer = SDIFrameRenderer(width: 64, height: 36, ringSize: 4, sceneProvider: {
            entered.signal()
            release.wait()                                                  // inside `frame()`, with its render lock held
            return plainScene
        }, videoSource: nil, mediaSource: nil)
        let result = FIXTFrameBox()
        DispatchQueue.global().async { result.set(renderer.frame()); done.signal() }
        entered.wait()
        let fired = FIXTFlag()
        // Only so a regression ends by itself: if a readout waits for the frame, this releases it after a while and the check below fails.
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { fired.set(); release.signal() }
        // Each of these is read on the main actor by the operator window. Before the fix every one waited for the frame.
        _ = renderer.lastError
        _ = renderer.renderTiming
        _ = renderer.sceneIsOpaque
        _ = renderer.unavailableImagePaths
        _ = renderer.renderProblems
        _ = renderer.bufferReallocations
        let waited = fired.isSet
        release.signal()
        done.wait()
        #expect(!waited, "a readout waited for the frame being drawn")
        #expect(result.frame != nil)
        #expect(renderer.renderTiming.frames == 1, "the readout shows the finished frame")
        #expect(renderer.lastError == nil)
    }
}
