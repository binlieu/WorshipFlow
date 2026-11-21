// HWTEST-001: launch arguments, the headless run for the coordinator, and the controller behind the window.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct LaunchTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: arguments

    @Test func withoutTheFlagThereIsNoHardwareTest() {
        #expect(HardwareTestLaunch.parse(["WORSHIPFLOW", "--library", "/tmp/x.sqlite"]) == nil)
        #expect(HardwareTestLaunch.parse(["WORSHIPFLOW", "--simulated", "--quick"]) == nil)
    }

    @Test func theFlagAloneOpensTheWindow() {
        let l = HardwareTestLaunch.parse(["WORSHIPFLOW", "--hardware-test"])
        #expect(l == HardwareTestLaunch(simulated: false, preset: .quick, outputPath: nil))
        #expect(l?.isHeadless == false)
    }

    @Test func theHeadlessFlagsAreRead() {
        let l = HardwareTestLaunch.parse(["WORSHIPFLOW", "--hardware-test", "--simulated", "--quick", "--output", "/tmp/out.zip", "--silent-audio"])
        #expect(l == HardwareTestLaunch(simulated: true, preset: .quick, outputPath: "/tmp/out.zip"))
        #expect(l?.isHeadless == true)
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--long"])?.preset == .long)
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--standard"])?.preset == .standard)
    }

    @Test func injectedFaultsAreReadAndReportedCorrectly() async throws {
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--simulated", "--inject-faults"])?.faults
                == SimulatedFaults(dropEveryNthFrame: 7, swapFillAndKey: true))
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--simulated"])?.faults == SimulatedFaults.none)
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("faults.zip")
        let launch = HardwareTestLaunch(simulated: true, preset: .quick, outputPath: out.path, faults: SimulatedFaults(dropEveryNthFrame: 7, swapFillAndKey: true))
        let code = await HardwareTestHeadless.run(launch, durations: HardwareTestConfiguration.tiny.durations, environment: .fixed)
        #expect(code == 0)
        let r = try HardwareTestBundle.load(from: out).report
        #expect(r.step(.loopback).outcome == .failed && r.step(.loopback).summary.contains("missing"))
        #expect(r.step(.fillKeyLoopback).outcome == .failed && r.step(.fillKeyLoopback).summary.contains("reversed"))
        #expect(r.step(.outputRun).outcome == .passed)
    }

    @Test func aMissingOutputValueIsNotHeadless() {
        #expect(HardwareTestLaunch.parse(["x", "--hardware-test", "--output"])?.outputPath == nil)
    }

    // MARK: headless

    @Test func aHeadlessSimulatedRunWritesTheBundleAndExitsZero() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("result.zip")
        let launch = HardwareTestLaunch(simulated: true, preset: .quick, outputPath: out.path)
        let code = await HardwareTestHeadless.run(launch, durations: HardwareTestConfiguration.tiny.durations, environment: .fixed)
        #expect(code == 0)
        let loaded = try HardwareTestBundle.load(from: out)
        #expect(loaded.report.simulated && loaded.report.complete)
        #expect(loaded.summary.components(separatedBy: "\n")[0].contains("SIMULATED"))
        #expect(loaded.report.steps.count == 9)
    }

    @Test func aDirectoryPathGetsAGeneratedSimulatedFileName() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("bundles")
        let code = await HardwareTestHeadless.run(HardwareTestLaunch(simulated: true, preset: .quick, outputPath: target.path),
                                                  durations: HardwareTestDurations(outputRunSeconds: 1, loopbackSeconds: 1, keyedSecondsPerMode: 2, fourOutputSeconds: 1),
                                                  environment: .fixed, steps: HardwareTestSteps.standard(.tiny).filter { [.environment, .devices, .modeSweep].contains($0.id) })
        #expect(code == 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: target.path)
        #expect(names.count == 1)
        #expect(names[0].hasSuffix("-SIMULATED-WORSHIPFLOW-hardware-test.zip"))
    }

    @Test func failingStepsDoNotChangeTheExitCode() async throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("noDevice.zip")
        // not simulated and no real provider: every device step is skipped and the device step fails, yet the bundle is written
        let code = await HardwareTestHeadless.run(HardwareTestLaunch(simulated: false, preset: .quick, outputPath: out.path),
                                                  durations: HardwareTestConfiguration.tiny.durations, environment: .fixed,
                                                  realProvider: HardwareTestProvider(isSimulated: false, devices: { [] },
                                                                                     driver: { HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.") }),
                                                  steps: HardwareTestSteps.standard(.tiny).filter { [.environment, .devices, .modeSweep].contains($0.id) })
        #expect(code == 0)
        let loaded = try HardwareTestBundle.load(from: out)
        #expect(loaded.report.step(.devices).outcome == .failed)
        #expect(!loaded.report.simulated)
    }

    @Test func anUnwritableOutputIsTheKitFailing() async {
        let code = await HardwareTestHeadless.run(HardwareTestLaunch(simulated: true, preset: .quick, outputPath: "/dev/null/nope/result.zip"),
                                                  durations: HardwareTestConfiguration.tiny.durations, environment: .fixed, steps: HardwareTestSteps.standard(.tiny).filter { [.environment, .devices, .modeSweep].contains($0.id) })
        #expect(code != 0)
    }

    @Test func headlessNeedsAnOutputPath() async {
        let code = await HardwareTestHeadless.run(HardwareTestLaunch(simulated: true, preset: .quick, outputPath: nil),
                                                  durations: HardwareTestConfiguration.tiny.durations, environment: .fixed)
        #expect(code != 0)
    }
}

}

