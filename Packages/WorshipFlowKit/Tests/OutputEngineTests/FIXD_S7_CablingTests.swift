// FIX-D S7: what fill and key reports as measured fact depends on the cables, so a result that is the reverse of the
// device's report asks the tester to confirm the cables and repeats once; the report keeps both runs and words the finding
// as an observation. Only pre-FIX-D API here, so the tests can be run against the earlier kit.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_S7_CablingTests {
    @Test func aReversedResultAsksTheTesterToConfirmTheCablesAndRunsOnceMore() async {
        let seen = PromptLog()
        let tester = ScriptedInteraction { p in seen.add(p.kind.rawValue); return .proceed }
        let report = await runSteps([.fillKeyLoopback], faults: SimulatedFaults(swapFillAndKey: true), interaction: tester)
        let s = report.step(.fillKeyLoopback)
        #expect(seen.items.contains("confirmCables"), "\(seen.items)")
        #expect(seen.items.filter { $0 == "confirmCables" }.count == 1)
        #expect(s.outcome == .failed)
        #expect(s.summary.contains("reversed"))
        // both runs are kept
        #expect(s.measurements.contains { $0.name.hasPrefix("First run") })
        #expect(s.measurements.contains { $0.name.hasPrefix("Route measured") })
        // the finding is an observation that depends on the cabling
        let finding = s.findings.joined(separator: "\n")
        #expect(finding.contains("with the cables as instructed"), "\(finding)")
        #expect(finding.contains("Two cables swapped would look the same"), "\(finding)")
        #expect(!finding.contains("(measured, with the cables as the guide says)"))
    }

    @Test func aCorrectResultIsNotRepeatedOrQuestioned() async {
        let seen = PromptLog()
        let tester = ScriptedInteraction { p in seen.add(p.kind.rawValue); return .proceed }
        let report = await runSteps([.fillKeyLoopback], interaction: tester)
        #expect(report.step(.fillKeyLoopback).outcome == .passed)
        #expect(!seen.items.contains("confirmCables"))
        #expect(!report.step(.fillKeyLoopback).measurements.contains { $0.name.hasPrefix("First run") })
    }

    @Test func crossedCablesThatTheTesterFixesWhenAskedAreNotReportedAsAReversedCard() async {
        let rig = HardwareTestRig.simulated()
        let device = rig.device
        // the two cables are crossed: SDI 1 to SDI 4 and SDI 2 to SDI 3
        device.connect(output: 1, toInput: 4)
        device.connect(output: 2, toInput: 3)
        let tester = ScriptedInteraction { p in
            if p.kind.rawValue == "confirmCables" {
                device.connect(output: 1, toInput: 3)
                device.connect(output: 2, toInput: 4)
            }
            return .proceed
        }
        let report = await runSteps([.fillKeyLoopback], interaction: tester, rig: rig)
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.findings.joined(separator: "\n").contains("most likely a cabling mistake"))
        #expect(s.value("First run: route measured") != nil)
    }

    @Test func crossedCablesThatStayCrossedAreReportedWithBothRunsAndTheCaveat() async {
        let rig = HardwareTestRig.simulated()
        rig.device.connect(output: 1, toInput: 4)
        rig.device.connect(output: 2, toInput: 3)
        let report = await runSteps([.fillKeyLoopback], rig: rig)
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.findings.joined(separator: "\n").contains("same answer as the first"))
        #expect(s.findings.joined(separator: "\n").contains("Two cables swapped would look the same"))
    }

    @Test func skippingTheConfirmationKeepsTheFirstResultAndSaysItWasNotRepeated() async {
        let tester = ScriptedInteraction { p in p.kind.rawValue == "confirmCables" ? .skip : .proceed }
        let report = await runSteps([.fillKeyLoopback], faults: SimulatedFaults(swapFillAndKey: true), interaction: tester)
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.findings.joined(separator: "\n").contains("not repeated"))
        #expect(!s.measurements.contains { $0.name.hasPrefix("First run") })
    }
}
}

final class PromptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ s: String) { lock.withLock { list.append(s) } }
    var items: [String] { lock.withLock { list } }
}
