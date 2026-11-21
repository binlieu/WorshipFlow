// FIX-C / S11 (HW-003): an SDI output prerolls max(3, the device's minimum) frames before it starts playback.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

/// Forwards to a simulated port, logs the order of scheduling and playback, and reports a device minimum preroll.
final class PrerollRecordingPort: SDIOutputPort, @unchecked Sendable {
    private let inner: SimulatedSDIOutputPort
    private let lock = NSLock()
    private var _events: [String] = []
    private let minimum: Int
    init(_ inner: SimulatedSDIOutputPort, minimum: Int) { self.inner = inner; self.minimum = minimum }
    var events: [String] { lock.withLock { _events } }
    var minimumPrerollFrames: Int { minimum }
    var connector: Int { inner.connector }
    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { inner.supports(mode: mode, keying: keying) }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws { try inner.enable(mode: mode, keying: keying) }
    func disable() { inner.disable() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws {
        lock.withLock { _events.append("schedule") }
        try inner.schedule(frame, atFrame: frameIndex)
    }
    func startPlayback(atFrame frameIndex: Int64) { lock.withLock { _events.append("start") }; inner.startPlayback(atFrame: frameIndex) }
    func stopPlayback() { inner.stopPlayback() }
    func close() { inner.close() }
    var bufferedFrameCount: Int { inner.bufferedFrameCount }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? {
        get { inner.onFrameCompleted } set { inner.onFrameCompleted = newValue }
    }
    var onFailure: (@Sendable (SDIError) -> Void)? {
        get { inner.onFailure } set { inner.onFailure = newValue }
    }
}

@MainActor
@Suite(.serialized) struct FIXC_S11_PrerollTests {
    private func framesScheduledBeforePlayback(minimum: Int) throws -> Int {
        let device = SimulatedSDIDevice(info: .simulatedDuo2)
        let port = PrerollRecordingPort(try device.openOutput(connector: 1), minimum: minimum)
        let out = SDIOutput(name: "S11", port: port, mode: .hd1080p5994, keying: .none, isSimulated: true,
                            sceneProvider: { SceneDescription(backgroundColor: .black, textLayers: []) })
        try out.start(); out.waitUntilStarted()
        defer { out.stop() }
        let events = port.events
        return events.prefix { $0 == "schedule" }.count
    }

    @Test func aDeviceMinimumAboveThreeRaisesThePreroll() throws {
        #expect(try framesScheduledBeforePlayback(minimum: 5) == 5)
        #expect(try framesScheduledBeforePlayback(minimum: 7) == 7)
    }

    @Test func aSmallOrUnknownMinimumKeepsThePrerollAtThree() throws {
        #expect(try framesScheduledBeforePlayback(minimum: 0) == 3)
        #expect(try framesScheduledBeforePlayback(minimum: 2) == 3)
    }
}
