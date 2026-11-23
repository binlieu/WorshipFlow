// OUT-002d (KI-007): for each dropped or late frame, say whether the app or the system was late. Injected timings only: no wall clock.
import Testing
import Foundation
import QuartzCore
import Domain
@testable import OutputEngine

private let period = 1.0 / 60.0

/// A tick that started at `start`, with its three parts in milliseconds.
private func tick(_ start: Double, drawable: Double = 0.1, build: Double = 0.5, encode: Double = 0.4, flags: UInt8 = 0,
                  linkTimestamp: Double = 0, linkTarget: Double = 0) -> TickSample {
    TickSample(start: start, linkTimestamp: linkTimestamp, linkTarget: linkTarget,
               drawable: drawable / 1000, build: build / 1000, encode: encode / 1000, flags: flags)
}

/// Ticks on a steady cadence ending just before `end`.
private func steady(count: Int, endingBefore end: Double) -> [TickSample] {
    (0..<count).map { i in tick(end - Double(count - i) * period) }
}

@Suite struct OUT002d_RingTests {
    @Test func theRingKeepsTheLastEightTicksInOrderAndNeverGrows() {
        var ring = TickRing()
        #expect(ring.capacity == 8)
        for i in 0..<20 { ring.push(tick(Double(i))) }
        let s = ring.snapshot()
        #expect(s.count == 8)
        #expect(s.map(\.start) == (12..<20).map(Double.init))
        #expect(ring.count == 8)
    }

    @Test func aPartlyFilledRingReturnsOnlyWhatWasWritten() {
        var ring = TickRing(capacity: 4)
        #expect(ring.snapshot().isEmpty)
        ring.push(tick(1)); ring.push(tick(2))
        #expect(ring.snapshot().map(\.start) == [1, 2])
    }

    @Test func theFlagsRoundTrip() {
        let s = tick(0, flags: TickSample.gateHolding | TickSample.newVideoFrame)
        #expect(s.gateHolding && s.newVideoFrame && !s.sceneChanged && !s.skipped)
        #expect(abs(s.work - 0.001) < 1e-9)
    }
}

@Suite struct OUT002d_HistogramTests {
    @Test func workFallsIntoFixedBucketsAndTheMaximumIsKept() {
        var h = TickWorkHistogram()
        h.record(work: 0.0003, period: period)     // < 0.5 ms
        h.record(work: 0.0015, period: period)     // 1 to 2
        h.record(work: 0.0015, period: period)
        h.record(work: 0.030, period: period)      // 20 to 33, over the period
        h.record(work: 0.5, period: period)        // beyond the last edge
        #expect(h.ticks == 5)
        #expect(h.counts.reduce(0, +) == 5)
        #expect(h.counts[0] == 1)
        #expect(h.counts[2] == 2)
        #expect(h.counts.last == 1)
        #expect(h.overPeriod == 2)
        #expect(abs(h.maxWorkMs - 500) < 1e-6)
    }

    @Test func theBucketArrayNeverChangesSize() {
        var h = TickWorkHistogram()
        let n = h.counts.count
        for i in 0..<10_000 { h.record(work: Double(i % 90) / 1000, period: period) }
        #expect(h.counts.count == n)
        #expect(h.ticks == 10_000)
    }

    @Test func skippedTicksAreCountedApart() {
        var h = TickWorkHistogram()
        h.recordSkipped(); h.recordSkipped()
        #expect(h.skipped == 2)
        #expect(h.ticks == 0)
    }
}

@Suite struct OUT002d_ClassificationTests {
    let event = 100.0
    let gap = 2 * period

    private func classify(_ ticks: [TickSample]) -> LatenessClassification {
        FrameLateness.classify(ticks: ticks, eventTime: event, gap: gap, period: period)
    }

    @Test func aTickWhoseWorkExceededThePeriodIsAppSlowAndNamesTheLargestPart() {
        var ticks = steady(count: 5, endingBefore: event - 3 * period)
        ticks.append(tick(event - 3 * period, drawable: 0.2, build: 27.5, encode: 0.6))
        ticks.append(tick(event - 3 * period + 0.0283))
        let c = classify(ticks)
        #expect(c.kind == .appSlow)
        #expect(c.detail.contains("building the scene"))
        #expect(c.detail.contains("28.3"))
    }

