// OUT-002b: the soak report says when each dropped and late frame happened. Injected times only; no wall clock.
import Testing
@testable import OutputEngine

@Suite struct OUT002b_DropTimesTests {
    let period = 0.01   // 100 Hz

    // MARK: outcome from FrameStatistics

    @Test func firstPresentationHasNoOutcomeAndSteadyCadenceIsNotNotable() {
        var stats = FrameStatistics(targetInterval: period)
        #expect(stats.recordPresentation(at: 0) == nil)
        let steady = stats.recordPresentation(at: period)
        #expect(steady?.isNotable == false)
    }

    @Test func outcomeMatchesTheCounters() {
        var stats = FrameStatistics(targetInterval: period)
        stats.recordPresentation(at: 0)
        let late = stats.recordPresentation(at: 0.016)      // 1.6 periods rounds to 2: one missed interval, late, not over 2x
        #expect(late == PresentationOutcome(gap: 0.016, missed: 1, isLate: true, isLong: false))
        let drop = stats.recordPresentation(at: 0.016 + 0.05)   // 5 periods: 4 dropped, late, long
        #expect(drop?.missed == 4)
        #expect(drop?.isLate == true)
        #expect(drop?.isLong == true)
        #expect(stats.droppedFrames == 5)
        #expect(stats.lateFrames == 2)
    }

    // MARK: the log and its cap

    @Test func logKeepsOnlyNotableFramesAndCapsMemory() {
        var log = FrameEventLog(capacity: 3)
        log.record(at: 1, PresentationOutcome(gap: 0.01, missed: 0, isLate: false, isLong: false))
        #expect(log.events.isEmpty)
        for i in 0..<5 {
            log.record(at: Double(i), PresentationOutcome(gap: 0.03, missed: 2, isLate: true, isLong: true))
        }
        #expect(log.events.count == 3)
        #expect(log.beyondCap == 2)
        #expect(log.events[0].intervalMs == 30)
        #expect(log.events[0].missed == 2)
    }

    @Test func zeroCapacityLogCountsOnly() {
        var log = FrameEventLog(capacity: 0)
        log.record(at: 1, PresentationOutcome(gap: 0.03, missed: 2, isLate: true, isLong: true))
        #expect(log.events.isEmpty)
        #expect(log.beyondCap == 1)
    }

    // MARK: classification

    @Test func spanStartsAtTheLastVisibleSampleAndEndsAtTheNextVisibleOne() {
        var t = VisibilityTimeline()
        t.note(sampleAt: 10.0, covered: false)
        t.note(sampleAt: 10.25, covered: true)
        t.note(sampleAt: 10.5, covered: true)     // still the same span
        t.note(sampleAt: 10.75, covered: false)
        #expect(t.spans == [VisibilityTimeline.Span(start: 10.0, end: 10.75)])
    }

    @Test func firstSampleCoveredStartsTheSpanAtThatSample() {
        var t = VisibilityTimeline()
        t.note(sampleAt: 5, covered: true)
        #expect(t.spans == [VisibilityTimeline.Span(start: 5, end: nil)])
        #expect(t.isCovered(at: 100))   // open span: covered until it ends
        t.finish(at: 6)
        #expect(t.spans[0].end == 6)
    }

    @Test func eventIsCoveredInsideTheSpanAndForOneSecondAfter() {
        var t = VisibilityTimeline()
        t.note(sampleAt: 10, covered: false)
        t.note(sampleAt: 11, covered: true)
        t.note(sampleAt: 12, covered: false)
        #expect(!t.isCovered(at: 9.9))
        #expect(t.isCovered(at: 10.0))
        #expect(t.isCovered(at: 11.5))
        #expect(t.isCovered(at: 13.0))      // end + 1 s
        #expect(!t.isCovered(at: 13.001))
    }

