// HW-004: what the bridge's adapter reports to the engine (key routes, connector roles, profile state, environment state)
// and how SDK failures are named. Pure functions only: no call here reaches a card. NOTHING IN THIS FILE IS HARDWARE VERIFIED.
import DeckLinkC
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

@Suite struct HW004_KeyRouteReportTests {
    @Test func theDuo2ReportsFillOnTheSecondConnectorOfEachPairFromTheManualTable() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [nil, nil], subDeviceCount: 4)
        let routes = DeckLinkDeviceReport.keyRoutes(layout: layout, connectorCount: 4)
        #expect(routes == [SDIKeyRoute(firstConnector: 1, fillConnector: 2, keyConnector: 1, source: .manualTable),
                           SDIKeyRoute(firstConnector: 3, fillConnector: 4, keyConnector: 3, source: .manualTable)])
    }

    @Test func theRouteIsReportedWhateverTheCurrentProfileSoThePlannerCanShowIt() {
        let half = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [DeckLinkProfile.twoSubDevicesHalfDuplex, DeckLinkProfile.twoSubDevicesHalfDuplex], subDeviceCount: 4)
        let full = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [DeckLinkProfile.oneSubDeviceFullDuplex, DeckLinkProfile.oneSubDeviceFullDuplex], subDeviceCount: 2)
        #expect(DeckLinkDeviceReport.keyRoutes(layout: half, connectorCount: 4) == DeckLinkDeviceReport.keyRoutes(layout: full, connectorCount: 4))
    }

    @Test func anotherModelReportsTheAssumedConventionAndSaysSo() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink 8K Pro", pairProfiles: [nil, nil], subDeviceCount: 4)
        let routes = DeckLinkDeviceReport.keyRoutes(layout: layout, connectorCount: 4)
        #expect(routes == [SDIKeyRoute(firstConnector: 1, fillConnector: 1, keyConnector: 2, source: .assumed),
                           SDIKeyRoute(firstConnector: 3, fillConnector: 3, keyConnector: 4, source: .assumed)])
    }

    @Test func aSingleConnectorCardReportsNoRoutes() {
        let layout = DeckLinkConnectorLayout.make(modelName: "DeckLink Mini Monitor", pairProfiles: [nil, nil], subDeviceCount: 1)
        #expect(DeckLinkDeviceReport.keyRoutes(layout: layout, connectorCount: 1).isEmpty)
    }

    @Test func connectorRolesFollowTheLayout() {
        let full = DeckLinkConnectorLayout.make(modelName: "DeckLink Duo 2", pairProfiles: [DeckLinkProfile.oneSubDeviceFullDuplex, nil], subDeviceCount: 3)
        let infos = DeckLinkDeviceReport.connectors(layout: full)
        #expect(infos[0] == SDIConnectorInfo(connector: 1, canOutput: false, canInput: true, keyRole: .key))
        #expect(infos[1] == SDIConnectorInfo(connector: 2, canOutput: true, canInput: false, keyRole: .fill))
        #expect(infos[2] == SDIConnectorInfo(connector: 3, canOutput: true, canInput: true, keyRole: nil))
        #expect(infos.count == 4)
    }
}

@Suite struct HW004_ProfileReportTests {
    private func profile(_ id: UInt32, keying: Bool, active: Bool = false) -> DeckLinkProfileInfo {
        DeckLinkProfileInfo(id: id, name: DeckLinkProfile.name(id), isActive: active, supportsExternalKeying: keying, supportsInternalKeying: false,
                            supportsPlayback: true, supportsCapture: true, duplex: "dxfu", subDeviceCount: nil)
    }

    @Test func aCardInAHalfDuplexProfileNeedsTheFullDuplexOneForKeying() {
        let state = DeckLinkDeviceReport.profileState(
            firstConnector: 1, connectorCount: 4, activeProfile: DeckLinkProfile.twoSubDevicesHalfDuplex, activeProfileKeys: false,
            profiles: [profile(DeckLinkProfile.twoSubDevicesHalfDuplex, keying: false, active: true), profile(DeckLinkProfile.oneSubDeviceFullDuplex, keying: true)])
        #expect(!state.keyingAvailableNow)
        #expect(state.activeName == "two sub-devices, half duplex")
        #expect(state.keyingChange == SDIProfileChange(firstConnector: 1, fromName: "two sub-devices, half duplex", toName: "one sub-device, full duplex",
                                                      interruptedConnectors: [1, 2, 3, 4]))
    }

    @Test func aCardAlreadyInAKeyingProfileNeedsNoChange() {
        let state = DeckLinkDeviceReport.profileState(
            firstConnector: 3, connectorCount: 4, activeProfile: DeckLinkProfile.oneSubDeviceFullDuplex, activeProfileKeys: true,
            profiles: [profile(DeckLinkProfile.oneSubDeviceFullDuplex, keying: true, active: true)])
        #expect(state.keyingAvailableNow && state.keyingChange == nil)
    }

    @Test func aCardWithNoKeyingProfileHasNothingToOffer() {
        let state = DeckLinkDeviceReport.profileState(
            firstConnector: 1, connectorCount: 4, activeProfile: DeckLinkProfile.twoSubDevicesHalfDuplex, activeProfileKeys: false,
            profiles: [profile(DeckLinkProfile.twoSubDevicesHalfDuplex, keying: false, active: true)])
        #expect(!state.keyingAvailableNow && state.keyingChange == nil)
    }

    @Test func aProfileThatIsMissingFromTheListStillReportsNoChangeRatherThanGuessing() {
        let state = DeckLinkDeviceReport.profileState(firstConnector: 1, connectorCount: 4, activeProfile: nil, activeProfileKeys: false, profiles: [])
        #expect(!state.keyingAvailableNow && state.keyingChange == nil && state.activeName == nil)
    }
}