    @Test func eachPartCanBeTheSlowOne() {
        func part(_ d: Double, _ b: Double, _ e: Double) -> String {
            classify([tick(event - 0.03, drawable: d, build: b, encode: e)]).detail
        }
        #expect(part(30, 0.1, 0.1).contains("getting the drawable"))
        #expect(part(0.1, 30, 0.1).contains("building the scene"))
        #expect(part(0.1, 0.1, 30).contains("encoding and committing"))
    }

    @Test func workWithinThePeriodIsNotSlow() {
        let c = classify([tick(event - 0.03, drawable: 0, build: period * 990, encode: 0)])
        #expect(c.kind != .appSlow)
    }

    @Test func aTickThatStartedMoreThanOneAndAHalfPeriodsAfterThePreviousOneIsAppLate() {
        let a = tick(event - 0.08)
        let b = tick(event - 0.08 + 0.030)      // 1.8 periods later, short work
        let c = classify([a, b])
        #expect(c.kind == .appLate)
        #expect(c.detail.contains("30.0"))
    }

    @Test func aCallbackFarAfterTheLinksOwnTimestampIsAppLate() {
        let on = tick(event - 0.05, linkTimestamp: event - 0.05 - 0.001)
        let off = tick(event - 0.05 + period, linkTimestamp: event - 0.05 + period - 0.030)   // ran 30 ms after the link's stamp
        let c = classify([on, off])
        #expect(c.kind == .appLate)
        #expect(c.detail.contains("display link"))
    }

    @Test func slowWorkWinsOverLateStartBecauseTheLateStartFollowsFromIt() {
        let a = tick(event - 0.08, build: 40)
        let b = tick(event - 0.08 + 0.045)
        #expect(classify([a, b]).kind == .appSlow)
    }

    @Test func everyTickOnTimeAndShortMeansThePresentationWasLate() {
        let ticks = steady(count: 4, endingBefore: event)
        let c = classify(ticks)
        #expect(c.kind == .presentedLate)
        #expect(c.detail.contains("4 tick"))
    }

    @Test func aSkippedTickMakesItUnknownAndSaysWhy() {
        var ticks = steady(count: 4, endingBefore: event)
        ticks.append(tick(event - 0.005, drawable: 0, build: 0, encode: 0, flags: TickSample.skipped))
        let c = classify(ticks)
        #expect(c.kind == .unknown)
        #expect(c.detail.contains("skipped"))
    }

    @Test func noTicksNearTheEventIsUnknown() {
        #expect(classify([]).kind == .unknown)
        #expect(classify([tick(event - 5)]).kind == .unknown)       // far older than the window
        #expect(FrameLateness.classify(ticks: [tick(event - 0.01)], eventTime: event, gap: gap, period: 0).kind == .unknown)
    }

    @Test func aSlowTickOutsideTheWindowIsNotBlamed() {
        // A steady run of ticks starting one second before the event, the first of them slow.
        let ticks = (0..<59).map { tick(event - 1.0 + Double($0) * period, build: $0 == 0 ? 50 : 0.5) }
        #expect(classify(ticks).kind == .presentedLate)
    }

    @Test func aTickAfterTheEventIsIgnored() {
        let ticks = steady(count: 5, endingBefore: event) + [tick(event + 0.01, build: 50)]
        #expect(classify(ticks).kind == .presentedLate)
    }

    @Test func theLongGapWindowReachesBackOverTheWholeGap() {
        let longGap = 0.59
        let slow = tick(event - longGap - 0.02, build: 500)
        let c = FrameLateness.classify(ticks: [slow, tick(event - 0.01)], eventTime: event, gap: longGap, period: period)
        #expect(c.kind == .appSlow)
    }
}

@Suite struct OUT002d_MarksTests {
    @Test func theNearestMarkIsSignedAndPositiveWhenTheEventIsAfterIt() {
        let marks = [10.0, 15.0, 20.0]
        #expect(EventMarks.nearest(to: 15.4, in: marks) == 15.4 - 15.0)
        #expect(EventMarks.nearest(to: 14.9, in: marks)! < 0)
        #expect(abs(EventMarks.nearest(to: 17.4, in: marks)! - 2.4) < 1e-9)
        #expect(abs(EventMarks.nearest(to: 17.6, in: marks)! + 2.4) < 1e-9)
        #expect(abs(EventMarks.nearest(to: 100, in: marks)! - 80) < 1e-9)
        #expect(abs(EventMarks.nearest(to: 0, in: marks)! + 10) < 1e-9)
        #expect(EventMarks.nearest(to: 1, in: []) == nil)
    }

    @Test func theMarkListIsBounded() {
        var marks = EventMarks(capacity: 3)
        for i in 0..<10 { marks.add(Double(i)) }
        #expect(marks.times == [0, 1, 2])
        #expect(marks.beyondCap == 7)
    }
}

