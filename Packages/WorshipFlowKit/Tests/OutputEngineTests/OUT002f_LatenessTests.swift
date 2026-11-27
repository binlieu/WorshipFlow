// OUT-002f (REVIEW-5 L23): the display link's target timestamp is a time in the future (the hour soak of 2026-11-26 recorded the callback running
// steadily about one frame period before it, on every listed tick). Injected timings only: no wall clock.
import Testing
import Foundation
@testable import OutputEngine

private let period = 1.0 / 60.0
private let event = 100.0

private func tick(_ start: Double, linkTimestamp: Double) -> TickSample {
    TickSample(start: start, linkTimestamp: linkTimestamp, linkTarget: 0, drawable: 0.0001, build: 0.0005, encode: 0.0004)
}

@Suite struct OUT002f_LatenessTests {
    @Test func callbacksThatRunOnePeriodBeforeTheLinksTimestampAreOnTime() {
        // The measured shape: the callback runs about one frame period before the link's timestamp, tick after tick.
        let ticks = (0..<4).map { i in
            let start = event - 0.08 + Double(i) * period
            return tick(start, linkTimestamp: start + period)
        }
        let c = FrameLateness.classify(ticks: ticks, eventTime: event, gap: 2 * period, period: period)
        #expect(c.kind == .presentedLate, "every tick was on time: \(c.detail)")
    }

    @Test func aCallbackThatRanAfterItsTimeIsAppLateEvenThoughTheTimestampIsStillAheadOfIt() {
        // On time, the callback runs one period before the timestamp. This one ran 30 ms later than that: it ran 13 ms before the stamp, so the
        // difference to the stamp is still negative, and the rule that read the stamp as the due time could not see it.
        let on = tick(event - 0.05, linkTimestamp: event - 0.05 + period)
        let startLate = event - 0.05 + period
        let late = tick(startLate, linkTimestamp: startLate + period - 0.030)
        let c = FrameLateness.classify(ticks: [on, late], eventTime: event, gap: 0.03, period: period)
        #expect(c.kind == .appLate)
        #expect(c.detail.contains("display link"))
    }

    @Test func aCallbackThatMissedItsTimeByLessThanOneAndAHalfPeriodsIsNotLate() {
        let on = tick(event - 0.05, linkTimestamp: event - 0.05 + period)
        let startLate = event - 0.05 + period
        let a_bit = tick(startLate, linkTimestamp: startLate + period - 0.015)   // 15 ms after its time
        #expect(FrameLateness.classify(ticks: [on, a_bit], eventTime: event, gap: 0.03, period: period).kind == .presentedLate)
    }
}

// OUT-002f (REVIEW-5 L19): the output follows the refresh rate of the display its window is on.
@Suite struct OUT002f_RefreshRateTests {
    @Test func aWindowMovedFromA120HzDisplayTo60HzSwitchesTheRate() {
        #expect(MetalOutput.newRefreshRate(screenMaximum: 60, current: 120) == 60)
        #expect(MetalOutput.newRefreshRate(screenMaximum: 120, current: 60) == 120)
    }

    @Test func theSameRateOrNoRateChangesNothing() {
        #expect(MetalOutput.newRefreshRate(screenMaximum: 60, current: 60) == nil)
        #expect(MetalOutput.newRefreshRate(screenMaximum: 0, current: 60) == nil)
        #expect(MetalOutput.newRefreshRate(screenMaximum: -1, current: 60) == nil)
    }
}
