// CUE-001 (AUTO-01, AUTO-02): running actions against a target with an injected clock.
import Testing
import Foundation
@testable import CueEngine

/// Test-only clock. Only the main actor touches it in these tests, hence unchecked.
final class ManualClock: CueClock, @unchecked Sendable {
    var time: TimeInterval = 100
    func now() -> TimeInterval { time }
    func advance(_ s: TimeInterval) { time += s }
}

@MainActor final class RecordingTarget: CueTarget {
    var log: [String] = []                 // "begin", "perform", "end" in call order
    var batches: [[CueAction]] = []        // every action attempted between begin and end
    var failing: [CueAction: String] = [:]
    var onPerform: ((CueAction) -> Void)?
    private var current: [CueAction] = []

    var delivered: [CueAction] { batches.flatMap { $0 } }

    func beginBatch() { log.append("begin"); current = [] }
    func perform(_ action: CueAction) throws {
        log.append("perform")
        current.append(action)
        onPerform?(action)
        if let why = failing[action] { throw CueTargetError(why) }
    }
    func endBatch() { log.append("end"); batches.append(current); current = [] }
}

private let look = UUID(), look2 = UUID(), prop = UUID(), msg = UUID(), asset = UUID(), asset2 = UUID(), timer = UUID()

@MainActor
private func makeExecutor(macros: MacroLibrary = MacroLibrary()) -> (CueExecutor, RecordingTarget, ManualClock) {
    let t = RecordingTarget(), c = ManualClock()
    return (CueExecutor(target: t, clock: c, macros: macros), t, c)
}

@MainActor @Suite struct CueExecutorOrderTests {
    @Test func actionsRunInTheDefinedOrderWhateverTheWrittenOrder() {
        let (ex, t, _) = makeExecutor()
        let written: [CueAction] = [
            .midiOut(.noteOn(channel: 1, note: 60, velocity: 100)),
            .startTimer(timer),
            .playAudio(assetID: asset),
            .playForeground(assetID: asset2),
            .showMessage(id: msg, fields: ["a": "b"]),
            .prop(id: prop, isOn: true),
            .selectLook(look),
            .transport(.next),
        ]
        ex.run(written, origin: .operatorTrigger)
        #expect(t.batches == [[
            .transport(.next),
            .selectLook(look),
            .showMessage(id: msg, fields: ["a": "b"]),
            .prop(id: prop, isOn: true),
            .playForeground(assetID: asset2),
            .playAudio(assetID: asset),
            .startTimer(timer),
            .midiOut(.noteOn(channel: 1, note: 60, velocity: 100)),
        ]])
    }

    @Test func actionsOfTheSameKindKeepTheirWrittenOrder() {
        let (ex, t, _) = makeExecutor()
        ex.run([.hideMessage(id: msg), .prop(id: prop, isOn: false), .showMessage(id: msg, fields: [:]),
                .resetTimer(timer), .startTimer(timer), .pauseTimer(timer),
                .stopForeground, .setBackground(assetID: asset), .playForeground(assetID: asset2),
                .stopAudio(assetID: asset), .playAudio(assetID: asset2),
                .selectLook(look), .selectLook(look2)], origin: .operatorTrigger)
        #expect(t.delivered == [
            .selectLook(look), .selectLook(look2),
            .hideMessage(id: msg), .prop(id: prop, isOn: false), .showMessage(id: msg, fields: [:]),
            .stopForeground, .setBackground(assetID: asset), .playForeground(assetID: asset2),
            .stopAudio(assetID: asset), .playAudio(assetID: asset2),
            .resetTimer(timer), .startTimer(timer), .pauseTimer(timer),
        ])
    }

    @Test func aMediaAndALookActionFireTogetherLookFirst() {
        // AUTO-01 acceptance: a slide with a media action and a Look action fires both, in a defined order.
        let (ex, t, _) = makeExecutor()
        let report = ex.run([.playForeground(assetID: asset), .selectLook(look)], origin: .slide)
        #expect(t.delivered == [.selectLook(look), .playForeground(assetID: asset)])
        #expect(report.issues.isEmpty)
    }

    @Test func oneTriggerIsOneBatchWithEveryActionInsideBeginAndEnd() {
        let (ex, t, _) = makeExecutor()
        let report = ex.run([.selectLook(look), .playAudio(assetID: asset), .startTimer(timer), .stopForeground, .prop(id: prop, isOn: true)], origin: .slide)
        #expect(t.log == ["begin", "perform", "perform", "perform", "perform", "perform", "end"])
        #expect(t.batches.count == 1)
        #expect(report.batchesDelivered == 1 && report.actionsDelivered == 5)
    }

    @Test func anEmptyListDeliversNothing() {
        let (ex, t, _) = makeExecutor()
        let report = ex.run([], origin: .slide)
        #expect(t.log.isEmpty)
        #expect(report == CueReport())
    }
}

