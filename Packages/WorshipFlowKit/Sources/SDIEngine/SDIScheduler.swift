// HW-001 / SCRN-11, NFR-02, NFR-05: the pure scheduling rules for a hardware output.
// A value type with no clock and no device: it is told what completed and says what to schedule next.
import Foundation

/// How the device reported a scheduled frame.
public enum SDICompletionResult: Equatable, Sendable {
    case completed
    case displayedLate
    case dropped
    case flushed
}

public enum SDIHealth: Equatable, Sendable {
    case ok
    case degraded
    case failing
}

public struct SDISchedulerStatistics: Equatable, Sendable {
    public var scheduled = 0
    public var completed = 0
    public var late = 0
    public var dropped = 0
    public var flushed = 0
    public init() {}
}

public struct SDIScheduler: Sendable {
    public enum Action: Equatable, Sendable {
        case schedule(frameIndex: Int64)
        case startPlayback(atFrame: Int64)
    }

    /// Health looks at the last 120 completions (two seconds at 60 fps).
    public static let healthWindow = 120
    public static let degradedThreshold = 3
    public static let failingThreshold = 30

    /// Frames scheduled before playback starts, and the level the buffer is topped back up to. Always at least 1.
    public let prerollFrames: Int
    /// Hard cap on frames in the device buffer. Always at least 1; the target level never exceeds it.
    public let maxBufferedFrames: Int

    public private(set) var isRunning = false
    public private(set) var statistics = SDISchedulerStatistics()

    private var nextFrameIndex: Int64 = 0
    private var window: [Bool] = []          // true = bad frame (late or dropped)
    private var badInWindow = 0

    public init(prerollFrames: Int, maxBufferedFrames: Int) {
        self.prerollFrames = max(1, prerollFrames)
        self.maxBufferedFrames = max(1, maxBufferedFrames)
    }

    private var targetBuffered: Int { min(prerollFrames, maxBufferedFrames) }

    public var health: SDIHealth {
        if badInWindow >= Self.failingThreshold { return .failing }
        if badInWindow >= Self.degradedThreshold { return .degraded }
        return .ok
    }

    /// Begins a fresh timeline at frame zero with fresh statistics. Starting twice does nothing.
    @discardableResult
    public mutating func start() -> [Action] {
        guard !isRunning else { return [] }
        isRunning = true
        statistics = SDISchedulerStatistics()
        window.removeAll()
        badInWindow = 0
        nextFrameIndex = 0
        var actions = scheduleActions(count: targetBuffered)
        actions.append(.startPlayback(atFrame: 0))
        return actions
    }

    public mutating func stop() {
        isRunning = false
    }

    /// Records one completion and returns the frames to schedule to bring the buffer back to its target level.
    /// `bufferedFrames` is what the device reports as still queued, after this completion.
    @discardableResult
    public mutating func frameCompleted(_ result: SDICompletionResult, bufferedFrames: Int) -> [Action] {
        guard isRunning else { return [] }
        switch result {
        case .completed: statistics.completed += 1
        case .displayedLate: statistics.late += 1
        case .dropped: statistics.dropped += 1
        case .flushed: statistics.flushed += 1
        }
        if result != .flushed {           // a flush is the device emptying itself, not a bad frame
            record(bad: result == .displayedLate || result == .dropped)
        }
        guard result != .flushed else { return [] }
        return scheduleActions(count: targetBuffered - max(0, bufferedFrames))
    }

    private mutating func scheduleActions(count: Int) -> [Action] {
        guard count > 0 else { return [] }
        var actions: [Action] = []
        for _ in 0..<count {
            actions.append(.schedule(frameIndex: nextFrameIndex))
            nextFrameIndex += 1
            statistics.scheduled += 1
        }
        return actions
    }

    private mutating func record(bad: Bool) {
        window.append(bad)
        if bad { badInWindow += 1 }
        if window.count > Self.healthWindow {
            if window.removeFirst() { badInWindow -= 1 }
        }
    }
}
