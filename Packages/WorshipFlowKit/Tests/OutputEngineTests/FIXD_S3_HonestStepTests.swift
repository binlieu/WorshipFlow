// FIX-D S3, S14: a step is PASSED only when everything it claims was measured, and the headline says what kind of run it was.
// These tests use only the API that existed before FIX-D (they read outcomes by raw value), so they can be run against the
// earlier kit to see them fail.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_S3_HonestStepTests {
    private func config(unplug: Bool = false, human: Bool = false) -> HardwareTestConfiguration {
        var c = HardwareTestConfiguration.tiny
        c.includeUnplugTest = unplug
        c.includeHumanChecks = human
        return c
    }

    private func notPassed(_ s: HardwareStepResult) -> Bool { s.outcome != .passed && s.outcome != .failed }

    // MARK: unplug and replug

    @Test func skippingTheReplugIsNotPassedAndSaysWhatWasMeasured() async {
        let rig = HardwareTestRig.simulated()
        let device = rig.device
        let tester = ScriptedInteraction { p in
            switch p.kind {
            case .unplugDevice: device.simulateUnplug(); return .proceed
            case .replugDevice: return .skip
            default: return .proceed
            }
        }
        let report = await runSteps([.unplugReplug], config: config(unplug: true), interaction: tester, rig: rig)
        let s = report.step(.unplugReplug)
        #expect(s.outcome != .passed, "\(s.summary)")
        #expect(s.outcome.rawValue == "partial", "\(s.outcome)")
        #expect(s.summary.lowercased().contains("unplug was measured"), "\(s.summary)")
        #expect(s.summary.lowercased().contains("replug") && s.summary.contains("Not measured"), "\(s.summary)")
        #expect(s.value("Device back after replug")?.contains("NOT MEASURED") == true)
    }

    @Test func aResponseTimeThatCouldNotBeMeasuredIsNotPassed() async {
        let report = await runSteps([.unplugReplug], config: config(unplug: true), responsiveness: HardwareResponsivenessProbe { nil })
        let s = report.step(.unplugReplug)
        #expect(s.outcome != .passed, "\(s.summary)")
        #expect(s.outcome.rawValue == "partial")
        #expect(s.summary.contains("responsive"), "\(s.summary)")
    }

    @Test func aFullyMeasuredUnplugStillPasses() async {
        let report = await runSteps([.unplugReplug], config: config(unplug: true))
        #expect(report.step(.unplugReplug).outcome == .passed, "\(report.step(.unplugReplug).summary)")
    }

    // MARK: human checks

    @Test func oneQuestionAnsweredYesAndOneSkippedIsPartAndNotSkipped() async {
        let tester = ScriptedInteraction { p in
            switch p.kind {
            case .humanBars: return .yes
            case .humanKeyEdges: return .skip
            case .photo: return .skip
            default: return .proceed
            }
        }
        let report = await runSteps([.humanChecks], config: config(human: true), interaction: tester)
        let s = report.step(.humanChecks)
        #expect(s.outcome != .passed && s.outcome != .skipped, "\(s.outcome) \(s.summary)")
        #expect(s.outcome.rawValue == "partial")
        #expect(s.summary.contains("Colour bars"), "\(s.summary)")
    }

    @Test func aKeyedQuestionThatCouldNotBeAskedIsNotPassed() async {
        let rig = HardwareTestRig.simulated()
        var device = rig.provider.devices()[0]
        let inner = device.openOutput
        device.openOutput = { c in KeyRefusingPort(inner: try inner(c)) }
        let patched = device
        let provider = HardwareTestProvider(isSimulated: true, devices: { [patched] }, driver: rig.provider.driver)
        let yes = ScriptedInteraction { p in p.kind == .photo ? .skip : .yes }
        let report = await runSteps([.humanChecks], config: config(human: true), interaction: yes,
                                    rig: HardwareTestRig(provider: provider, clock: rig.clock, interaction: rig.interaction, device: rig.device))
        let s = report.step(.humanChecks)
        #expect(s.outcome != .passed, "\(s.summary)")
        #expect(s.outcome.rawValue == "partial")
        #expect(s.measurements.contains { $0.value.contains("NOT ASKED") })
    }

    // MARK: four outputs at once with nothing looked at (S4's own honesty rule)

    @Test func fourOutputsWithNoCablesAreNotPassed() async {
        let skip = ScriptedInteraction { _ in .skip }
        let report = await runSteps([.fourOutputs], cabled: false, interaction: skip)
        let s = report.step(.fourOutputs)
        #expect(s.outcome != .passed, "\(s.summary)")
        #expect(s.outcome.rawValue == "partial")
        #expect(s.summary.contains("identity not checked"), "\(s.summary)")
        #expect(s.value("Connector 1 result") == "ran, identity not checked")
    }

    // MARK: S14: what the headline says

    private func realInfo() -> SDIDeviceInfo {
        SDIDeviceInfo(displayName: "DeckLink Duo 2", connectorCount: 4, supportsExternalKeying: true, isSimulated: false)
    }

    private func realProvider() -> HardwareTestProvider {
        let device = SimulatedSDIDevice(info: realInfo())
        let handle = HardwareTestDevice(id: "real-1", device: device, profile: nil)
        return HardwareTestProvider(isSimulated: false, devices: { [handle] }, driver: { HardwareDriverStatus(isInstalled: true, apiVersion: "16.0", message: "ok") })
    }

    @Test func aDiagnosticExportWithNoVideoStepSaysDeviceInformationOnly() async throws {
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-diag-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        let code = await DiagnosticBundle.export(to: zip, environment: .fixed, provider: realProvider())
        #expect(code == 0)
        let loaded = try HardwareTestBundle.load(from: zip)
        let first = loaded.summary.components(separatedBy: "\n")[0]
        #expect(first.hasPrefix("DEVICE INFORMATION ONLY: no video test was run"), "\(first)")
        #expect(!loaded.summary.contains("REAL DEVICE TESTED"))
        #expect(!loaded.summary.contains("were measured on this card"))
    }

    @Test func aRunThatSentVideoStillSaysTheDeviceWasTested() async {
        var report = await runSteps([.outputRun])
        report.simulated = false
        report.deviceName = "DeckLink Duo 2"
        #expect(HardwareTestSummary.render(report).components(separatedBy: "\n")[0].hasPrefix("REAL DEVICE TESTED: DeckLink Duo 2"))
    }

    @Test func aRunWhoseVideoStepsAllSkippedSaysDeviceInformationOnly() async {
        var report = await runSteps([.environment, .devices, .modeSweep])
        report.simulated = false
        report.deviceName = "DeckLink Duo 2"
        #expect(HardwareTestSummary.render(report).components(separatedBy: "\n")[0].hasPrefix("DEVICE INFORMATION ONLY"))
    }
}
}

