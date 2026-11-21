// HW-004: the hardware test kit reads the device-reported key route and compares it with what it measures and with the
// manual's table, records the driver facts, says on its first line whether a real device was tested, and describes the
// card's state in words. Simulated only: no real device has ever been seen.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

private func duo2Named(reversedRoute: Bool) -> SDIDeviceInfo {
    var info = reversedRoute ? SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute : SDIDeviceInfo.simulatedDuo2
    info.displayName = "DeckLink Duo 2"
    return info
}

private func rig(info: SDIDeviceInfo, faults: SimulatedFaults = .none, profile: String? = nil,
                 activate: (@Sendable (Int) async throws -> Void)? = nil) -> HardwareTestRig {
    let device = SimulatedSDIDevice(info: info)
    device.setFaults(faults)
    device.connect(output: 1, toInput: 3)
    device.connect(output: 2, toInput: 4)
    let provided = SDIProvidedDevice(id: "kit-test", info: info, profileDescription: profile, isConnected: { device.isConnected },
                                     openOutput: { try device.openOutput(connector: $0) }, openInput: { try device.openInput(connector: $0) },
                                     activateKeyingProfile: activate)
    let provider = HardwareTestProvider(isSimulated: info.isSimulated && info.displayName.contains("Simulated"), devices: { [HardwareTestDevice(provided)] },
                                        driver: { HardwareDriverStatus(isInstalled: true, apiVersion: "16.0", message: "ok") })
    return HardwareTestRig(provider: provider, clock: SimulatedHardwareTestClock(devices: [device]), interaction: SimulatedInteraction(device: device), device: device)
}

@Suite(.serialized) struct HW004_KitRouteTests {
    @Test func aDeviceThatReportsFillOnTheSecondConnectorPassesWhenTheHardwareAgrees() async {
        let report = await runSteps([.fillKeyLoopback], rig: rig(info: duo2Named(reversedRoute: true)))
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("SDI 1 carries") == "key" && s.value("SDI 2 carries") == "fill")
        #expect(s.value("Route reported by the device") == "fill on SDI 2, key on SDI 1")
        #expect(s.value("Route in the manual's table") == "fill on SDI 2, key on SDI 1")
        #expect(s.value("Route measured") == "fill on SDI 2, key on SDI 1")
        let finding = s.findings.joined(separator: "\n")
        #expect(finding.contains("UNV-03"))
        #expect(finding.contains("agrees with the device's report") && finding.contains("agrees with the manual's table"))
        #expect(finding.contains("fill on the first connector") && finding.contains("wrong"))     // the old assumption
    }

    @Test func aDeviceThatReportsFillOnTheFirstConnectorDisagreesWithTheManualAndSaysSo() async {
        let report = await runSteps([.fillKeyLoopback], rig: rig(info: duo2Named(reversedRoute: false)))
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("SDI 1 carries") == "fill")
        let finding = s.findings.joined(separator: "\n")
        #expect(finding.contains("agrees with the device's report"))
        #expect(finding.contains("disagrees with the manual's table"))
    }

    @Test func aMeasurementThatContradictsTheDeviceReportFails() async {
        // The device says fill on SDI 1; the cables carry it the other way round.
        let report = await runSteps([.fillKeyLoopback], rig: rig(info: duo2Named(reversedRoute: false), faults: SimulatedFaults(swapFillAndKey: true)))
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.summary.contains("reversed"))
        let finding = s.findings.joined(separator: "\n")
        #expect(finding.contains("disagrees with the device's report"))
    }

    @Test func aDeviceThatReportsNoRouteIsComparedWithTheOldConvention() async {
        var info = SDIDeviceInfo.simulatedDuo2
        info.keyRoutes = []
        let report = await runSteps([.fillKeyLoopback], rig: rig(info: info))
        let s = report.step(.fillKeyLoopback)
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.value("Route reported by the device") == "none reported")
        #expect(s.findings.joined(separator: "\n").contains("reports no route"))
    }

    @Test func aDeviceThatIsNotADuo2HasNoManualTableToCompareWith() async {
        let report = await runSteps([.fillKeyLoopback], rig: rig(info: .simulatedDuo2))
        let s = report.step(.fillKeyLoopback)
        #expect(s.value("Route in the manual's table")?.contains("no table") == true)
    }

    @Test func theEnvironmentStepRecordsTheApiVersionTheFrameworkCheckAndTheReportedRoute() async {
        let r = rig(info: duo2Named(reversedRoute: true))
        let provider = HardwareTestProvider(isSimulated: false, devices: r.provider.devices,
                                            driver: { HardwareDriverStatus(isInstalled: true, apiVersion: "16.0", frameworkLoadable: true, message: "installed") })
        let report = await runSteps([.environment], rig: HardwareTestRig(provider: provider, clock: r.clock, interaction: r.interaction, device: r.device))
        let s = report.step(.environment)
        #expect(s.value("Driver API version") == "16.0")
        #expect(s.value("Framework can be loaded (entitlement check)") == "yes")
        #expect(s.value("Key route reported by the device (connectors 1 and 2)") == "fill on SDI 2, key on SDI 1")
        #expect(s.value("Key route reported by the device (connectors 3 and 4)") == "fill on SDI 4, key on SDI 3")
    }

    @Test func theEnvironmentStepSaysWhenTheFrameworkCannotBeLoaded() async {
        let provider = HardwareTestProvider(isSimulated: false, devices: { [] },
                                            driver: { HardwareDriverStatus(isInstalled: false, frameworkLoadable: false, message: "files present but not loadable") })
        let rigNone = HardwareTestRig(provider: provider, clock: SimulatedHardwareTestClock(devices: []), interaction: AutomaticInteraction(), device: SimulatedSDIDevice())
        let s = await runSteps([.environment], rig: rigNone).step(.environment)
        #expect(s.value("Framework can be loaded (entitlement check)")?.hasPrefix("no") == true)
        #expect(s.value("Key route reported by the device") == "no device found")
    }
}

