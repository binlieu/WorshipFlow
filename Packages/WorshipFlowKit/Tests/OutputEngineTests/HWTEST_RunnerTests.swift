// HWTEST-001: the hardware test runner against the simulated card, in virtual time. Simulated only: every result here
// says what the kit does with a card that behaves, or misbehaves in a known way, never what a real card does.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HardwareTestConfiguration {
    /// A run that takes seconds, not minutes, of test time.
    static var tiny: HardwareTestConfiguration {
        HardwareTestConfiguration(preset: .quick, durations: HardwareTestDurations(outputRunSeconds: 2, loopbackSeconds: 2, keyedSecondsPerMode: 4, fourOutputSeconds: 1))
    }
}

/// Answers prompts from a script and remembers what was asked.
final class ScriptedInteraction: HardwareTestInteraction, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [HardwarePrompt] = []
    private let answer: @Sendable (HardwarePrompt) -> HardwareAnswer
    init(_ answer: @escaping @Sendable (HardwarePrompt) -> HardwareAnswer) { self.answer = answer }
    func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        lock.withLock { asked.append(prompt) }
        return answer(prompt)
    }
    var kinds: [HardwarePromptKind] { lock.withLock { asked.map(\.kind) } }
}

struct FixedResources: Sendable {
    static let probe = HardwareResourceProbe { HardwareResourceSample(residentBytes: 512 * 1024 * 1024, cpuSeconds: 0, wallSeconds: 1) }
}

func runSteps(_ ids: Set<HardwareTestStepID>, faults: SimulatedFaults = .none, cabled: Bool = true,
              config: HardwareTestConfiguration = .tiny, interaction: (any HardwareTestInteraction)? = nil,
              rig customRig: HardwareTestRig? = nil, writer: HardwareTestBundleWriter? = nil,
              responsiveness: HardwareResponsivenessProbe = HardwareResponsivenessProbe { 4 }) async -> HardwareTestReport {
    let rig = customRig ?? HardwareTestRig.simulated(faults: faults, cabled: cabled)
    let runner = HardwareTestRunner(provider: rig.provider, configuration: config, clock: rig.clock,
                                    interaction: interaction ?? rig.interaction,
                                    environment: .fixed, resources: FixedResources.probe, responsiveness: responsiveness,
                                    bundle: writer.map { HardwareTestBundleTarget(writer: $0, zipURL: nil) },
                                    steps: HardwareTestSteps.standard(config).filter { ids.contains($0.id) })
    return await runner.run().report
}

extension HardwareTestReport {
    func step(_ id: HardwareTestStepID) -> HardwareStepResult { steps.first { $0.id == id }! }
}

extension HardwareStepResult {
    func value(_ name: String) -> String? { measurements.first { $0.name == name }?.value }
}

/// The suites that run whole simulated tests are heavy (1080p frames), so they run one after another: parallel copies
/// would starve the wall-clock tests elsewhere in the package.
@Suite(.serialized) struct HWTEST_Heavy {}

extension HWTEST_Heavy {
@Suite struct RunnerTests {
    // MARK: presets

    @Test func thePresetsHaveTheLengthsThePeopleAreTold() {
        #expect(HardwareTestPreset.quick.durations.outputRunSeconds == 30)
        #expect(HardwareTestPreset.standard.durations.outputRunSeconds == 600)
        #expect(HardwareTestPreset.long.durations.outputRunSeconds == 3600)
        func total(_ d: HardwareTestDurations) -> Double { d.outputRunSeconds + d.loopbackSeconds + 2 * d.keyedSecondsPerMode + d.fourOutputSeconds }
        #expect(total(.quick) <= 120)                          // plus the sweep, prompts and setup: about 3 minutes
        #expect((65 * 60)...(75 * 60) ~= Int(total(.long)))    // about 70 minutes
        #expect(HardwareTestPreset.quick.title == "Quick (about 3 minutes)")
        #expect(HardwareTestPreset.long.title == "Long (about 70 minutes)")
    }

    // MARK: a clean simulated card

