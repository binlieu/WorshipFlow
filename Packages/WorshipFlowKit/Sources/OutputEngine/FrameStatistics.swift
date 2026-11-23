// OUT-001: presentation cadence statistics (NFR-01, NFR-02).
import Foundation

public struct FrameStatistics: Sendable, Equatable {
    public var targetInterval: Double
    public private(set) var presentedFrames = 0
    public private(set) var droppedFrames = 0
    public private(set) var lateFrames = 0
    public private(set) var maxInterval = 0.0
    private var lastPresentation: Double?

    public init(targetInterval: Double) {
        self.targetInterval = targetInterval
    }

    /// Records one presentation at `time` (seconds). A drop is a whole target interval with no presentation;
    /// a late frame is one whose gap from the previous presentation exceeded 1.5 intervals.
    @discardableResult
    public mutating func recordPresentation(at time: Double) -> PresentationOutcome? {
        presentedFrames += 1
        var outcome: PresentationOutcome?
        if let last = lastPresentation, targetInterval > 0 {
            let gap = time - last
            maxInterval = max(maxInterval, gap)
            let missed = Int((gap / targetInterval).rounded()) - 1
            if missed > 0 { droppedFrames += missed }
            let late = gap > 1.5 * targetInterval
            if late { lateFrames += 1 }
            outcome = PresentationOutcome(gap: gap, missed: max(0, missed), isLate: late, isLong: gap > 2 * targetInterval)
        }
        lastPresentation = time
        return outcome
    }

    /// Counters from outside a display link: an SDI output reads them from its session (HW-002).
    public init(targetInterval: Double, presentedFrames: Int, droppedFrames: Int, lateFrames: Int, maxInterval: Double = 0) {
        self.targetInterval = targetInterval
        self.presentedFrames = presentedFrames
        self.droppedFrames = droppedFrames
        self.lateFrames = lateFrames
        self.maxInterval = maxInterval
    }

    public mutating func reset() {
        presentedFrames = 0
        droppedFrames = 0
        lateFrames = 0
        maxInterval = 0
        lastPresentation = nil
    }
}
