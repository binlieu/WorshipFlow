// UI-006g (CU-22): a dry run shows what a run would do without delivering anything.
import Testing
import Foundation
@testable import CueEngine

@MainActor
private final class CountingTarget: CueTarget {
    var performed = 0
    func beginBatch() {}
    func perform(_ action: CueAction) throws { performed += 1 }
    func endBatch() {}
}

private struct FixedClock: CueClock { func now() -> TimeInterval { 0 } }

@MainActor
@Suite struct DryRunTests {
    private func executor(_ macros: [Macro] = []) -> (CueExecutor, CountingTarget) {
        let target = CountingTarget()
        return (CueExecutor(target: target, clock: FixedClock(), macros: MacroLibrary(unvalidated: macros)), target)
    }

    @Test func stagesAreInTheOrderARunDeliversThem() {
        let look = UUID(), timer = UUID()
        let (ex, _) = executor()
        // Written timer, then Look, then transport: a run delivers the transport first, then the Look, then the timer.
        let dry = ex.dryRun([.startTimer(timer), .selectLook(look), .transport(.next)], origin: .operatorTrigger)
        #expect(dry.stages.count == 1)
        #expect(dry.stages[0].delay == 0)
        #expect(dry.stages[0].actions == [.transport(.next), .selectLook(look), .startTimer(timer)])
        #expect(dry.issues.isEmpty)
    }

    @Test func aWaitSplitsTheListAndAddsUp() {
        let a = UUID(), b = UUID()
        let (ex, _) = executor()
        let dry = ex.dryRun([.selectLook(a), .wait(seconds: 2), .selectLook(b), .wait(seconds: 1.5), .stopForeground], origin: .operatorTrigger)
        #expect(dry.stages.map(\.delay) == [0, 2, 3.5])
        #expect(dry.stages.map(\.actions.count) == [1, 1, 1])
        #expect(dry.totalDuration == 3.5)
        #expect(dry.actionCount == 3)
    }

    @Test func aCalledMacroIsExpandedInPlaceAndAMissingOneIsReported() {
        let look = UUID(), gone = UUID()
        let inner = Macro(name: "Inner", steps: [.selectLook(look)])
        let (ex, _) = executor([inner])
        let dry = ex.dryRun([.runMacro(inner.id), .runMacro(gone)], origin: .operatorTrigger)
        #expect(dry.stages.flatMap(\.actions) == [.selectLook(look)])
        #expect(dry.issues.count == 1)
    }

    @Test func aSlideRunReportsATransportStepAsSkipped() {
        let (ex, _) = executor()
        let dry = ex.dryRun([.transport(.next), .stopForeground], origin: .slide)
        #expect(dry.stages.flatMap(\.actions) == [.stopForeground])
        #expect(dry.issues.count == 1)
    }

    @Test func nothingIsDeliveredAndNothingIsQueued() {
        let (ex, target) = executor()
        _ = ex.dryRun([.transport(.next), .wait(seconds: 5), .stopForeground], origin: .operatorTrigger)
        #expect(target.performed == 0)
        #expect(ex.pendingStageCount == 0)
        #expect(ex.nextDueTime == nil)
    }

    @Test func dryRunUsesTheSamePlanARunDoes() {
        let (ex, target) = executor()
        let actions: [CueAction] = [.stopForeground, .transport(.clear), .wait(seconds: 0), .selectLook(UUID())]
        let dry = ex.dryRun(actions, origin: .operatorTrigger)
        let report = ex.run(actions, origin: .operatorTrigger)
        #expect(report.actionsDelivered == dry.actionCount)
        #expect(target.performed == dry.actionCount)
    }
}