@MainActor @Suite struct CueExecutorWaitTests {
    @Test func aWaitSplitsTheListIntoStagesDeliveredOnTime() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.selectLook(look), .wait(seconds: 2), .playAudio(assetID: asset), .wait(seconds: 3), .startTimer(timer)], origin: .slide)
        #expect(t.batches == [[.selectLook(look)]])
        #expect(ex.pendingStageCount == 2)
        clock.advance(1.9); #expect(ex.tick() == CueReport()); #expect(t.batches.count == 1)
        clock.advance(0.1)
        #expect(ex.tick().batchesDelivered == 1)
        #expect(t.batches == [[.selectLook(look)], [.playAudio(assetID: asset)]])
        clock.advance(2.9); _ = ex.tick(); #expect(t.batches.count == 2)
        clock.advance(0.1); _ = ex.tick()
        #expect(t.batches == [[.selectLook(look)], [.playAudio(assetID: asset)], [.startTimer(timer)]])
        #expect(ex.pendingStageCount == 0 && ex.nextDueTime == nil)
    }

    @Test func eachStageIsOrderedOnItsOwnAndStagesKeepTheirWrittenOrder() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.midiOut(.programChange(channel: 1, program: 1)), .selectLook(look),
                .wait(seconds: 1),
                .midiOut(.programChange(channel: 1, program: 2)), .selectLook(look2)], origin: .slide)
        clock.advance(1); ex.tick()
        #expect(t.batches == [
            [.selectLook(look), .midiOut(.programChange(channel: 1, program: 1))],
            [.selectLook(look2), .midiOut(.programChange(channel: 1, program: 2))],
        ])
    }

    @Test func aLeadingWaitDelaysEverything() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 1), .wait(seconds: 2), .selectLook(look)], origin: .operatorTrigger)
        #expect(t.batches.isEmpty)
        clock.advance(2.99); ex.tick(); #expect(t.batches.isEmpty)
        clock.advance(0.01); ex.tick(); #expect(t.batches == [[.selectLook(look)]])
    }

    @Test func aTrailingWaitAndEmptyStagesDeliverNothing() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.selectLook(look), .wait(seconds: 1)], origin: .slide)
        clock.advance(5); ex.tick()
        #expect(t.batches == [[.selectLook(look)]])
        #expect(ex.pendingStageCount == 0)
    }

    @Test func aZeroWaitStillSplitsButDeliversImmediatelyInOrder() {
        let (ex, t, _) = makeExecutor()
        ex.run([.midiOut(.programChange(channel: 1, program: 1)), .wait(seconds: 0), .selectLook(look)], origin: .slide)
        #expect(t.batches == [[.midiOut(.programChange(channel: 1, program: 1))], [.selectLook(look)]])
    }

    @Test func aLateTickDeliversEveryDueStageInOrderEachInItsOwnBatch() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 1), .selectLook(look), .wait(seconds: 1), .selectLook(look2)], origin: .slide)
        clock.advance(60)                               // the Mac slept
        let report = ex.tick()
        #expect(t.batches == [[.selectLook(look)], [.selectLook(look2)]])
        #expect(report.batchesDelivered == 2)
    }

    @Test func stageTimesAreFixedAtPlanTimeSoALateTickDoesNotShiftTheNextStage() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 2), .selectLook(look), .wait(seconds: 3), .selectLook(look2)], origin: .slide)   // due +2 and +5
        clock.advance(2.9); ex.tick()
        #expect(t.batches == [[.selectLook(look)]])
        clock.advance(2.0); ex.tick()                   // +4.9
        #expect(t.batches.count == 1)
        clock.advance(0.1); ex.tick()                   // +5.0
        #expect(t.batches.count == 2)
    }

    @Test func nextDueTimeIsTheEarliestPendingStage() {
        let (ex, _, clock) = makeExecutor()
        #expect(ex.nextDueTime == nil)
        ex.run([.wait(seconds: 4), .selectLook(look)], origin: .operatorTrigger)
        ex.run([.wait(seconds: 2), .selectLook(look2)], origin: .operatorTrigger)
        #expect(ex.nextDueTime == clock.time + 2)
    }

    @Test func invalidWaitsAreTreatedAsZeroAndReported() {
        let (ex, t, _) = makeExecutor()
        let report = ex.run([.wait(seconds: -1), .selectLook(look), .wait(seconds: .infinity), .selectLook(look2), .wait(seconds: .nan)], origin: .slide)
        #expect(t.delivered == [.selectLook(look), .selectLook(look2)])
        #expect(report.issues.count == 3)
        #expect(report.issues[0].message == "Wait of -1 s is not valid; treated as 0 s.")
    }
}