@Suite(.serialized) struct HW004_KitProfileTests {
    private func needingProfile() -> SDIDeviceInfo {
        var info = SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute
        let change = SDIProfileChange(firstConnector: 1, fromName: "two sub-devices, half duplex", toName: "one sub-device, full duplex", interruptedConnectors: [1, 2, 3, 4])
        info.profiles = [SDIProfileState(firstConnector: 1, activeName: "two sub-devices, half duplex", keyingAvailableNow: false, keyingChange: change),
                         SDIProfileState(firstConnector: 3, activeName: "two sub-devices, half duplex", keyingAvailableNow: true, keyingChange: nil)]
        return info
    }

    private final class Calls: @unchecked Sendable {
        private let lock = NSLock(); private var v: [Int] = []
        func add(_ p: Int) { lock.lock(); v.append(p); lock.unlock() }
        var all: [Int] { lock.lock(); defer { lock.unlock() }; return v }
    }

    @Test func theKitAsksBeforeChangingTheProfileAndThenRunsTheKeyedStep() async {
        let calls = Calls()
        let tester = ScriptedInteraction { $0.kind == .changeProfile ? .proceed : .proceed }
        let r = rig(info: needingProfile(), activate: { calls.add($0) })
        let s = await runSteps([.fillKeyLoopback], interaction: tester, rig: r).step(.fillKeyLoopback)
        #expect(tester.kinds.contains(.changeProfile))
        #expect(calls.all == [1])
        #expect(s.outcome == .passed, "\(s.summary)")
        #expect(s.events.contains { $0.contains("one sub-device, full duplex") })
    }