@Suite struct OUT002d_EventLogTests {
    private let outcome = PresentationOutcome(gap: 0.0333, missed: 1, isLate: true, isLong: false)

    @Test func aNotableEventCarriesTheRingAndThePeriod() {
        var log = FrameEventLog(capacity: 5)
        let ticks = steady(count: 8, endingBefore: 10)
        log.record(at: 10, outcome, targetInterval: period, ticks: ticks)
        #expect(log.events.count == 1)
        #expect(log.events[0].ticks == ticks)
        #expect(abs(log.events[0].targetMs - 16.6667) < 0.001)
    }

    @Test func aFrameThatIsNotNotableTakesNoSnapshot() {
        var log = FrameEventLog(capacity: 5)
        var called = false
        log.record(at: 1, PresentationOutcome(gap: period, missed: 0, isLate: false, isLong: false), targetInterval: period,
                   ticks: { () -> [TickSample] in called = true; return [] }())
        #expect(!called)
        #expect(log.events.isEmpty)
    }

    @Test func pastTheCapNoSnapshotIsTakenAndTheEventIsOnlyCounted() {
        var log = FrameEventLog(capacity: 1)
        var calls = 0
        for i in 0..<4 { log.record(at: Double(i), outcome, targetInterval: period, ticks: { () -> [TickSample] in calls += 1; return [] }()) }
        #expect(log.events.count == 1)
        #expect(log.beyondCap == 3)
        #expect(calls == 1)
    }

    @Test func theEventCapStaysTwoThousandAndEachEventHoldsAtMostTheRing() {
        #expect(FrameEventLog.defaultCapacity == 2_000)
        var log = FrameEventLog()
        var ring = TickRing()
        for i in 0..<30 { ring.push(tick(Double(i))) }
        for i in 0..<2_100 { log.record(at: Double(i), outcome, targetInterval: period, ticks: ring.snapshot()) }
        #expect(log.events.count == 2_000)
        #expect(log.beyondCap == 100)
        #expect(log.events.allSatisfy { $0.ticks.count <= TickRing.defaultCapacity })
    }

    @Test func theLogCountsTickWorkAndSkippedTicks() {
        var log = FrameEventLog(capacity: 1)
        log.noteTick(work: 0.002, period: period)
        log.noteSkippedTick()
        #expect(log.workHistogram.ticks == 1)
        #expect(log.workHistogram.skipped == 1)
    }
}

@Suite struct OUT002d_ReportTests {
    private func report() -> (lines: [String], text: String) {
        var timeline = VisibilityTimeline()
        timeline.note(sampleAt: 1000, covered: false)
        var log = FrameEventLog(capacity: 10)
        // Event 1: a slow build near an advance.
        let slowTicks = [tick(1004.90), tick(1004.93, build: 27), tick(1004.9667)]
        log.record(at: 1005, PresentationOutcome(gap: 0.0333, missed: 1, isLate: true, isLong: false), targetInterval: period, ticks: slowTicks)
        // Event 2: every tick fine.
        log.record(at: 1100, PresentationOutcome(gap: 0.0333, missed: 1, isLate: true, isLong: false), targetInterval: period,
                   ticks: steady(count: 6, endingBefore: 1100))
        // Event 3: no tick record (the older recording hook).
        log.record(at: 1200, PresentationOutcome(gap: 0.05, missed: 2, isLate: true, isLong: true))
        log.noteTick(work: 0.0003, period: period)
        log.noteTick(work: 0.0275, period: period)
        log.noteSkippedTick()
        let lines = SoakDropReport.lines(log: log, timeline: timeline, origin: 1000, advances: [1005.02, 1010.1], loops: [1080])
        return (lines, lines.joined(separator: "\n"))
    }

    @Test func theTextStatesTheClassificationRule() {
        let r = report().text
        #expect(r.contains("classification rule"))
        #expect(r.contains("app slow:"))
        #expect(r.contains("app late:"))
        #expect(r.contains("presented late:"))
        #expect(r.contains("unknown:"))
    }

    @Test func theSummaryCountsEachClass() {
        #expect(report().text.contains("classes: app slow 1, app late 0, presented late 1, unknown 1"))
    }

