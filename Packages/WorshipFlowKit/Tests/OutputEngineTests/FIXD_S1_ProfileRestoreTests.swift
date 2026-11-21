// FIX-D S1: the kit records the card's profile and layout before any step, puts the profile back after the fill and key
// step without asking, verifies it, and picks every step's connectors from the layout the card has NOW. Simulated: the
// card here is the kit's own profiled double, which models the vendor manual's table and nothing about a real card.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_S1_ProfileRestoreTests {
    private func config(unplug: Bool = false) -> HardwareTestConfiguration {
        var c = HardwareTestConfiguration.tiny
        c.includeUnplugTest = unplug
        return c
    }

    private func run(_ card: SimulatedProfileCard, ids: Set<HardwareTestStepID>, unplug: Bool = false,
                     interaction: (any HardwareTestInteraction)? = nil) async -> HardwareTestReport {
        let rig = HardwareTestRig.simulated(card: card)
        return await runSteps(ids, config: config(unplug: unplug), interaction: interaction, rig: rig)
    }

    // MARK: the profile is put back, and later steps work

    @Test func theProfileIsRestoredAfterFillAndKeyAndTheLaterStepsRunInTheOriginalLayout() async {
        let card = SimulatedProfileCard(scope: .onePair)
        let report = await run(card, ids: [.outputRun, .fillKeyLoopback, .modeSweep, .unplugReplug], unplug: true)
        #expect(card.profile(ofPair: 0) == .halfDuplex && card.profile(ofPair: 1) == .halfDuplex)
        #expect(report.profileRestore?.state == .restoredAndVerified, "\(String(describing: report.profileRestore))")
        #expect(report.profileAtStart?.contains("connectors 1 and 2: half duplex") == true)
        #expect(report.step(.fillKeyLoopback).outcome == .passed, "\(report.step(.fillKeyLoopback).summary)")
        for id in [HardwareTestStepID.modeSweep, .unplugReplug] {
            let s = report.step(id)
            #expect(s.outcome == .passed, "\(id): \(s.summary)")
            #expect(s.profileNote == nil)
        }
        #expect(HardwareTestSummary.render(report).components(separatedBy: "\n")[0].contains("NOT RESTORED") == false)
    }

    @Test func whenAProfileChangeMovesBothPairsTheKeyedLoopbackIsNotWiredAndNothingIsReportedFalsely() async {
        let card = SimulatedProfileCard(scope: .bothPairs)
        let report = await run(card, ids: [.fillKeyLoopback, .modeSweep])
        // after the switch both pairs have a lower connector that can only receive and an upper one that can only send,
        // so the two inputs a fill and key loopback needs do not exist: the step says so instead of failing on a guess
        let key = report.step(.fillKeyLoopback)
        #expect(key.outcome != .failed && key.outcome != .passed, "\(key.summary)")
        #expect(key.summary.contains("can receive"), "\(key.summary)")
        #expect(card.profile(ofPair: 0) == .halfDuplex && card.profile(ofPair: 1) == .halfDuplex)
        #expect(report.profileRestore?.state == .restoredAndVerified)
        #expect(report.step(.modeSweep).outcome == .passed, "\(report.step(.modeSweep).summary)")
    }

    // MARK: restore fails or cannot be verified

    @Test func aProfileThatCouldNotBeRestoredIsSaidInTheHeadlineAndTheLaterStepsAreLabelled() async {
        let card = SimulatedProfileCard(scope: .onePair, faults: .init(restoreFails: true))
        let report = await run(card, ids: [.fillKeyLoopback, .modeSweep, .fourOutputs, .unplugReplug], unplug: true)
        #expect(report.profileRestore?.state == .failed)
        let headline = HardwareTestSummary.render(report).components(separatedBy: "\n")[0]
        #expect(headline.contains("NOT RESTORED") && headline.contains("keying profile"), "\(headline)")
        // no false "not supported": the sweep asks the connector that can output in this layout
        let sweep = report.step(.modeSweep)
        #expect(sweep.outcome == .passed, "\(sweep.summary)")
        #expect(sweep.profileNote?.contains("keying profile") == true)
        #expect(report.step(.unplugReplug).outcome == .passed, "\(report.step(.unplugReplug).summary)")
        #expect(report.step(.unplugReplug).profileNote?.contains("keying profile") == true)
        // four plain outputs are impossible in this layout: skipped with the reason, not failed
        let four = report.step(.fourOutputs)
        #expect(four.outcome == .skipped && four.summary.contains("only"), "\(four.summary)")
        #expect(four.profileNote?.contains("keying profile") == true)
        // the step that changed the profile is not labelled: it ran in the keying profile on purpose
        #expect(report.step(.fillKeyLoopback).profileNote == nil)
    }

    @Test func aRestoreThatReturnsButChangesNothingIsNotVerified() async {
        let card = SimulatedProfileCard(scope: .onePair, faults: .init(restoreHasNoEffect: true))
        let report = await run(card, ids: [.fillKeyLoopback, .modeSweep])
        #expect(report.profileRestore?.state == .notVerified, "\(String(describing: report.profileRestore))")
        #expect(HardwareTestSummary.render(report).components(separatedBy: "\n")[0].contains("NOT RESTORED"))
        #expect(report.step(.modeSweep).profileNote?.contains("keying profile") == true)
    }

    @Test func aCardThatCannotRestoreItsProfileIsReportedAsNotVerified() async {
        let card = SimulatedProfileCard(scope: .onePair)
        let rig = HardwareTestRig.simulated(card: card)
        var device = rig.provider.devices()[0]
        device.restoreProfiles = nil
        let patched = device
        let provider = HardwareTestProvider(isSimulated: true, devices: { [patched] }, driver: rig.provider.driver)
        let report = await runSteps([.fillKeyLoopback, .modeSweep], config: config(),
                                    rig: HardwareTestRig(provider: provider, clock: rig.clock, interaction: rig.interaction, device: rig.device))
        #expect(report.profileRestore?.state == .notVerified)
        #expect(report.step(.modeSweep).profileNote != nil)
    }

    @Test func aDeclinedChangeLeavesTheProfileAloneAndSaysNothingAboutRestoring() async {
        let card = SimulatedProfileCard(scope: .onePair)
        let declining = ScriptedInteraction { p in p.kind == .changeProfile ? .skip : .proceed }
        let report = await run(card, ids: [.fillKeyLoopback, .modeSweep], interaction: declining)
        #expect(report.step(.fillKeyLoopback).outcome == .skipped)
        #expect(report.profileRestore == nil)
        #expect(report.step(.modeSweep).profileNote == nil)
    }

    @Test func theCardNeverNeedingAChangeLeavesNoRestoreRecord() async {
        let card = SimulatedProfileCard(scope: .onePair, start: [.keying, .halfDuplex])
        let report = await run(card, ids: [.fillKeyLoopback, .modeSweep])
        #expect(report.profileRestore == nil)
        #expect(report.profileAtStart?.contains("connectors 1 and 2: one sub-device, full duplex") == true)
    }

    // MARK: the layout is recorded before any step and the connectors come from it

    @Test func theLayoutAtTheStartIsInTheReport() async {
        let report = await run(SimulatedProfileCard(), ids: [.environment])
        #expect(report.profileAtStart?.contains("connectors 3 and 4: half duplex") == true)
        #expect(report.profileAtStart?.contains("SDI 1: out/in") == true, "\(String(describing: report.profileAtStart))")
    }

    @Test func aCardThatStartsInTheKeyingProfileHasItsOutputOnTheConnectorThatCanSendIt() async {
        // connector 1 of a keying pair cannot send plain output: the output run uses SDI 2, not a fixed SDI 1
        let card = SimulatedProfileCard(scope: .onePair, start: [.keying, .halfDuplex])
        let report = await run(card, ids: [.outputRun, .modeSweep, .loopback])
        let out = report.step(.outputRun)
        #expect(out.outcome == .passed, "\(out.summary)")
        #expect(out.value("Connector") == "SDI 2")
        let sweep = report.step(.modeSweep)
        #expect(sweep.outcome == .passed, "\(sweep.summary)")
        let loop = report.step(.loopback)
        #expect(loop.value("Output") == "SDI 2", "\(loop.summary)")
    }

    // MARK: the planner

    @Test func thePlannerFollowsTheLayoutAndNeverAFixedNumber() {
        let keying = SimulatedProfileCard(start: [.keying, .halfDuplex]).info
        #expect(HardwareTestLayout.outputs(keying) == [2, 3, 4])
        #expect(HardwareTestLayout.plainOutput(keying, prefer: 1) == 2)
        #expect(HardwareTestLayout.loopback(keying, preferOutput: 1, preferInput: 3).map { [$0.output, $0.input] } == [2, 3])
        let both = SimulatedProfileCard(start: [.keying, .keying]).info
        #expect(HardwareTestLayout.outputs(both) == [2, 4])
        if case .failure(let why) = HardwareTestLayout.keyed(both, first: 1, preferA: 3, preferB: 4) {
            #expect(why.text.contains("only SDI 3 can receive"), "\(why.text)")
        } else { Issue.record("the keyed plan should not exist when only one input can receive") }
        let half = SimulatedProfileCard().info
        if case .success(let plan) = HardwareTestLayout.keyed(half, first: 1, preferA: 3, preferB: 4) {
            #expect(plan == HardwareKeyedPlan(first: 1, fillConnector: 2, keyConnector: 1, inputA: 3, inputB: 4))
            #expect(plan.cables == [HardwareCable(output: 1, input: 3), HardwareCable(output: 2, input: 4)])
        } else { Issue.record("a half-duplex card can be wired for fill and key") }
    }
}
}