    @Test func aTesterWhoSaysNoLeavesTheProfileAloneAndTheStepIsSkippedWithTheReason() async {
        let calls = Calls()
        let tester = ScriptedInteraction { $0.kind == .changeProfile ? .skip : .proceed }
        let s = await runSteps([.fillKeyLoopback], interaction: tester, rig: rig(info: needingProfile(), activate: { calls.add($0) })).step(.fillKeyLoopback)
        #expect(calls.all.isEmpty)
        #expect(s.outcome == .skipped)
        #expect(s.summary.contains("profile"))
    }

    @Test func aRunWithNoPersonNeverChangesTheProfile() async {
        let calls = Calls()
        let r = rig(info: needingProfile(), activate: { calls.add($0) })
        let s = await runSteps([.fillKeyLoopback], interaction: AutomaticInteraction(), rig: r).step(.fillKeyLoopback)
        #expect(calls.all.isEmpty)
        #expect(s.outcome == .skipped && s.summary.contains("profile"))
    }

    @Test func aFailedSwitchIsAFailedStepWithTheReason() async {
        struct Refused: Error, LocalizedError { var errorDescription: String? { "the card did not confirm the profile" } }
        let tester = ScriptedInteraction { _ in .proceed }
        let s = await runSteps([.fillKeyLoopback], interaction: tester, rig: rig(info: needingProfile(), activate: { _ in throw Refused() })).step(.fillKeyLoopback)
        #expect(s.outcome == .failed)
        #expect(s.summary.contains("did not confirm the profile"))
    }
}

@Suite struct HW004_KitFirstScreenTests {
    private func report(simulated: Bool, device: String?) -> HardwareTestReport {
        HardwareTestReport(simulated: simulated, deviceName: device, deviceID: device == nil ? nil : "d", preset: "quick", startedAt: "2026-11-20T10:00:00Z")
    }

    @Test func aRealDeviceIsNamedOnTheFirstLine() {
        let lines = HardwareTestSummary.render(report(simulated: false, device: "DeckLink Duo 2")).components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("REAL DEVICE TESTED: DeckLink Duo 2"))
        #expect(!lines[0].contains("SIMULATED"))
    }

    @Test func noDeviceIsSaidOnTheFirstLineAndNothingIsClaimed() {
        let lines = HardwareTestSummary.render(report(simulated: false, device: nil)).components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("NO REAL DEVICE WAS TESTED"))
        #expect(lines[0].contains("nothing in this report says anything about real hardware"))
        #expect(!lines.prefix(4).joined(separator: "\n").contains("real hardware)"))
    }

    @Test func aSimulatedRunIsStillMarkedOnTheFirstLine() {
        let lines = HardwareTestSummary.render(report(simulated: true, device: "Simulated SDI card (4 connectors)")).components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("SIMULATED RUN"))
    }
}

