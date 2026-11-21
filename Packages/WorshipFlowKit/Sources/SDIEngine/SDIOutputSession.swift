// HW-001 / SCRN-11, NFR-05: ties an output port, the scheduler and a frame source together.
import Foundation

/// Returns the frame to show at a frame index, or nil when there is no new frame in time.
public typealias SDIFrameProvider = @Sendable (Int64) -> SDIFrame?

public enum SDIStopReason: Equatable, Sendable {
    case requested
    case failed(SDIError)
}

public enum SDISessionState: Equatable, Sendable {
    case idle
    case running
    case stopped(SDIStopReason)
}

public struct SDISessionStatistics: Equatable, Sendable {
    public var scheduler = SDISchedulerStatistics()
    /// Frames where the provider had nothing new and the previous frame was shown again.
    public var repeatedFrames = 0
}

/// Locking: `lock` guards the scheduler, state, statistics and last frame. It is never held while calling
/// the frame provider or the port, so the port may deliver completions from its own thread (the SDK callback
/// thread in a real bridge) and the provider may be slow. The frame provider must not call back into the session.
/// `@unchecked Sendable`: all mutable state is behind `lock`.
public final class SDIOutputSession: @unchecked Sendable {
    private let port: any SDIOutputPort
    private let mode: SDIVideoMode
    private let keying: SDIKeying
    private let frameProvider: SDIFrameProvider

    private let lock = NSLock()
    private var scheduler: SDIScheduler
    private var currentState: SDISessionState = .idle
    private var repeated = 0
    private var lastFrame: SDIFrame?

    public init(port: any SDIOutputPort, mode: SDIVideoMode, keying: SDIKeying = .none,
                prerollFrames: Int = 3, maxBufferedFrames: Int = 5, frameProvider: @escaping SDIFrameProvider) {
        self.port = port
        self.mode = mode
        self.keying = keying
        self.frameProvider = frameProvider
        self.scheduler = SDIScheduler(prerollFrames: prerollFrames, maxBufferedFrames: maxBufferedFrames)
    }

    public var state: SDISessionState { lock.withLock { currentState } }
    public var health: SDIHealth { lock.withLock { scheduler.health } }
    public var statistics: SDISessionStatistics {
        lock.withLock { SDISessionStatistics(scheduler: scheduler.statistics, repeatedFrames: repeated) }
    }
    /// Why the session stopped, if it did.
    public var stopReason: SDIStopReason? {
        lock.withLock { if case .stopped(let reason) = currentState { return reason } else { return nil } }
    }

    /// Enables the port and prerolls. Throws if the port refuses; the session is then stopped with that reason.
    public func start() throws {
        let alreadyRunning = lock.withLock { currentState == .running }
        guard !alreadyRunning else { return }
        do { try port.enable(mode: mode, keying: keying) } catch {
            fail(error)
            throw error
        }
        port.onFrameCompleted = { [weak self] completion in self?.handle(completion) }
        port.onFailure = { [weak self] error in self?.fail(error) }
        let actions: [SDIScheduler.Action] = lock.withLock {
            currentState = .running
            repeated = 0
            lastFrame = nil
            return scheduler.start()
        }
        if let error = perform(actions) { throw error }
    }

    /// Stops playback and releases the handlers. Safe to call at any time, more than once.
    public func stop() { finish(reason: .requested) }

    private func handle(_ completion: SDIFrameCompletion) {
        let buffered = port.bufferedFrameCount     // read before taking our lock: the port has its own
        let actions: [SDIScheduler.Action] = lock.withLock {
            guard currentState == .running else { return [] }
            return scheduler.frameCompleted(completion.result, bufferedFrames: buffered)
        }
        _ = perform(actions)
    }

    /// Runs the scheduler's actions. A failure stops the session and is returned.
    private func perform(_ actions: [SDIScheduler.Action]) -> Error? {
        for action in actions {
            guard state == .running else { return nil }
            do {
                switch action {
                case .schedule(let index):
                    try port.schedule(nextFrame(for: index), atFrame: index)
                case .startPlayback(let index):
                    port.startPlayback(atFrame: index)
                }
            } catch {
                fail(error)
                return error
            }
        }
        return nil
    }

    private func nextFrame(for index: Int64) -> SDIFrame {
        let fresh = frameProvider(index)
        return lock.withLock {
            if let fresh {
                lastFrame = fresh
                return fresh
            }
            repeated += 1
            if let last = lastFrame { return last }
            let black = SDIFrame(width: mode.width, height: mode.height, bgra: [UInt8](repeating: 0, count: mode.width * mode.height * 4))
            lastFrame = black
            return black
        }
    }

    private func fail(_ error: Error) {
        finish(reason: .failed(error as? SDIError ?? .portClosed))
    }

    private func finish(reason: SDIStopReason) {
        let wasRunning: Bool = lock.withLock {
            let running = currentState == .running
            if running || currentState == .idle { currentState = .stopped(reason) }
            if running { scheduler.stop() }
            return running
        }
        guard wasRunning else { return }
        port.onFrameCompleted = nil
        port.onFailure = nil
        port.stopPlayback()
        port.disable()
    }
}