@MainActor @Suite struct CueExecutorFailureTests {
    @Test func aFailingActionDoesNotStopTheRestAndIsReportedInPlainText() {
        let (ex, t, _) = makeExecutor()
        t.failing[.playAudio(assetID: asset)] = "Audio device missing"
        let report = ex.run([.selectLook(look), .playAudio(assetID: asset), .startTimer(timer)], origin: .slide)
        #expect(t.delivered == [.selectLook(look), .playAudio(assetID: asset), .startTimer(timer)])
        #expect(t.log.last == "end")
        #expect(report.issues == [CueIssue(action: .playAudio(assetID: asset), message: "Play sound failed: Audio device missing")])
        #expect(report.actionsDelivered == 3)
    }

    @Test func aTargetErrorThatIsNotOursStillGivesText() {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        @MainActor final class Throwing: CueTarget {
            func beginBatch() {}
            func endBatch() {}
            func perform(_ action: CueAction) throws { throw Boom() }
        }
        let ex = CueExecutor(target: Throwing(), clock: ManualClock())
        let report = ex.run([.selectLook(look)], origin: .slide)
        #expect(report.issues.map(\.message) == ["Select Look failed: boom"])
    }

    @Test func failuresInALaterStageAreReportedByTheTickThatRanIt() {
        let (ex, t, clock) = makeExecutor()
        t.failing[.selectLook(look2)] = "no such Look"
        let first = ex.run([.selectLook(look), .wait(seconds: 1), .selectLook(look2)], origin: .slide)
        #expect(first.issues.isEmpty)
        clock.advance(1)
        #expect(ex.tick().issues.map(\.message) == ["Select Look failed: no such Look"])
    }

    @Test func unknownActionsAreSkippedAndReportedWithoutReachingTheTarget() {
        let (ex, t, _) = makeExecutor()
        let unknown = CueAction.unknown(.object(["kind": .string("dmx.set")]))
        let report = ex.run([unknown, .selectLook(look)], origin: .slide)
        #expect(t.delivered == [.selectLook(look)])
        #expect(report.issues.count == 1)
        #expect(report.issues[0].message.contains("dmx.set") && report.issues[0].message.contains("skipped"))
    }

    @Test func anInvalidMidiMessageIsSkippedAndReported() {
        let (ex, t, _) = makeExecutor()
        let report = ex.run([.midiOut(.noteOn(channel: 99, note: 1, velocity: 1)), .selectLook(look)], origin: .slide)
        #expect(t.delivered == [.selectLook(look)])
        #expect(report.issues.map(\.message) == ["Send MIDI was skipped: the message is not valid."])
    }
}

@MainActor @Suite struct CueExecutorMacroTests {
    private func library(_ macros: [Macro]) -> MacroLibrary {
        var lib = MacroLibrary()
        for m in macros {
            do { try lib.save(m) } catch { Issue.record("test macro rejected: \(error)") }
        }
        return lib
    }

    @Test func aMacroIsExpandedInPlaceBeforeOrderingAndSplittingOnItsWaits() {
        let m = Macro(id: UUID(), name: "Intro", steps: [.selectLook(look), .wait(seconds: 1), .playAudio(assetID: asset)])
        let (ex, t, clock) = makeExecutor(macros: library([m]))
        ex.run([.runMacro(m.id), .startTimer(timer)], origin: .operatorTrigger)
        #expect(t.batches == [[.selectLook(look)]])          // timer is in stage 2 because the macro's wait comes first
        clock.advance(1); ex.tick()
        #expect(t.batches[1] == [.playAudio(assetID: asset), .startTimer(timer)])
    }

    @Test func theSameMacroFromAButtonAndFromASlideGivesTheSameDeliveredActions() {
        // AUTO-02 acceptance (rules half): one macro, same result from any entry point.
        let m = Macro(id: UUID(), name: "Three", steps: [.selectLook(look), .playAudio(assetID: asset), .startTimer(timer)])
        let lib = library([m])
        let (e1, t1, _) = makeExecutor(macros: lib)
        let (e2, t2, _) = makeExecutor(macros: lib)
        let (e3, t3, _) = makeExecutor(macros: lib)
        e1.run([.runMacro(m.id)], origin: .operatorTrigger)
        e2.run([.runMacro(m.id)], origin: .slide)
        e3.run([.runMacro(m.id)], origin: .schedule)
        #expect(t1.batches == t2.batches && t2.batches == t3.batches)
        #expect(t1.delivered.count == 3)
    }