@Suite(.serialized) struct HW004_BriefSummaryDriverFactsTests {
    @Test func aBriefSummaryShowsTheDriverFactsWhateverElseItTrims() async {
        let provider = HardwareTestProvider(isSimulated: false, devices: { [] },
                                            driver: { HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.") })
        let rigNone = HardwareTestRig(provider: provider, clock: SimulatedHardwareTestClock(devices: []), interaction: AutomaticInteraction(), device: SimulatedSDIDevice())
        let report = await runSteps([.environment, .devices], rig: rigNone)
        let text = HardwareTestSummary.render(report)
        let section = text.components(separatedBy: "THE DRIVER AND THE CARD")
        #expect(section.count == 2)
        let block = section.last?.components(separatedBy: "DETAILS").first ?? ""
        #expect(block.contains("Blackmagic driver: not installed"))
        #expect(block.contains("Framework can be loaded (entitlement check): unknown"))
        #expect(block.contains("Key route reported by the device: no device found"))
        #expect(text.components(separatedBy: "\n")[0].hasPrefix("NO REAL DEVICE WAS TESTED"))
    }
}

@Suite struct HW004_CardStateTests {
    private let env = HardwareDriverStatus(isInstalled: true, apiVersion: "16.0", message: "x")

    @Test func driverNotInstalledSaysWhatToInstall() {
        let s = HardwareCardState.describe(driver: HardwareDriverStatus(isInstalled: false, message: "x"), cards: [])
        #expect(s.state == .driverNotInstalled)
        #expect(s.text.contains("Blackmagic Desktop Video is not installed on this Mac"))
        #expect(s.text.contains("Install Blackmagic Desktop Video") && s.text.contains("Rescan"))
        #expect(!s.text.contains("cannot talk to a card yet"))
    }

    @Test func driverFilesThatCouldNotBeLoadedUseTheProvidersOwnWords() {
        let s = HardwareCardState.describe(driver: HardwareDriverStatus(isInstalled: false, frameworkLoadable: false, message: "files present but not loadable"), cards: [])
        #expect(s.state == .driverNotInstalled)
        #expect(s.text == "files present but not loadable")
    }

    @Test func driverInstalledButNoCardAsksForTheCableAndPower() {
        let s = HardwareCardState.describe(driver: env, cards: [])
        #expect(s.state == .noCardFound)
        #expect(s.text.contains("no DeckLink card was found"))
        #expect(s.text.contains("Thunderbolt cable") && s.text.contains("enclosure") && s.text.contains("Rescan"))
        #expect(s.text.contains("16.0"))
    }

    @Test func aCardFoundIsNamed() {
        let s = HardwareCardState.describe(driver: env, cards: ["DeckLink Duo 2"])
        #expect(s.state == .cardFound)
        #expect(s.text == "Card found: DeckLink Duo 2")
    }

    @Test func theProviderBuiltFromAnSDIProviderReportsItsEnvironment() {
        let status = SDIEnvironmentStatus(state: .noCardFound, driverInstalled: true, apiVersion: "16.0", frameworkLoadable: true, deviceCount: 0, message: "no card")
        let provider = HardwareTestProvider(provider: FakeProvider(status: status))
        #expect(!provider.isSimulated)
        #expect(provider.devices().isEmpty)
        let driver = provider.driver()
        #expect(driver.isInstalled && driver.apiVersion == "16.0" && driver.frameworkLoadable == true && driver.message == "no card")
    }

    @MainActor @Test func theControllerDescribesItsStateInWordsForEachSituation() {
        func controller(driver: HardwareDriverStatus, devices: [HardwareTestDevice]) -> HardwareTestController {
            HardwareTestController(realProvider: { HardwareTestProvider(isSimulated: false, devices: { devices }, driver: { driver }) },
                                   environment: .fixed, screensOpen: { false })
        }
        #expect(controller(driver: HardwareDriverStatus(isInstalled: false, message: "m"), devices: []).cardState.state == .driverNotInstalled)
        #expect(controller(driver: HardwareDriverStatus(isInstalled: true, message: "m"), devices: []).cardState.state == .noCardFound)
        let sim = SimulatedSDIDevice()
        let card = HardwareTestDevice(id: "d", device: sim)
        let found = controller(driver: HardwareDriverStatus(isInstalled: true, message: "m"), devices: [card])
        #expect(found.cardState.state == .cardFound && found.cardState.text.hasPrefix("Card found: Simulated"))
        #expect(found.verdictLine == nil)
    }

    @Test func aSimulatedProviderIsMarkedSimulated() {
        let provider = HardwareTestProvider(provider: SimulatedSDIProvider(device: SimulatedSDIDevice()))
        #expect(provider.isSimulated)
        #expect(provider.devices().count == 1)
    }
}

final class FakeProvider: SDIDeviceProviding, @unchecked Sendable {
    let status: SDIEnvironmentStatus
    init(status: SDIEnvironmentStatus) { self.status = status }
    func currentDevices() -> [SDIProvidedDevice] { [] }
    func rescan() {}
    func events() -> AsyncStream<SDIDeviceEvent> { AsyncStream { $0.finish() } }
    func environmentStatus() -> SDIEnvironmentStatus { status }
}