    @Test func spanCapCountsTheRest() {
        var t = VisibilityTimeline(spanCapacity: 2)
        var now = 0.0
        for _ in 0..<4 {
            t.note(sampleAt: now, covered: false); now += 1
            t.note(sampleAt: now, covered: true); now += 1
        }
        t.note(sampleAt: now, covered: false)
        #expect(t.spans.count == 2)
        #expect(t.spansBeyondCap == 2)
    }

    @Test func splitTotalsSeparateVisibleFromCovered() {
        var t = VisibilityTimeline()
        t.note(sampleAt: 100, covered: false)
        t.note(sampleAt: 101, covered: true)
        t.note(sampleAt: 103, covered: false)
        let events = [
            FrameEvent(time: 50, intervalMs: 30, missed: 2, isLate: true, isLong: true),       // visible
            FrameEvent(time: 70, intervalMs: 16, missed: 0, isLate: true, isLong: false),      // visible
            FrameEvent(time: 103, intervalMs: 590, missed: 58, isLate: true, isLong: true),    // covered (first frame after)
            FrameEvent(time: 104.5, intervalMs: 20, missed: 1, isLate: true, isLong: false),   // 1.5 s after: visible
        ]
        let s = SoakDropReport.split(events: events, timeline: t)
        #expect(s.visible.dropped == 3)
        #expect(s.visible.late == 3)
        #expect(s.visible.longIntervals == 1)
        #expect(s.visible.longestIntervalMs == 30)
        #expect(s.covered.dropped == 58)
        #expect(s.covered.late == 1)
        #expect(s.covered.longestIntervalMs == 590)
    }

    // MARK: report text

    @Test func reportTextListsEventsSpansAndTheResultLine() {
        var t = VisibilityTimeline()
        t.note(sampleAt: 1000, covered: false)
        t.note(sampleAt: 1010, covered: false)
        t.note(sampleAt: 1010.25, covered: true)
        t.note(sampleAt: 1011, covered: false)
        var log = FrameEventLog(capacity: 10)
        log.record(at: 1005, PresentationOutcome(gap: 0.03, missed: 2, isLate: true, isLong: true))
        log.record(at: 1011.0, PresentationOutcome(gap: 0.59, missed: 58, isLate: true, isLong: true))
        let lines = SoakDropReport.lines(log: log, timeline: t, origin: 1000)
        let text = lines.joined(separator: "\n")
        #expect(text.contains("events recorded: 2 (cap 10), further events not listed or classified: 0"))
        #expect(text.contains("while visible: dropped 2, late 1, intervals over 2x period 1"))
        #expect(text.contains("while covered or within 1 s after becoming visible again: dropped 58, late 1, intervals over 2x period 1"))
        #expect(text.contains("longest interval while visible: 30.00 ms"))
        #expect(text.contains("covered spans (start s, length s):"))
        #expect(text.contains("  10.000, 1.000"))
        #expect(text.contains("  5.000, dropped 2 + late + over 2x period, 30.00, visible"))
        #expect(text.contains("  11.000, dropped 58 + late + over 2x period, 590.00, covered"))
        #expect(lines.last == "drops while visible: 2")
    }

    @Test func reportWithNoEventsSaysSo() {
        let lines = SoakDropReport.lines(log: FrameEventLog(capacity: 4), timeline: VisibilityTimeline(), origin: 0)
        #expect(lines.contains("events: none"))
        #expect(lines.contains("covered spans: none"))
        #expect(lines.last == "drops while visible: 0")
    }

    @Test func overflowIsStatedNextToTheResult() {
        var log = FrameEventLog(capacity: 1)
        for i in 0..<3 { log.record(at: Double(i), PresentationOutcome(gap: 0.03, missed: 2, isLate: true, isLong: true)) }
        let lines = SoakDropReport.lines(log: log, timeline: VisibilityTimeline(), origin: 0)
        #expect(lines.last == "drops while visible: 2 (at least: 2 further event(s) were not classified)")
    }
}
