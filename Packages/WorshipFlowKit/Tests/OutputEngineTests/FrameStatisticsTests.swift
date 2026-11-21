// OUT-001 acceptance tests (NFR-01, NFR-02). Owned by the coordinator: do not modify.
import Testing
@testable import OutputEngine

@Suite struct FrameStatisticsTests {
    let interval = 1001.0 / 60000.0   // 59.94 fps

    @Test func steadyCadenceDropsNothing() {
        var stats = FrameStatistics(targetInterval: interval)
        for i in 0..<600 { stats.recordPresentation(at: Double(i) * interval) }
        #expect(stats.presentedFrames == 600)
        #expect(stats.droppedFrames == 0)
        #expect(stats.lateFrames == 0)
    }

    @Test func smallJitterIsNotADrop() {
        var stats = FrameStatistics(targetInterval: interval)
        for i in 0..<600 {
            let jitter = (i % 2 == 0 ? 0.2 : -0.2) * interval
            stats.recordPresentation(at: Double(i) * interval + jitter)
        }
        #expect(stats.droppedFrames == 0)
        #expect(stats.lateFrames == 0)
    }

    @Test func oneSkippedIntervalIsOneDrop() {
        var stats = FrameStatistics(targetInterval: interval)
        for i in [0, 1, 2, 4, 5] { stats.recordPresentation(at: Double(i) * interval) }
        #expect(stats.presentedFrames == 5)
        #expect(stats.droppedFrames == 1)
        #expect(stats.lateFrames == 1)
    }

    @Test func longStallCountsEveryMissedInterval() {
        var stats = FrameStatistics(targetInterval: interval)
        stats.recordPresentation(at: 0)
        stats.recordPresentation(at: 10 * interval)
        #expect(stats.droppedFrames == 9)
        #expect(stats.lateFrames == 1)
        #expect(abs(stats.maxInterval - 10 * interval) < 1e-9)
    }

    @Test func resetClearsCounters() {
        var stats = FrameStatistics(targetInterval: interval)
        stats.recordPresentation(at: 0)
        stats.recordPresentation(at: 5 * interval)
        stats.reset()
        #expect(stats.presentedFrames == 0 && stats.droppedFrames == 0 && stats.lateFrames == 0)
        stats.recordPresentation(at: 100)   // first frame after reset is never a drop
        #expect(stats.droppedFrames == 0)
    }
}
