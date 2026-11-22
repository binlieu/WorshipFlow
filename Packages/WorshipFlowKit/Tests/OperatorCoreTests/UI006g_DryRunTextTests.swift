// UI-006g (CU-22): the words of a dry run, and the model's dry run of a macro.
import Testing
import Foundation
import Persistence
import CueEngine
import CueStore
@testable import OperatorCore

@MainActor
@Suite struct UI006g_DryRunTextTests {
    private func rig() async throws -> (cue: CueModel, show: FakeShow) {
        let library = try LibraryStore.inMemory()
        let show = FakeShow()
        let cue = CueModel(store: CueStore(library: library), ports: CuePorts(transport: WorkspaceModel(store: library), looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock())
        await cue.reload()
        return (cue, show)
    }

    @Test func aMacroReadsInDeliveryOrderWithItsWaitsAndTheScreensItCanChange() async throws {
        let r = try await rig()
        let look = UUID(), timer = UUID()
        let choices = CueChoices(looks: [CueChoice(id: look, name: "Worship")], timers: [CueChoice(id: timer, name: "Service")])
        let macro = try #require(await r.cue.createMacro(name: "Start"))
        await r.cue.setSteps([.startTimer(timer), .selectLook(look), .wait(seconds: 2), .stopForeground], of: macro.id)

        let summary = try #require(r.cue.dryRun(of: macro.id, choices: choices))
        #expect(summary.headline == "3 actions over 2 s")
        #expect(summary.groups.map(\.when) == ["Right away", "After 2 s"])
        #expect(summary.groups[0].lines.map(\.title) == ["Set Look", "Start timer"])      // the Look is delivered before the timer
        #expect(summary.groups[0].lines.map(\.number) == [1, 2])
        #expect(summary.groups[1].lines.map(\.number) == [3])
        #expect(summary.screens == [.audience, .stage, .broadcast])
        #expect(summary.brokenCount == 0 && summary.issues.isEmpty)
    }

    @Test func aStepThatPointsAtSomethingGoneIsCountedAndNothingIsRun() async throws {
        let r = try await rig()
        let macro = try #require(await r.cue.createMacro(name: "Old"))
        await r.cue.setSteps([.selectLook(UUID())], of: macro.id)
        let summary = try #require(r.cue.dryRun(of: macro.id, choices: CueChoices()))
        #expect(summary.brokenCount == 1)
        #expect(summary.groups[0].lines[0].isBroken)
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
        #expect(r.cue.activity.isEmpty)
    }

    @Test func anEmptyMacroSaysSo() async throws {
        let r = try await rig()
        let macro = try #require(await r.cue.createMacro(name: "Empty"))
        let summary = try #require(r.cue.dryRun(of: macro.id, choices: CueChoices()))
        #expect(summary.headline == "Nothing would run")
        #expect(summary.isEmpty)
    }

    @Test func aMissingMacroHasNoDryRun() async throws {
        let r = try await rig()
        #expect(r.cue.dryRun(of: UUID(), choices: CueChoices()) == nil)
    }

    @Test func deletingACalledMacroLeavesNothingToRun() async throws {
        let r = try await rig()
        let macro = try #require(await r.cue.createMacro(name: "Outer"))
        let inner = try #require(await r.cue.createMacro(name: "Inner"))
        await r.cue.setSteps([.runMacro(inner.id)], of: macro.id)
        _ = await r.cue.deleteMacro(inner.id, force: true)
        let summary = try #require(r.cue.dryRun(of: macro.id, choices: CueChoices()))
        #expect(summary.headline == "Nothing would run")
    }

    @Test func theHeadlineHandlesOneActionAndFractions() {
        #expect(CueDryRunText.headline(count: 1, duration: 0) == "1 action, all at once")
        #expect(CueDryRunText.headline(count: 2, duration: 0.25) == "2 actions over 0.3 s")
        #expect(CueDryRunText.when(1.5) == "After 1.5 s")
        #expect(CueDryRunText.when(0) == "Right away")
    }
}