    @Test func aCleanSimulatedRunAnswersEveryStepItCan() async {
        let report = await runSteps(Set(HardwareTestStepID.allCases))
        #expect(report.complete && report.simulated && report.finishedAt != nil)
        #expect(report.steps.map(\.id) == [.environment, .devices, .outputRun, .loopback, .fillKeyLoopback, .modeSweep, .fourOutputs, .unplugReplug, .humanChecks])
        #expect(report.steps.map(\.number) == Array(1...9))
        let outcomes = Dictionary(uniqueKeysWithValues: report.steps.map { ($0.id, $0.outcome) })
        for id in [HardwareTestStepID.environment, .devices, .outputRun, .loopback, .fillKeyLoopback, .modeSweep, .fourOutputs] {
            #expect(outcomes[id] == .passed, "\(id): \(report.step(id).summary)")
        }
        #expect(outcomes[.unplugReplug] == .skipped)
        #expect(outcomes[.humanChecks] == .skipped)
        #expect(report.deviceName == "Simulated SDI card (4 connectors)")
        #expect(report.steps.allSatisfy { !$0.summary.isEmpty && !$0.startedAt.isEmpty })
        #expect(report.steps.filter { $0.outcome == .passed }.allSatisfy { !$0.passCriteria.isEmpty })
    }

    @Test func theEnvironmentStepRecordsTheMachineAndTheDriver() async {
        let report = await runSteps([.environment])
        let s = report.step(.environment)
        #expect(s.value("macOS") == "27.2 (26C100)")
        #expect(s.value("Mac model") == "Mac16,10")
        #expect(s.value("Chip") == "Apple M4")
        #expect(s.value("Memory") == "16 GB")
        #expect(s.value("Display 1") == "Test Display, 3840 x 2160 pixels, 59.94 Hz")
        #expect(s.value("Blackmagic driver")?.contains("installed") == true)
        #expect(report.environment?.appVersion == "9.9.9")
        #expect(report.environment?.displays.count == 1)
        let all = s.measurements.map(\.value).joined() + s.summary
        #expect(!all.contains(NSUserName()) || NSUserName().count < 3)
    }

    @Test func theDevicesStepListsEverythingTheDeviceReports() async {
        let report = await runSteps([.devices])
        let s = report.step(.devices)
        #expect(s.outcome == .passed)
        #expect(s.value("Device 1") == "Simulated SDI card (4 connectors)")
        #expect(s.value("Device 1 simulated") == "yes")
        #expect(s.value("Device 1 connectors") == "4")
        #expect(s.value("Device 1 fill and key") == "yes")
        #expect(s.value("Device 1 profile") != nil)
        #expect(s.value("Device 1 connector 1 output modes")?.contains("1080p59.94") == true)
        #expect(s.value("Device 1 connector 4 input modes")?.contains("1080p59.94") == true)
        #expect(s.value("Device 1 connector 3 output modes")?.components(separatedBy: ", ").count == SDIVideoMode.allKnown.count)
    }

    @Test func theOutputRunSamplesEverySecondAndPassesWithoutLossOrLateness() async {
        let report = await runSteps([.outputRun])
        let s = report.step(.outputRun)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.sampleIntervalSeconds == 1)
        for name in ["scheduled", "completed", "late", "dropped", "repeated", "buffered", "health"] {
            #expect(s.samples[name]?.count == 2, "samples for \(name)")
        }
        #expect(s.samples["completed"]?.last ?? 0 >= 110)           // 2 s of 59.94 fps
        #expect(s.samples["dropped"]?.allSatisfy { $0 == 0 } == true)
        #expect(s.value("Dropped frames") == "0")
        #expect(s.value("Late frames") == "0")
        #expect(s.value("Video mode") == "1080p59.94")
        #expect(s.passCriteria.contains("zero dropped"))
    }