    @Test func aMissingMacroIsReportedAndSkippedAndTheRestRuns() {
        let (ex, t, _) = makeExecutor()
        let ghost = UUID()
        let report = ex.run([.runMacro(ghost), .selectLook(look)], origin: .operatorTrigger)
        #expect(t.delivered == [.selectLook(look)])
        #expect(report.issues.count == 1)
        #expect(report.issues[0].message.contains("not found"))
        #expect(report.issues[0].message.contains(ghost.uuidString))
    }

    @Test func aCycleInDamagedStorageStopsTheExpansionAndIsReported() {
        let a = UUID()
        let lib = MacroLibrary(unvalidated: [Macro(id: a, name: "Loop", steps: [.selectLook(look), .runMacro(a)])])
        let (ex, t, _) = makeExecutor(macros: lib)
        let report = ex.run([.runMacro(a)], origin: .operatorTrigger)
        #expect(t.delivered == [.selectLook(look)])            // the rest of the macro still ran, once
        #expect(report.issues.count == 1)
        #expect(report.issues[0].message.contains("Loop") && report.issues[0].message.localizedCaseInsensitiveContains("itself"))
    }

    @Test func aLongerCycleInDamagedStorageNamesThePath() {
        let a = UUID(), b = UUID()
        let lib = MacroLibrary(unvalidated: [
            Macro(id: a, name: "Ping", steps: [.runMacro(b)]),
            Macro(id: b, name: "Pong", steps: [.selectLook(look), .runMacro(a)]),
        ])
        let (ex, t, _) = makeExecutor(macros: lib)
        let report = ex.run([.runMacro(a)], origin: .operatorTrigger)
        #expect(t.delivered == [.selectLook(look)])
        #expect(report.issues.map(\.message) == ["Macro cycle: Ping \u{2192} Pong \u{2192} Ping; the repeat was skipped."])
    }

    @Test func nestingBeyondTheLimitIsCutOffAtRunTimeToo() {
        let ids = (0..<10).map { _ in UUID() }
        var macros: [Macro] = []
        for i in 0..<10 {
            var steps: [CueAction] = [.prop(id: ids[i], isOn: true)]
            if i < 9 { steps.append(.runMacro(ids[i + 1])) }
            macros.append(Macro(id: ids[i], name: "M\(i + 1)", steps: steps))
        }
        let (ex, t, _) = makeExecutor(macros: MacroLibrary(unvalidated: macros))
        let report = ex.run([.runMacro(ids[0])], origin: .operatorTrigger)
        #expect(t.delivered.count == 8)                        // M1 to M8 ran, M9 was refused
        #expect(report.issues.count == 1 && report.issues[0].message.contains("8"))
    }

    @Test func transportInsideASlideRunIsSkippedEvenFromAMacroAndTheRestRuns() {
        let m = Macro(id: UUID(), name: "Sneaky", steps: [.selectLook(look), .transport(.next)])
        let (ex, t, _) = makeExecutor(macros: library([m]))
        let report = ex.run([.transport(.clear), .runMacro(m.id), .playAudio(assetID: asset)], origin: .slide)
        #expect(t.delivered == [.selectLook(look), .playAudio(assetID: asset)])
        #expect(report.issues.map(\.message) == [
            "Clear was skipped: slide actions cannot move the show.",
            "Next slide was skipped: slide actions cannot move the show.",
        ])
    }

    @Test func transportIsAllowedForButtonsMidiAndTheSchedule() {
        for origin in [CueOrigin.operatorTrigger, .schedule, .marker] {
            let (ex, t, _) = makeExecutor()
            let report = ex.run([.transport(.next)], origin: origin)
            #expect(t.delivered == [.transport(.next)])
            #expect(report.issues.isEmpty)
        }
    }
}