    @Test func eachEventHasOneReadableLineWithClassMarksAndTicks() {
        let lines = report().lines
        let slow = lines.first { $0.contains("app slow (") && $0.hasPrefix("    ") }
        #expect(slow != nil)
        #expect(slow?.contains("advance -0.020 s") == true)      // event 5.000 s, advance 5.020 s: the event is before it
        #expect(slow?.contains("loop -75.000 s") == true)
        #expect(slow?.contains("b27.0") == true)
        let fine = lines.first { $0.contains("presented late (") }
        #expect(fine != nil)
        #expect(lines.contains { $0.contains("unknown (no tick records") })
        // The OUT-002b event lines and the final line are unchanged.
        #expect(lines.contains("  5.000, dropped 1 + late, 33.30, visible"))
        #expect(lines.last == "drops while visible: 4")
    }

    @Test func theHistogramListsBucketsMaximumAndSkippedTicks() {
        let r = report().text
        #expect(r.contains("tick work over the run: 2 ticks"))
        #expect(r.contains("maximum 27.50 ms"))
        #expect(r.contains("over the frame period: 1"))
        #expect(r.contains("ticks skipped because the GPU was behind: 1"))
        #expect(r.contains("< 0.5 ms: 1"))
    }

    @Test func missingMarksAreSaidNotInvented() {
        var log = FrameEventLog(capacity: 2)
        log.record(at: 5, PresentationOutcome(gap: 0.0333, missed: 1, isLate: true, isLong: false), targetInterval: period, ticks: steady(count: 3, endingBefore: 5))
        let text = SoakDropReport.lines(log: log, timeline: VisibilityTimeline(), origin: 0).joined(separator: "\n")
        #expect(text.contains("advance n/a"))
        #expect(text.contains("loop n/a"))
    }

    @Test func theExistingReportShapeStillEndsWithTheDropsLine() {
        let lines = SoakDropReport.lines(log: FrameEventLog(capacity: 4), timeline: VisibilityTimeline(), origin: 0)
        #expect(lines.last == "drops while visible: 0")
        #expect(lines.contains("events: none"))
    }
}

@Suite struct OUT002d_GateAndRendererTests {
    private func slide(_ words: String) -> SceneDescription {
        let style = TextStyle(fontName: "Helvetica Neue", fontSize: 60, color: .white)
        return SceneDescription(backgroundColor: .black, textLayers: [TextLayer(text: words, style: style, frame: NormalizedRect(x: 0.05, y: 0.2, width: 0.9, height: 0.5), fitFloor: 30)])
    }

    @Test func theGateSaysWhetherItIsHoldingAndWhetherTheSceneChanged() {
        let gate = ScenePreparationGate { _, _, _, _, _ in }       // never finishes
        let a = slide("A \(UUID())"), b = slide("B \(UUID())")
        _ = gate.sceneToDraw(a, width: 100, height: 100)
        #expect(gate.adoptedOnLastCall && !gate.isHolding)
        _ = gate.sceneToDraw(a, width: 100, height: 100)
        #expect(!gate.adoptedOnLastCall && !gate.isHolding)
        _ = gate.sceneToDraw(b, width: 100, height: 100)
        #expect(gate.isHolding && !gate.adoptedOnLastCall)
        _ = gate.sceneToDraw(b, width: 100, height: 100)
        _ = gate.sceneToDraw(b, width: 100, height: 100)
        _ = gate.sceneToDraw(b, width: 100, height: 100)         // the bound (3 held frames) is reached: drawn anyway
        #expect(gate.adoptedOnLastCall && !gate.isHolding)
    }

    @Test func aRenderedTickLeavesOneRecordOfItsPhases() throws {
        let layer = CAMetalLayer()
        layer.drawableSize = CGSize(width: 160, height: 90)
        let scene = SceneDescription(backgroundColor: .black, textLayers: [])
        let renderer = OutputRenderer(layer: layer, sceneProvider: { scene }, videoSource: nil, targetInterval: 1.0 / 60.0)
        try renderer.prepare()
        guard layer.nextDrawable() != nil else { return }        // no drawables without a display
        renderer.tick(linkTimestamp: 1, linkTarget: 2)
        let h = renderer.frameEvents.workHistogram
        #expect(h.ticks == 1)
        #expect(h.maxWorkMs >= 0)
        #expect(renderer.tickSamples.count == 1)
        let s = try #require(renderer.tickSamples.first)
        #expect(s.linkTimestamp == 1 && s.linkTarget == 2)
        #expect(s.sceneChanged)                                  // the first scene an output draws
        #expect(!s.skipped && !s.gateHolding)
        #expect(s.drawable >= 0 && s.build >= 0 && s.encode >= 0)
        renderer.stop()
    }
}