    @Test func aStarvedOutputIsReportedWithTheTimesItHappened() async throws {
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        // a device whose output refuses to keep up: every frame we schedule after the first second is thrown away
        var device = rig.provider.devices()[0]
        let inner = device.openOutput
        device.openOutput = { c in StarvingPort(inner: try inner(c), startingAt: 70) }
        let patched = device
        let provider = HardwareTestProvider(isSimulated: true, devices: { [patched] }, driver: rig.provider.driver)
        let report = await runSteps([.outputRun], rig: HardwareTestRig(provider: provider, clock: rig.clock, interaction: rig.interaction, device: rig.device))
        let s = report.step(.outputRun)
        #expect(s.outcome == .failed)
        #expect(s.events.contains { $0.contains("dropped") })
        #expect((s.samples["dropped"]?.last ?? 0) > 0)
        #expect(s.summary.contains("dropped") || s.summary.contains("late"))
    }

    // MARK: loopback

    @Test func aCleanLoopbackSeesEveryFrameOneFrameLateWithNoError() async {
        let report = await runSteps([.loopback])
        let s = report.step(.loopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("Signal detected") == "yes")
        #expect(s.value("Detected mode") == "1080p59.94")
        #expect(s.value("Missing frames") == "0")
        #expect(s.value("Repeated frames") == "0")
        #expect(s.value("Out-of-order frames") == "0")
        #expect(s.value("Delay (median)") == "1 frames")
        #expect(s.value("Largest pixel error") == "0")
        #expect(s.value("Frames received").flatMap { Int($0) } ?? 0 >= 110)
        #expect(s.passCriteria.contains("pixel error"))
        #expect(s.samples["received"]?.count == 2)
    }

    @Test func droppedFramesOnTheCableAreCountedAsMissing() async {
        let report = await runSteps([.loopback], faults: SimulatedFaults(dropEveryNthFrame: 10))
        let s = report.step(.loopback)
        #expect(s.outcome == .failed)
        let missing = Int(s.value("Missing frames") ?? "") ?? 0
        #expect(missing >= 9 && missing <= 14)                     // one in ten of about 125
        #expect(s.summary.contains("missing"))
    }

    @Test func aOnePixelShiftShowsAsPixelError() async {
        let report = await runSteps([.loopback], faults: SimulatedFaults(shiftPixels: 1))
        let s = report.step(.loopback)
        #expect(s.outcome == .failed)
        #expect(s.value("Missing frames") == "0")
        #expect((Int(s.value("Largest pixel error") ?? "") ?? 0) > 24)
        #expect(s.value("First differing pixel") != nil)
        #expect(s.summary.contains("pixel"))
    }

    @Test func aWrongDetectedModeFailsTheLoopback() async {
        let report = await runSteps([.loopback], faults: SimulatedFaults(wrongMode: .hd1080p60))
        let s = report.step(.loopback)
        #expect(s.outcome == .failed)
        #expect(s.value("Detected mode") == "1080p60")
        #expect(s.summary.contains("1080p60"))
    }

    @Test func noCableMeansNoSignalAndTheRunCarriesOn() async {
        let report = await runSteps([.loopback, .fillKeyLoopback, .modeSweep], cabled: false)
        let loop = report.step(.loopback)
        #expect(loop.outcome == .failed)
        #expect(loop.value("Signal detected") == "no")
        #expect(loop.summary.contains("cable"))
        #expect(report.step(.fillKeyLoopback).outcome == .failed)
        #expect(report.step(.modeSweep).outcome == .passed)        // needs no cable
    }

    @Test func theTesterCanSkipTheCablesAndSeesWhichConnectorsToJoin() async {
        let skip = ScriptedInteraction { _ in .skip }
        let report = await runSteps([.loopback, .fillKeyLoopback], interaction: skip)
        #expect(report.step(.loopback).outcome == .skipped)
        #expect(report.step(.fillKeyLoopback).outcome == .skipped)
        #expect(skip.kinds == [.connectLoopbackCable, .connectKeyCables])
    }

