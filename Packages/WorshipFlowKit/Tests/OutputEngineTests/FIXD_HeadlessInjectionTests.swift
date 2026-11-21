// FIX-D: the headless simulated run, clean and with each injected fault, as a coordinator runs it from the command line.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_HeadlessInjectionTests {
    private func run(_ args: [String]) async throws -> HardwareTestReport {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-head-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("r.zip")
        let launch = try #require(HardwareTestLaunch.parse(["WORSHIPFLOW", "--hardware-test", "--simulated", "--quick", "--output", out.path] + args))
        let code = await HardwareTestHeadless.run(launch, durations: HardwareTestConfiguration.tiny.durations, environment: .fixed)
        #expect(code == 0)
        return try HardwareTestBundle.load(from: out).report
    }

    @Test func theFaultNamesAreRead() {
        let l = HardwareTestLaunch.parse(["x", "--hardware-test", "--simulated", "--inject-fault", "swapped-connectors", "--inject-fault", "crossed-cables"])
        #expect(l?.injections == [.swappedConnectors, .crossedCables])
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--simulated", "--inject-fault", "nonsense"])?.injections == [])
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--simulated"])?.injections == [])
    }

    @Test func aCleanSimulatedRunPassesEveryVideoStepAndRestoresTheProfile() async throws {
        let r = try await run([])
        for id in [HardwareTestStepID.outputRun, .loopback, .fillKeyLoopback, .modeSweep, .fourOutputs] {
            #expect(r.step(id).outcome == .passed, "\(id): \(r.step(id).summary)")
        }
        #expect(r.profileRestore?.state == .restoredAndVerified)
        #expect(HardwareTestSummary.render(r).components(separatedBy: "\n")[0].hasPrefix("SIMULATED RUN"))
    }

    @Test func swappedConnectorsAreCaughtByTheFourOutputStep() async throws {
        let r = try await run(["--inject-fault", "swapped-connectors"])
        #expect(r.step(.fourOutputs).outcome == .failed, "\(r.step(.fourOutputs).summary)")
        #expect(r.step(.fourOutputs).value("Connector 1 picture")?.hasPrefix("WRONG") == true)
        // with SDI 1 and 2 swapped inside the card, the cable from SDI 1 carries nothing: the loopback says so as well
        #expect(r.step(.loopback).outcome == .failed && r.step(.loopback).summary.contains("No signal"), "\(r.step(.loopback).summary)")
    }

    @Test func aProfileThatIsNotRestoredIsInTheHeadlineAndLabelsTheLaterSteps() async throws {
        let r = try await run(["--inject-fault", "profile-not-restored"])
        let headline = HardwareTestSummary.render(r).components(separatedBy: "\n")[0]
        #expect(headline.contains("NOT RESTORED"), "\(headline)")
        #expect(r.step(.modeSweep).profileNote != nil && r.step(.modeSweep).outcome == .passed)
        #expect(r.step(.fourOutputs).outcome == .skipped)
        #expect(r.step(.fillKeyLoopback).outcome == .passed)
    }

    @Test func crossedCablesAreReportedAsAnObservationWithBothRuns() async throws {
        let r = try await run(["--inject-fault", "crossed-cables"])
        let s = r.step(.fillKeyLoopback)
        #expect(s.outcome == .failed && s.summary.contains("reversed"), "\(s.summary)")
        #expect(s.measurements.contains { $0.name.hasPrefix("First run") })
        #expect(s.findings.joined(separator: "\n").contains("with the cables as instructed"))
    }

    @Test func aRunWithTheOldFaultFlagStillBehavesAsBefore() async throws {
        let r = try await run(["--inject-faults"])
        #expect(r.step(.loopback).outcome == .failed && r.step(.loopback).summary.contains("missing"))
        #expect(r.step(.fillKeyLoopback).outcome == .failed && r.step(.fillKeyLoopback).summary.contains("reversed"))
    }
}
}