@Suite struct HW004_EnvironmentStateTests {
    private func status(driver: Bool, onDisk: Bool = false, devices: [String] = [], version: String? = "16.0") -> SDIEnvironmentStatus {
        DeckLinkDeviceReport.environmentStatus(
            environment: DeckLinkEnvironment.make(driverPresent: driver, apiVersion: version, compiledAPIVersion: "16.0", frameworkOnDisk: onDisk), deviceNames: devices)
    }

    @Test func driverNotInstalledNamesWhatToInstall() {
        let s = status(driver: false)
        #expect(s.state == .driverNotInstalled && !s.driverInstalled && s.deviceCount == 0)
        #expect(s.message.hasPrefix("Blackmagic Desktop Video is not installed on this Mac. SDI outputs need it."))
        #expect(s.message.contains("Install Blackmagic Desktop Video"))
        #expect(s.frameworkLoadable == nil)
    }

    @Test func driverFilesOnTheMacThatCouldNotBeLoadedIsADifferentState() {
        let s = status(driver: false, onDisk: true)
        #expect(s.state == .driverNotInstalled)
        #expect(s.frameworkLoadable == false)
        #expect(s.message.contains("could not load"))
        #expect(!s.message.hasPrefix("Blackmagic Desktop Video is not installed"))
    }

    @Test func driverInstalledButNoCardAsksForTheCableAndThePower() {
        let s = status(driver: true)
        #expect(s.state == .noCardFound && s.driverInstalled && s.frameworkLoadable == true && s.apiVersion == "16.0")
        #expect(s.message.contains("no DeckLink card was found"))
        #expect(s.message.contains("Thunderbolt cable") && s.message.contains("enclosure") && s.message.contains("Rescan"))
    }

    @Test func aCardFoundIsNamed() {
        let s = status(driver: true, devices: ["DeckLink Duo 2"])
        #expect(s.state == .cardFound && s.deviceCount == 1)
        #expect(s.message.contains("DeckLink Duo 2"))
    }
}

@Suite struct HW004_HardwareFaultMappingTests {
    private func bridgeError(_ code: DLBError.Code) -> NSError {
        NSError(domain: DLBErrorDomain, code: code.rawValue, userInfo: [NSLocalizedDescriptionKey: "The card would not accept the frame.", DLBErrorHRESULTKey: -2147467259])
    }

    @Test func sdkFailuresAreHardwareFaultsWithTheDetailNotDisconnects() {
        for code in [DLBError.Code.sdkFailure, .outOfMemory, .profileTimeout] {
            let e = DeckLinkMapping.sdiError(bridgeError(code), context: .schedule)
            guard case .hardwareFault(let detail) = e else { Issue.record("\(code) mapped to \(e)"); continue }
            #expect(detail.contains("The card would not accept the frame") && detail.contains("-2147467259"))
        }
    }

    @Test func anUnrecognisedErrorIsAHardwareFaultToo() {
        guard case .hardwareFault = DeckLinkMapping.sdiError(NSError(domain: "other", code: 1), context: .runtime) else {
            Issue.record("expected hardwareFault"); return
        }
    }

    @Test func removalAndTheDriverBeingGoneStillMeanDisconnected() {
        #expect(DeckLinkMapping.sdiError(bridgeError(.deviceRemoved), context: .schedule) == .deviceDisconnected)
        #expect(DeckLinkMapping.sdiError(bridgeError(.driverNotInstalled), context: .runtime) == .deviceDisconnected)
    }
}

@Suite struct HW004_DriverAbsentProviderTests {
    private let driverIsPresent = DeckLinkEnvironment.current.driverPresent

    @Test func theProviderConformsAndReportsTheMissingDriverCalmly() {
        let provider: any SDIDeviceProviding = DeckLinkDeviceProvider()
        provider.rescan()
        #expect(provider.currentDevices().isEmpty || driverIsPresent)
        let status = provider.environmentStatus()
        if !driverIsPresent {
            #expect(status.state == .driverNotInstalled)
            #expect(status.message.hasPrefix("Blackmagic Desktop Video is not installed on this Mac. SDI outputs need it."))
        }
    }

    @Test func withNoDriverTheEventStreamEndsAtOnceInsteadOfHanging() async {
        guard !driverIsPresent else { return }
        let provider = DeckLinkDeviceProvider()
        var count = 0
        for await _ in provider.events() { count += 1 }
        #expect(count == 0)
    }
}