    @Test func theCablePromptNamesTheConnectors() async {
        final class Seen: @unchecked Sendable { var text = "" }
        let seen = Seen()
        let ask = ScriptedInteraction { p in seen.text += p.message + "\n"; return .skip }
        _ = await runSteps([.loopback, .fillKeyLoopback], interaction: ask)
        #expect(seen.text.contains("SDI 1") && seen.text.contains("SDI 3") && seen.text.contains("SDI 2") && seen.text.contains("SDI 4"))
    }

    // MARK: fill and key

    @Test func aCleanKeyedLoopbackFindsFillOnOneAndKeyOnTwo() async {
        let report = await runSteps([.fillKeyLoopback])
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("SDI 1 carries") == "fill")
        #expect(s.value("SDI 2 carries") == "key")
        #expect(s.value("Key matches the alpha (premultiplied)") == "yes")
        #expect(s.value("Key matches the alpha (straight)") == "yes")
        #expect(s.value("Fill is premultiplied when configured so") == "yes")
        #expect(s.value("Fill is straight when configured so") == "yes")
        #expect(s.value("Alpha ramp follows the key") == "yes")
        #expect(s.findings.contains { $0.hasPrefix("UNV-03") && $0.contains("SDI 1 carries the fill") })
        #expect(s.passCriteria.contains("tolerance"))
    }

    @Test func swappedFillAndKeyAreReportedAsReversed() async {
        let report = await runSteps([.fillKeyLoopback], faults: SimulatedFaults(swapFillAndKey: true))
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.value("SDI 1 carries") == "key")
        #expect(s.value("SDI 2 carries") == "fill")
        #expect(s.findings.contains { $0.hasPrefix("UNV-03") && $0.contains("SDI 1 carries the key") })
        #expect(s.summary.contains("reversed"))
    }

    @Test func oneCableOnlyIsReportedAsPartial() async {
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        rig.device.disconnect(input: 4)
        let report = await runSteps([.fillKeyLoopback], rig: rig)
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.summary.contains("SDI 4"))
    }

    // MARK: mode sweep

    @Test func theSweepAsksTheDeviceAboutEveryModeWithoutRunningVideo() async {
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        let report = await runSteps([.modeSweep], rig: rig)
        let s = report.step(.modeSweep)
        #expect(s.outcome == .passed, "\(s.summary)")
        for mode in SDIVideoMode.allKnown {
            #expect(s.value("\(mode.name) output") == "supported")
            #expect(s.value("\(mode.name) with fill and key") == "supported")
        }
        #expect(s.findings.contains { $0.hasPrefix("UNV-02") && $0.contains("1080p59.94") })
        #expect(rig.device.lastDisplayed(onConnector: 1) == nil)   // nothing was ever shown
    }

    @Test func aDeviceThatRefusesKeyingAt1080p5994FailsTheSweep() async {
        var info = SDIDeviceInfo.simulatedDuo2
        info.supportsExternalKeying = false
        let device = SimulatedSDIDevice(info: info)
        let rig = HardwareTestRig.simulated(device: device, cabled: true)
        let report = await runSteps([.modeSweep], rig: rig)
        let s = report.step(.modeSweep)
        #expect(s.outcome == .failed)
        #expect(s.value("1080p59.94 with fill and key") == "not supported")
        #expect(s.findings.contains { $0.hasPrefix("UNV-02") && $0.contains("not") })
    }

    // MARK: four outputs

    @Test func fourOutputsRunTogetherWithMemoryAndCpuSamples() async {
        let report = await runSteps([.fourOutputs])
        let s = report.step(.fourOutputs)
        #expect(s.outcome == .passed, "\(s.summary)")
        for c in 1...4 {
            #expect(s.value("Connector \(c) dropped") == "0")
            #expect(s.value("Connector \(c) late") == "0")
            #expect(s.samples["connector\(c)Completed"]?.count == 1)
        }
        #expect(s.samples["residentMB"]?.count == 1)
        #expect(s.samples["cpuPercent"]?.count == 1)
        #expect(s.value("Peak memory") == "512 MB")
        #expect(s.findings.contains { $0.hasPrefix("UNV-04") })
    }

    @Test func aCardWithFewerThanFourConnectorsSkipsTheFourOutputStep() async {
        let device = SimulatedSDIDevice(info: SDIDeviceInfo(displayName: "Small card", connectorCount: 2, supportsExternalKeying: false, isSimulated: true))
        let report = await runSteps([.fourOutputs, .fillKeyLoopback], rig: .simulated(device: device, cabled: true))
        #expect(report.step(.fourOutputs).outcome == .skipped)
        #expect(report.step(.fourOutputs).summary.contains("four"))
        #expect(report.step(.fillKeyLoopback).outcome == .skipped)
    }

    // MARK: no device

    @Test func withNoDeviceEveryDeviceStepIsSkippedWithTheReason() async {
        let driver = HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.")
        let provider = HardwareTestProvider(isSimulated: false, devices: { [] }, driver: { driver })
        let rig = HardwareTestRig(provider: provider, clock: SimulatedHardwareTestClock(devices: []), interaction: AutomaticInteraction(), device: SimulatedSDIDevice())
        let report = await runSteps(Set(HardwareTestStepID.allCases), config: HardwareTestConfiguration(preset: .quick, durations: HardwareTestConfiguration.tiny.durations, includeUnplugTest: true, includeHumanChecks: true), rig: rig)
        #expect(report.complete && !report.simulated && report.deviceName == nil)
        #expect(report.step(.environment).outcome == .passed)
        #expect(report.step(.devices).outcome == .failed)
        #expect(report.step(.devices).summary.contains("Blackmagic Desktop Video is not installed."))
        for id in [HardwareTestStepID.outputRun, .loopback, .fillKeyLoopback, .modeSweep, .fourOutputs, .unplugReplug, .humanChecks] {
            #expect(report.step(id).outcome == .skipped, "\(id)")
            #expect(report.step(id).summary.contains("No device"), "\(id): \(report.step(id).summary)")
        }
        #expect(HardwareTestSummary.render(report).contains("none found"))
    }

    // MARK: robustness

    @Test func aStepThatThrowsFailsAndTheRunCarriesOn() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "the card exploded" } }
        let steps = [
            HardwareTestStep(id: .environment, number: 1, title: "First", timeoutSeconds: 5) { _ in throw Boom() },
            HardwareTestStep(id: .devices, number: 2, title: "Second", timeoutSeconds: 5) { _ in HardwareStepOutput(outcome: .passed, summary: "fine") },
        ]
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        let runner = HardwareTestRunner(provider: rig.provider, configuration: .tiny, clock: rig.clock, interaction: rig.interaction,
                                        environment: .fixed, resources: FixedResources.probe, steps: steps)
        let report = await runner.run().report
        #expect(report.steps.map(\.outcome) == [.failed, .passed])
        #expect(report.steps[0].summary.contains("the card exploded"))
        #expect(report.complete)
    }

    @Test func aStepThatNeverReturnsTimesOutAndTheRunCarriesOn() async {
        let steps = [
            HardwareTestStep(id: .environment, number: 1, title: "Hangs", timeoutSeconds: 0.3) { _ in
                try await Task.sleep(for: .seconds(3600))
                return HardwareStepOutput(outcome: .passed, summary: "never")
            },
            HardwareTestStep(id: .devices, number: 2, title: "After", timeoutSeconds: 5) { _ in HardwareStepOutput(outcome: .passed, summary: "fine") },
        ]
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        let runner = HardwareTestRunner(provider: rig.provider, configuration: .tiny, clock: rig.clock, interaction: rig.interaction,
                                        environment: .fixed, resources: FixedResources.probe, steps: steps)
        let started = Date()
        let report = await runner.run().report
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(report.steps.map(\.outcome) == [.failed, .passed])
        #expect(report.steps[0].summary.contains("did not finish"))
    }

    @Test func theBundleHoldsEveryFinishedStepBeforeTheNextOneStarts() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try HardwareTestBundleWriter(directory: dir)
        final class Seen: @unchecked Sendable { var counts: [Int] = [] }
        let seen = Seen()
        let steps = (1...3).map { n in
            HardwareTestStep(id: HardwareTestStepID.allCases[n - 1], number: n, title: "Step \(n)", timeoutSeconds: 5) { _ in
                // at the start of step n, the file already holds steps 1...n-1
                if let data = try? Data(contentsOf: dir.appendingPathComponent("report.json")),
                   let r = try? JSONDecoder().decode(HardwareTestReport.self, from: data) { seen.counts.append(r.steps.count) } else { seen.counts.append(0) }
                if n == 3 { struct Crash: Error {}; throw Crash() }
                return HardwareStepOutput(outcome: .passed, summary: "ok")
            }
        }
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        let runner = HardwareTestRunner(provider: rig.provider, configuration: .tiny, clock: rig.clock, interaction: rig.interaction,
                                        environment: .fixed, resources: FixedResources.probe,
                                        bundle: HardwareTestBundleTarget(writer: writer, zipURL: dir.appendingPathExtension("zip")), steps: steps)
        let result = await runner.run()
        #expect(seen.counts == [0, 1, 2])
        let loaded = try HardwareTestBundle.load(from: try #require(result.bundleURL))
        #expect(loaded.report.steps.count == 3 && loaded.report.complete)
        #expect(loaded.engineLog.contains("Step 2"))
        try? FileManager.default.removeItem(at: dir.appendingPathExtension("zip"))
    }

    @Test func progressEventsDescribeEachStep() async {
        final class Events: @unchecked Sendable {
            let lock = NSLock(); var items: [String] = []
            func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        }
        let events = Events()
        let rig = HardwareTestRig.simulated(faults: .none, cabled: true)
        let runner = HardwareTestRunner(provider: rig.provider, configuration: .tiny, clock: rig.clock, interaction: rig.interaction,
                                        environment: .fixed, resources: FixedResources.probe,
                                        onEvent: { e in
                                            switch e {
                                            case .stepStarted(let n, let total, let title): events.add("start \(n)/\(total) \(title)")
                                            case .stepFinished(let r): events.add("done \(r.number) \(r.outcome.rawValue)")
                                            case .progress, .log: break
                                            }
                                        },
                                        steps: HardwareTestSteps.standard(.tiny).filter { [.environment, .devices].contains($0.id) })
        _ = await runner.run()
        #expect(events.items == ["start 1/2 Environment", "done 1 passed", "start 2/2 Devices", "done 2 passed"])
    }

    // MARK: unplug and replug

    @Test func anUnplugIsReportedByTheEngineAndTheAppStaysResponsive() async {
        var config = HardwareTestConfiguration.tiny
        config.includeUnplugTest = true
        let report = await runSteps([.unplugReplug], config: config)
        let s = report.step(.unplugReplug)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("Engine reported")?.contains("disconnected") == true)
        #expect(s.value("App responsive during unplug") == "yes")
        #expect(s.value("Device back after replug") == "yes")
        #expect(s.value("Output restarted after replug") == "yes")
    }

    @Test func anUnplugThatNeverHappenedFails() async {
        var config = HardwareTestConfiguration.tiny
        config.includeUnplugTest = true
        let lazy = ScriptedInteraction { _ in .proceed }              // says "done" but nothing was unplugged
        let report = await runSteps([.unplugReplug], config: config, interaction: lazy)
        #expect(report.step(.unplugReplug).outcome == .failed)
        #expect(report.step(.unplugReplug).summary.contains("did not report"))
    }

    @Test func aSluggishAppFailsTheUnplugStep() async {
        var config = HardwareTestConfiguration.tiny
        config.includeUnplugTest = true
        let report = await runSteps([.unplugReplug], config: config, responsiveness: HardwareResponsivenessProbe { 4000 })
        #expect(report.step(.unplugReplug).outcome == .failed)
        #expect(report.step(.unplugReplug).value("App responsive during unplug") == "no")
    }

    @Test func theUnplugStepIsSkippedUnlessAsked() async {
        let report = await runSteps([.unplugReplug])
        #expect(report.step(.unplugReplug).outcome == .skipped)
        #expect(report.step(.unplugReplug).summary.contains("not selected"))
    }

    // MARK: human checks

    @Test func yesToEveryQuestionPasses() async {
        var config = HardwareTestConfiguration.tiny
        config.includeHumanChecks = true
        let yes = ScriptedInteraction { p in p.kind == .photo ? .skip : .yes }
        let report = await runSteps([.humanChecks], config: config, interaction: yes)
        let s = report.step(.humanChecks)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("Colour bars fill the screen") == "yes")
        #expect(s.value("White box edges are clean over camera") == "yes")
    }

    @Test func aNoFailsAndAPhotoIsAttachedWithoutItsPath() async throws {
        var config = HardwareTestConfiguration.tiny
        config.includeHumanChecks = true
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("my pastor's phone.jpg")
        try Data([9, 9]).write(to: photo)
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        let answers = ScriptedInteraction { p in
            switch p.kind {
            case .photo: return .attachment(photo.path)
            case .humanBars: return .yes
            default: return .no
            }
        }
        let report = await runSteps([.humanChecks], config: config, interaction: answers, writer: writer)
        let s = report.step(.humanChecks)
        #expect(s.outcome == .failed)
        #expect(s.value("White box edges are clean over camera") == "no")
        #expect(s.value("Photo 1") == "photos/photo-1.jpg")
        #expect(!(try String(contentsOf: dir.appendingPathComponent("work/report.json"), encoding: .utf8)).contains("pastor"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("work/photos/photo-1.jpg").path))
    }

    @Test func unansweredQuestionsNeedAPerson() async {
        var config = HardwareTestConfiguration.tiny
        config.includeHumanChecks = true
        let report = await runSteps([.humanChecks], config: config, interaction: AutomaticInteraction())
        #expect(report.step(.humanChecks).outcome == .needsHuman)
    }

    @Test func skippingEveryQuestionSkipsTheStep() async {
        var config = HardwareTestConfiguration.tiny
        config.includeHumanChecks = true
        let report = await runSteps([.humanChecks], config: config, interaction: ScriptedInteraction { _ in .skip })
        #expect(report.step(.humanChecks).outcome == .skipped)
    }
}

}

