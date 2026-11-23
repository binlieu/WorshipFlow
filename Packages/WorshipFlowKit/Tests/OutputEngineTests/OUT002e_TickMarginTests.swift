// OUT-002e (KI-007): the soak report says, over the whole run, how long before the display link's target time each tick finished.
// Injected values only: no wall clock.
import Testing
import Foundation
import Domain
@testable import OutputEngine

@Suite struct OUT002e_TickMarginTests {
    @Test func marginIsTargetMinusTickEnd() {
        let s = TickSample(start: 10.000, linkTimestamp: 10.000, linkTarget: 10.0167, drawable: 0.001, build: 0.0005, encode: 0.0005)
        #expect(abs((s.margin ?? 99) - 0.0147) < 1e-9)
    }

    @Test func noLinkTargetMeansNoMargin() {
        let s = TickSample(start: 10, linkTimestamp: 0, linkTarget: 0, drawable: 0.001, build: 0, encode: 0)
        #expect(s.margin == nil)
    }

    @Test func theHistogramKeepsCountMeanMinimumAndTicksEndingAfterTheTarget() {
        var h = TickWorkHistogram()
        h.record(work: 0.001, period: 1.0 / 60, margin: 0.015)
        h.record(work: 0.017, period: 1.0 / 60, margin: -0.0005)
        h.record(work: 0.017, period: 1.0 / 60, margin: -0.0015)
        h.record(work: 0.001, period: 1.0 / 60, margin: nil)      // no link target: not counted in the margin
        #expect(h.marginTicks == 3)
        #expect(h.marginLateTicks == 2)
        #expect(abs(h.marginMinMs - (-1.5)) < 1e-9)
        #expect(abs(h.marginMeanMs - ((15 - 0.5 - 1.5) / 3)) < 1e-9)
        #expect(h.ticks == 4)
    }

    @Test func recordingWithoutAMarginLeavesTheOldBehaviourUnchanged() {
        var h = TickWorkHistogram()
        h.record(work: 0.0004, period: 1.0 / 60)
        #expect(h.marginTicks == 0)
        #expect(h.counts[0] == 1)
    }

    @Test func theReportLineStatesTheMarginAndTheShareAtTwelveMillisecondsOrMore() {
        var log = FrameEventLog(capacity: 10)
        for _ in 0..<3 { log.noteTick(work: 0.0005, period: 1.0 / 60, margin: 0.0155) }
        for _ in 0..<1 { log.noteTick(work: 0.0165, period: 1.0 / 60, margin: -0.0005) }
        let text = SoakDropReport.classificationLines(log: log).joined(separator: "\n")
        #expect(text.contains("ticks with work of 12 ms or more: 1 of 4"))
        #expect(text.contains("margin to the display link target"))
        #expect(text.contains("ending after the target: 1 of 4"))
    }

    @Test func aRunWithoutLinkTargetsSaysSo() {
        var log = FrameEventLog(capacity: 10)
        log.noteTick(work: 0.001, period: 1.0 / 60)
        let text = SoakDropReport.classificationLines(log: log).joined(separator: "\n")
        #expect(text.contains("margin to the display link target: no link target recorded"))
    }
}

@Suite struct OUT002e_PresentLatencyTests {
    @Test func theStatsKeepCountMeanMinimumAndMaximumInMilliseconds() {
        var s = PresentLatencyStats()
        #expect(s.count == 0)
        s.record(0.0168); s.record(0.0335); s.record(0.0500)
        #expect(s.count == 3)
        #expect(abs(s.meanMs - 33.43333333) < 1e-6)
        #expect(abs(s.minMs - 16.8) < 1e-9)
        #expect(abs(s.maxMs - 50.0) < 1e-9)
    }

    @Test func aNegativeOrZeroLatencyIsIgnored() {
        var s = PresentLatencyStats()
        s.record(0); s.record(-0.001)
        #expect(s.count == 0)
    }

    @Test func theReportSaysHowLongAFrameTookFromTheStartOfItsTickToTheScreen() {
        var log = FrameEventLog(capacity: 10)
        log.noteTick(work: 0.001, period: 1.0 / 60, margin: 0.015)
        log.notePresentLatency(0.0167); log.notePresentLatency(0.0334)
        let text = SoakDropReport.classificationLines(log: log).joined(separator: "\n")
        #expect(text.contains("latency from the start of a tick to its frame on screen: mean 25.05 ms, minimum 16.70 ms, maximum 33.40 ms over 2 frames"))
    }

    @Test func aRunWithNoPresentedFrameSaysSo() {
        var log = FrameEventLog(capacity: 10)
        log.noteTick(work: 0.001, period: 1.0 / 60)
        let text = SoakDropReport.classificationLines(log: log).joined(separator: "\n")
        #expect(text.contains("latency from the start of a tick to its frame on screen: no presented frame"))
    }
}