extension HWTEST_Heavy {
@MainActor
@Suite struct ControllerTests {
    private func make(screensOpen: @escaping @MainActor () -> Bool = { false }, steps: [HardwareTestStep]? = HardwareTestSteps.standard(.tiny).filter { [.environment, .devices, .modeSweep].contains($0.id) }) -> HardwareTestController {
        let driver = HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.")
        let real = HardwareTestProvider(isSimulated: false, devices: { [] }, driver: { driver })
        return HardwareTestController(realProvider: { real }, environment: .fixed, screensOpen: screensOpen,
                                      durationsOverride: HardwareTestConfiguration.tiny.durations, stepsOverride: steps,
                                      workingFolder: FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString)"))
    }

    private func finish(_ c: HardwareTestController) async {
        for _ in 0..<2400 where c.phase == .running { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func withNoCardItSaysSoAndOffersTheSimulatedDemonstration() {
        let c = make()
        #expect(c.phase == .idle)
        #expect(c.realDevices.isEmpty)
        #expect(c.driverMessage == "Blackmagic Desktop Video is not installed.")
        #expect(c.hasRealDevice == false)
        #expect(c.canStartReal)                    // a run with no card still makes a report: useful evidence
        #expect(c.realRunTitle == "Create a report anyway")
        #expect(c.canStartSimulated)
        #expect(c.canSaveEvidenceWithoutDevice)
    }

    @Test func screensBeingOpenRefusesToStartAndSaysWhy() {
        let c = make(screensOpen: { true })
        #expect(c.refusal?.contains("screens are open") == true)
        #expect(!c.canStartSimulated && !c.canStartReal)
        c.start(simulated: true)
        #expect(c.phase == .idle)
    }

    @Test func aSimulatedDemonstrationProducesASimulatedReportYouCanSave() async throws {
        let c = make()
        c.start(simulated: true)
        #expect(c.phase == .running)
        await finish(c)
        #expect(c.phase == .finished)
        #expect(c.results.count == 3)
        #expect(c.summaryText?.components(separatedBy: "\n")[0].contains("SIMULATED") == true)
        #expect(c.suggestedFileName.contains("SIMULATED-WORSHIPFLOW-hardware-test"))
        #expect(c.logLines.contains { $0.contains("Hardware test finished") })
        let bundle = try #require(c.bundleURL)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: dest); try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        try c.save(to: dest)
        #expect(try HardwareTestBundle.load(from: dest).report.simulated)
        try c.save(to: dest)                                    // saving over an existing file replaces it
    }

    @Test func aRealRunWithNoCardStillMakesAReport() async throws {
        let c = make()
        c.start(simulated: false)
        await finish(c)
        #expect(c.phase == .finished)
        #expect(c.summaryText?.contains("none found") == true)
        #expect(c.suggestedFileName.contains("WORSHIPFLOW-hardware-test") && !c.suggestedFileName.contains("SIMULATED"))
        if let url = c.bundleURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    @Test func theTesterIsAskedAndAnswersFlowThrough() async throws {
        let c = make(steps: HardwareTestSteps.standard(.tiny).filter { [.loopback, .humanChecks].contains($0.id) })
        c.includeHumanChecks = true
        c.useInteractiveTesterForSimulation = true
        c.start(simulated: true)
        var seen: [HardwarePromptKind] = []
        for _ in 0..<4800 where c.phase == .running {
            if let p = c.pendingPrompt {
                seen.append(p.kind)
                c.answer(p.kind == .photo ? .skip : .yes)
            }
            try? await Task.sleep(for: .milliseconds(25))
        }
        #expect(c.phase == .finished)
        #expect(seen.contains(.connectLoopbackCable) && seen.contains(.humanBars))
        #expect(c.results.first { $0.id == .humanChecks }?.outcome == .passed)
        if let url = c.bundleURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }

    @Test func progressNamesTheCurrentStep() async {
        let c = make(steps: HardwareTestSteps.standard(.tiny).filter { $0.id == .loopback })
        c.useInteractiveTesterForSimulation = true
        c.start(simulated: true)
        var title: String?, position = 0, total = 0
        for _ in 0..<2400 where c.phase == .running {
            if c.pendingPrompt != nil {           // the loopback step is waiting for the tester: it is the current step
                (title, position, total) = (c.currentStepTitle, c.stepPosition, c.stepTotal)
                c.answer(.skip)
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(title == "Loopback" && position == 1 && total == 1)
        if let url = c.bundleURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    }
}
}