/// A port that stops accepting frames after a point, so the card runs dry and reports drops.
final class StarvingPort: SDIOutputPort, @unchecked Sendable {
    private let inner: any SDIOutputPort
    private let from: Int64
    init(inner: any SDIOutputPort, startingAt: Int64) { self.inner = inner; self.from = startingAt }
    var connector: Int { inner.connector }
    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { inner.supports(mode: mode, keying: keying) }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws { try inner.enable(mode: mode, keying: keying) }
    func disable() { inner.disable() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws { if frameIndex < from { try inner.schedule(frame, atFrame: frameIndex) } }
    func startPlayback(atFrame frameIndex: Int64) { inner.startPlayback(atFrame: frameIndex) }
    func stopPlayback() { inner.stopPlayback() }
    func close() { inner.close() }
    var bufferedFrameCount: Int { inner.bufferedFrameCount }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? { get { inner.onFrameCompleted } set { inner.onFrameCompleted = newValue } }
    var onFailure: (@Sendable (SDIError) -> Void)? { get { inner.onFailure } set { inner.onFailure = newValue } }
}

extension HardwareEnvironmentSource {
    /// Fixed answers, so a test can compare them.
    static var fixed: HardwareEnvironmentSource {
        HardwareEnvironmentSource(
            appVersion: "9.9.9", appBuild: "99",
            displays: { [HardwareDisplayInfo(name: "Test Display", pixelWidth: 3840, pixelHeight: 2160, scale: 2, refreshRateHz: 59.94)] },
            system: { HardwareSystemInfo(osVersion: "27.2", osBuild: "26C100", macModel: "Mac16,10", chip: "Apple M4", memoryBytes: 16 << 30, processorCount: 10) },
            now: { Date(timeIntervalSince1970: 1_800_000_000) })
    }
}