@MainActor @Suite struct CueExecutorCancelTests {
    @Test func aNewSlideTriggerCancelsPendingStagesOfThePreviousSlideTrigger() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        clock.advance(2)
        ex.run([.selectLook(look)], origin: .slide)
        #expect(ex.pendingStageCount == 0)
        clock.advance(10); ex.tick()
        #expect(t.delivered == [.selectLook(look)])
    }

    @Test func aNewSlideTriggerLeavesButtonMacrosAndScheduleRunsAlone() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .operatorTrigger)
        ex.run([.wait(seconds: 5), .stopAudio(assetID: asset2)], origin: .schedule)
        ex.run([.selectLook(look)], origin: .slide)
        #expect(ex.pendingStageCount == 2)
        clock.advance(5); ex.tick()
        #expect(t.delivered == [.selectLook(look), .playAudio(assetID: asset), .stopAudio(assetID: asset2)])
    }

    @Test func aSlideTriggerWithoutAnyActionsStillCancelsThePreviousOnesPendingStages() {
        // The app calls run with whatever the new slide has, which may be nothing.
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        ex.run([], origin: .slide)
        clock.advance(10); ex.tick()
        #expect(t.delivered.isEmpty)
    }

    @Test func aStopCommandRunThroughTheExecutorCancelsEveryOtherRunsPendingStages() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset2)], origin: .operatorTrigger)
        ex.run([.transport(.stop), .wait(seconds: 1), .selectLook(look)], origin: .operatorTrigger)
        #expect(ex.pendingStageCount == 1)                    // only the stop run's own later stage survives
        clock.advance(10); ex.tick()
        #expect(t.delivered == [.transport(.stop), .selectLook(look)])
    }

    @Test func stopCalledByTheAppCancelsEverything() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset2)], origin: .operatorTrigger)
        ex.stop()
        #expect(ex.pendingStageCount == 0)
        clock.advance(10); ex.tick()
        #expect(t.delivered.isEmpty)
    }

    @Test(arguments: [CueTransport.blackout(.on), .blackout(.toggle), .clear, .clearAll, .next, .goToSlide(index: 2)])
    func blackoutClearAndOtherMovesDoNotCancelPendingStages(_ command: CueTransport) {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        ex.run([.transport(command)], origin: .operatorTrigger)
        #expect(ex.pendingStageCount == 1)
        clock.advance(5); ex.tick()
        #expect(t.delivered == [.transport(command), .playAudio(assetID: asset)])
    }
}

@MainActor @Suite struct CueExecutorReentrancyTests {
    @Test func actionsArrivingWhileABatchRunsAreQueuedNotInterleaved() {
        let (ex, t, _) = makeExecutor()
        var nested: CueReport?
        t.onPerform = { [unowned ex] a in
            if a == .selectLook(look) { nested = ex.run([.playAudio(assetID: asset), .startTimer(timer)], origin: .operatorTrigger) }
        }
        let outer = ex.run([.selectLook(look), .stopForeground], origin: .operatorTrigger)
        #expect(nested?.wasQueued == true)
        #expect(t.log == ["begin", "perform", "perform", "end", "begin", "perform", "perform", "end"])
        #expect(t.batches == [[.selectLook(look), .stopForeground], [.playAudio(assetID: asset), .startTimer(timer)]])
        #expect(outer.batchesDelivered == 2 && outer.actionsDelivered == 4)
        #expect(outer.wasQueued == false)
    }

    @Test func queuedRunsKeepTheirArrivalOrder() {
        let (ex, t, _) = makeExecutor()
        t.onPerform = { [unowned ex] a in
            if a == .selectLook(look) {
                ex.run([.selectLook(look2)], origin: .operatorTrigger)
                ex.run([.stopForeground], origin: .operatorTrigger)
            }
        }
        ex.run([.selectLook(look)], origin: .operatorTrigger)
        #expect(t.batches == [[.selectLook(look)], [.selectLook(look2)], [.stopForeground]])
    }

    @Test func aRunQueuedDuringATickIsDeliveredAfterThatStage() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 1), .selectLook(look)], origin: .operatorTrigger)
        t.onPerform = { [unowned ex] a in
            if a == .selectLook(look) { ex.run([.stopForeground], origin: .operatorTrigger) }
        }
        clock.advance(1)
        let report = ex.tick()
        #expect(t.batches == [[.selectLook(look)], [.stopForeground]])
        #expect(report.batchesDelivered == 2)
    }

    @Test func aQueuedSlideRunStillCancelsThePreviousSlideRunWhenItsTurnComes() {
        let (ex, t, clock) = makeExecutor()
        ex.run([.wait(seconds: 5), .playAudio(assetID: asset)], origin: .slide)
        t.onPerform = { [unowned ex] a in
            if a == .stopForeground { ex.run([.selectLook(look)], origin: .slide) }
        }
        ex.run([.stopForeground], origin: .operatorTrigger)
        #expect(ex.pendingStageCount == 0)
        clock.advance(10); ex.tick()
        #expect(t.delivered == [.stopForeground, .selectLook(look)])
    }
}

@Suite struct SystemClockTests {
    @Test func systemClockNeverGoesBackward() {
        let c = SystemCueClock()
        var last = c.now()
        for _ in 0..<1000 { let n = c.now(); #expect(n >= last); last = n }
    }
}
