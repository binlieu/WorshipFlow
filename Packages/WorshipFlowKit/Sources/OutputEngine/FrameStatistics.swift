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
    public mutating func recordPresentation(at time: Double) {
        presentedFrames += 1
        if let last = lastPresentation, targetInterval > 0 {
            let gap = time - last
            maxInterval = max(maxInterval, gap)
            let missed = Int((gap / targetInterval).rounded()) - 1
            if missed > 0 { droppedFrames += missed }
            if gap > 1.5 * targetInterval { lateFrames += 1 }
        }
        lastPresentation = time
    }

    public mutating func reset() {
        presentedFrames = 0
        droppedFrames = 0
        lateFrames = 0
        maxInterval = 0
        lastPresentation = nil
    }
}