/// Refuses fill and key, as a card in a profile that cannot send it does.
final class KeyRefusingPort: SDIOutputPort, @unchecked Sendable {
    private let inner: any SDIOutputPort
    init(inner: any SDIOutputPort) { self.inner = inner }
    var connector: Int { inner.connector }
    func supports(mode: SDIVideoMode, keying: SDIKeying) -> Bool { keying == .none && inner.supports(mode: mode, keying: keying) }
    func enable(mode: SDIVideoMode, keying: SDIKeying) throws {
        if keying != .none { throw SDIError.keyingUnavailable(connector: inner.connector) }
        try inner.enable(mode: mode, keying: keying)
    }
    func disable() { inner.disable() }
    func schedule(_ frame: SDIFrame, atFrame frameIndex: Int64) throws { try inner.schedule(frame, atFrame: frameIndex) }
    func startPlayback(atFrame frameIndex: Int64) { inner.startPlayback(atFrame: frameIndex) }
    func stopPlayback() { inner.stopPlayback() }
    func close() { inner.close() }
    var bufferedFrameCount: Int { inner.bufferedFrameCount }
    var onFrameCompleted: (@Sendable (SDIFrameCompletion) -> Void)? { get { inner.onFrameCompleted } set { inner.onFrameCompleted = newValue } }
    var onFailure: (@Sendable (SDIError) -> Void)? { get { inner.onFailure } set { inner.onFailure = newValue } }
}
