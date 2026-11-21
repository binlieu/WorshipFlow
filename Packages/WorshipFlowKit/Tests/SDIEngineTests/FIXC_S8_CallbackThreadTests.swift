// FIX-C / S8 (HW-001, HW-003): no SDK stop, disable or close call is made from inside an SDK callback thread.
// A real SDK may wait for callbacks to return inside StopScheduledPlayback / DisableVideoOutput, so calling them from a
// callback would deadlock. The fake port below plays the SDK: it runs its handlers on its own thread, and records, for
// every stop/disable/close, whether it came from that thread while a handler was running. Simulated; no card involved.
import Testing
import Foundation
@testable import SDIEngine

/// A port whose handlers run on one dedicated thread, like an SDK's callback thread. A teardown call made from inside
/// a handler is recorded as a violation (a real SDK might hang there; the fake never blocks, so a failing test fails
/// by assertion instead of by timeout).
final class CallbackThreadPort: SDIOutputPort, @unchecked Sendable {
    let connector = 1
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(label: "fake.sdk.callback")
    private var insideCallbackOn: pthread_t?
    private var completionHandler: (@Sendable (SDIFrameCompletion) -> Void)?
    private var failureHandler: (@Sendable (SDIError) -> Void)?
    private var scheduledCount = 0
    private(set) var failScheduleAt: Int?
    private var _violations: [String] = []
    private var _teardown: [String] = []
    private let torn = DispatchSemaphore(value: 0)

    init(failScheduleAt: Int? = nil) { self.failScheduleAt = failScheduleAt }

    var violations: [String] { lock.withLock { _violations } }
    var teardownCalls: [String] { lock.withLock { _teardown } }
    /// Waits (with a watchdog) until `disable()` has been called by somebody.
    func waitForDisable(timeout: TimeInterval = 3) -> Bool { torn.wait(timeout: .now() + timeout) == .success }

    private func noteTeardown(_ what: String) {
        lock.withLock {
            _teardown.append(what)
            if let on = insideCallbackOn, pthread_equal(on, pthread_self()) != 0 { _violations.append(what) }
        }
    }

    /// Runs `body` on the callback thread, marked as "inside a callback".
    func onCallbackThread(_ body: @escaping @Sendable () -> Void) {
        callbackQueue.sync {
            lock.withLock { insideCallbackOn = pthread_self() }
            body()
            lock.withLock { insideCallbackOn = nil }
        }
    }

    func complete(_ index: Int64, _ result: SDICompletionResult = .completed) {
        let handler = lock.withLock { completionHandler }
        onCallbackThread { handler?(SDIFrameCompletion(frameIndex: index, result: result)) }
    }

    func failFromSDK(_ error: SDIError) {
        let handler = lock.withLock { failureHandler }
        onCallbackThread { handler?(error) }
    }

    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { true }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws {}
    func disable() { noteTeardown("disable"); torn.signal() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws {
        let n = lock.withLock { () -> Int in scheduledCount += 1; return scheduledCount }
        if let failScheduleAt, n >= failScheduleAt { throw SDIError.hardwareFault(detail: "fake schedule failure") }
    }
    func startPlayback(atFrame frameIndex: Int64) {}
    func stopPlayback() { noteTeardown("stopPlayback") }
    func close() { noteTeardown("close") }
    var bufferedFrameCount: Int { 0 }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? {
        get { lock.withLock { completionHandler } }
        set { lock.withLock { completionHandler = newValue } }
    }
    var onFailure: (@Sendable (SDIError) -> Void)? {
        get { lock.withLock { failureHandler } }
        set { lock.withLock { failureHandler = newValue } }
    }
}

@Suite struct FIXC_S8_CallbackThreadTests {
    private func frame() -> SDIFrame { SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 1, 2, 3, 255]) }

    /// A schedule failure found inside a completion callback must not stop the card from that same callback.
    @Test func aScheduleFailureInsideACompletionFinishesOffTheCallbackThread() throws {
        let port = CallbackThreadPort(failScheduleAt: 5)      // preroll takes 3 calls; the 5th is in the second completion
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 1, 2, 3, 255]) }
        try session.start()
        port.complete(0)
        port.complete(1)
        #expect(port.waitForDisable(), "the session never finished tearing the port down")
        #expect(port.violations.isEmpty, "stop/disable called from inside an SDK callback: \(port.violations)")
        #expect(session.state == .stopped(.failed(.hardwareFault(detail: "fake schedule failure"))))
        session.stop()
        #expect(port.teardownCalls.contains("stopPlayback") && port.teardownCalls.contains("disable"))
    }

    /// A device removal reported from the SDK's thread: same rule.
    @Test func aRemovalReportedFromTheCallbackThreadFinishesOffThatThread() throws {
        let port = CallbackThreadPort()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 1, 2, 3, 255]) }
        try session.start()
        port.failFromSDK(.deviceDisconnected)
        #expect(session.state == .stopped(.failed(.deviceDisconnected)))     // marked at once, in the callback
        #expect(port.waitForDisable())
        #expect(port.violations.isEmpty, "stop/disable called from inside an SDK callback: \(port.violations)")
    }

    /// `stop()` after a failure still returns only once the hop has finished, so the owner may close the port next.
    @Test func stopAfterAFailureWaitsForTheTeardownToFinish() throws {
        let port = CallbackThreadPort()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 1, 2, 3, 255]) }
        try session.start()
        port.failFromSDK(.deviceDisconnected)
        session.stop()
        #expect(port.teardownCalls.contains("disable"), "stop() returned before the port was disabled")
        session.stop()                                                          // idempotent
        #expect(port.teardownCalls.filter { $0 == "disable" }.count == 1)
    }

    /// An ordinary stop by the owner is still synchronous.
    @Test func anOrdinaryStopTearsTheCardDownBeforeReturning() throws {
        let port = CallbackThreadPort()
        let session = SDIOutputSession(port: port, mode: .hd1080p5994) { _ in SDIFrame(width: 2, height: 1, bgra: [1, 2, 3, 255, 1, 2, 3, 255]) }
        try session.start()
        session.stop()
        #expect(port.teardownCalls == ["stopPlayback", "disable"])
        #expect(session.state == .stopped(.requested))
    }
}
