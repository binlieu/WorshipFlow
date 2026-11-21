// FIX-D S4: every output carries its own connector number in its picture; the kit loops each of the four outputs back in
// turn (the tester moves the cables when asked) and "Four outputs at once" is PASSED only for connectors whose identity was
// seen on an input. SIMULATED: the card is the kit's profiled double, with two outputs wired the wrong way round on request.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

/// Passes every question to another tester and remembers what was asked.
final class RecordingInteraction: HardwareTestInteraction, @unchecked Sendable {
    private let inner: any HardwareTestInteraction
    private let log = PromptLog()
    private let override: (@Sendable (HardwarePrompt) -> HardwareAnswer?)?
    init(_ inner: any HardwareTestInteraction, override: (@Sendable (HardwarePrompt) -> HardwareAnswer?)? = nil) {
        self.inner = inner
        self.override = override
    }
    func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        log.add(prompt.kind.rawValue)
        if let a = override?(prompt) { return a }
        return await inner.ask(prompt)
    }
    var kinds: [String] { log.items }
}

extension HWTEST_Heavy {
@Suite struct FIXD_S4_IdentityTests {
    private func run(_ injecting: Set<HardwareTestInjection> = [], override: (@Sendable (HardwarePrompt) -> HardwareAnswer?)? = nil)
        async -> (report: HardwareTestReport, asked: [String]) {
        let rig = HardwareTestRig.simulatedCard(injecting: injecting)
        let tester = RecordingInteraction(rig.interaction, override: override)
        let report = await runSteps([.fourOutputs], interaction: tester, rig: rig)
        return (report, tester.kinds)
    }

    @Test func aCleanCardHasEveryConnectorsOwnPictureSeenAndPasses() async {
        let (report, asked) = await run()
        let s = report.step(.fourOutputs)
        #expect(s.outcome == .passed, "\(s.summary)")
        for c in 1...4 {
            #expect(s.value("Connector \(c) picture")?.hasPrefix("confirmed") == true, "\(c): \(s.value("Connector \(c) picture") ?? "nil")")
            #expect(s.value("Connector \(c) result") == "PASSED")
        }
        // the cables are asked for in turn, and taken off before the four outputs run together
        #expect(asked == ["connectLoopbackCable", "moveCables", "removeCables"], "\(asked)")
    }

    @Test func twoConnectorsWiredTheWrongWayRoundInsideTheCardAreCaught() async {
        let (report, _) = await run([.swappedConnectors])
        let s = report.step(.fourOutputs)
        #expect(s.outcome == .failed, "\(s.summary)")
        #expect(s.value("Connector 3 result") == "PASSED" && s.value("Connector 4 result") == "PASSED")
        #expect(s.value("Connector 1 result") == "FAILED" && s.value("Connector 2 result") == "FAILED")
        #expect(s.value("Connector 1 picture")?.hasPrefix("WRONG") == true)
        #expect(s.value("Connector 1 picture")?.contains("picture sent on SDI 2") == true, "\(s.value("Connector 1 picture") ?? "")")
        #expect(s.value("Connector 2 picture")?.contains("picture sent on SDI 1") == true)
        #expect(s.summary.contains("numbering"), "\(s.summary)")
    }

    @Test func twoConnectorsSwappedAcrossTheHalvesAreNeverCountedAsPassed() async {
        // outputs 2 and 4 leave by each other's connector: with 4 busy as an input, the cable from SDI 2 carries nothing
        let card = SimulatedProfileCard(faults: .init(swappedOutputs: [2, 4]))
        let rig = HardwareTestRig.simulated(card: card)
        let report = await runSteps([.fourOutputs], rig: rig)
        let s = report.step(.fourOutputs)
        #expect(s.outcome != .passed, "\(s.summary)")
        #expect(s.value("Connector 2 result") != "PASSED" && s.value("Connector 4 result") != "PASSED")
        #expect(s.value("Connector 1 result") == "PASSED" && s.value("Connector 3 result") == "PASSED")
    }

    @Test func skippingTheSecondSetOfCablesLeavesTwoConnectorsUnchecked() async {
        let (report, _) = await run(override: { $0.kind == .moveCables ? .skip : nil })
        let s = report.step(.fourOutputs)
        #expect(s.outcome.rawValue == "partial", "\(s.summary)")
        #expect(s.value("Connector 1 result") == "PASSED" && s.value("Connector 2 result") == "PASSED")
        #expect(s.value("Connector 3 result") == "ran, identity not checked" && s.value("Connector 4 result") == "ran, identity not checked")
        #expect(s.summary.contains("SDI 3, SDI 4 ran, identity not checked"), "\(s.summary)")
    }

    @Test func skippingEveryCableMeansNoConnectorIsCountedAsPassed() async {
        let (report, asked) = await run(override: { $0.kind == .connectLoopbackCable ? .skip : nil })
        let s = report.step(.fourOutputs)
        #expect(s.outcome.rawValue == "partial")
        for c in 1...4 { #expect(s.value("Connector \(c) result") == "ran, identity not checked") }
        #expect(!asked.contains("moveCables") && !asked.contains("removeCables"), "\(asked)")
    }

    @Test func aCableThatCarriesNothingIsNotCountedEvenThoughTheTesterSaidContinue() async {
        // the tester presses Continue but places no cable
        let rig = HardwareTestRig.simulatedCard()
        let nothing = ScriptedInteraction { _ in .proceed }
        let report = await runSteps([.fourOutputs], cabled: false, interaction: nothing, rig: HardwareTestRig(provider: rig.provider, clock: rig.clock, interaction: nothing, device: rig.device))
        let s = report.step(.fourOutputs)
        #expect(s.outcome.rawValue == "partial", "\(s.summary)")
        #expect(s.value("Connector 3 picture")?.contains("no signal reached") == true, "\(s.value("Connector 3 picture") ?? "")")
    }

    @Test func theIdentityIsInsideTheFrameCounterAndSurvivesTheCheck() {
        let base = CounterFrameSource(width: 1920, height: 1080)
        for c in 1...4 {
            let frame = HardwareTestSteps.IdentityFrameSource(connector: c, base: base).frame(index: 12_345)
            #expect(HardwareTestSteps.ConnectorIdentity.decode(frame) == c)
            // it is still a valid counter, so the older checks that read the counter keep working
            #expect(TestPattern.decodeFrameIndex(from: frame) == HardwareTestSteps.ConnectorIdentity.frameIndex(connector: c, counter: 12_345))
        }
        #expect(HardwareTestSteps.ConnectorIdentity.decode(base.frame(index: 7)) == nil)       // a plain counter has no connector in it
    }

    @Test func aCardThatCannotSendOnEveryConnectorSkipsTheStepWithTheReason() async {
        let card = SimulatedProfileCard(start: [.keying, .keying])
        let report = await runSteps([.fourOutputs], rig: HardwareTestRig.simulated(card: card))
        let s = report.step(.fourOutputs)
        #expect(s.outcome == .skipped)
        #expect(s.summary.contains("only SDI 2, 4"), "\(s.summary)")
    }
}
}
