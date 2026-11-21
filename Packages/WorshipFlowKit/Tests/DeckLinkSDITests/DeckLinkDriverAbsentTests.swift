// HW-003: what the bridge does on a Mac without the Blackmagic Desktop Video driver (DIST-06). Verification level:
// Unit Tested for the driver-absent path only. These tests say nothing about behaviour with a card.
import DeckLinkC
import Foundation
import SDIEngine
import Testing
@testable import DeckLinkSDI

private let driverIsPresent = DeckLinkEnvironment.current.driverPresent
private let skipReason: Comment = "The Desktop Video driver is installed on this Mac, so the driver-absent behaviour cannot be observed here."

@Suite struct HW003_DriverAbsentTests {
    @Test(.enabled(if: !driverIsPresent, skipReason))
    func environmentSaysTheDriverIsMissingInPlainLanguage() {
        let env = DeckLinkEnvironment.current
        #expect(!env.driverPresent)
        #expect(env.apiVersion == nil)
        #expect(env.message.hasPrefix("Blackmagic Desktop Video is not installed on this Mac"))
        #expect(env.message == DeckLinkEnvironment.driverMissingMessage)
        #expect(env.compiledAPIVersion == "16.0")
    }

    @Test(.enabled(if: !driverIsPresent, skipReason))
    func theProviderFindsNoDevicesAndDoesNotCrash() {
        let provider = DeckLinkDeviceProvider()
        #expect(provider.devices().isEmpty)
        provider.refresh()
        provider.refresh()
        #expect(provider.devices().isEmpty)
        #expect(!provider.environment.driverPresent)
    }

    @Test(.enabled(if: !driverIsPresent, skipReason))
    func monitoringRefusesToStartWithTheDriverMessage() {
        let provider = DeckLinkDeviceProvider()
        do {
            try provider.startMonitoring { _ in }
            Issue.record("monitoring started without a driver")
        } catch let error as DeckLinkError {
            #expect(error == .driverNotInstalled)
            #expect(error.errorDescription == DeckLinkEnvironment.driverMissingMessage)
        } catch {
            Issue.record("unexpected error \(error)")
        }
        provider.stopMonitoring()   // harmless when never started
    }

    @Test(.enabled(if: !driverIsPresent, skipReason))
    func theStatusSnapshotIsPlainDataWithNoDevices() {
        let snapshot = DeckLinkDeviceProvider().statusSnapshot()
        #expect(snapshot["driverPresent"]?.boolValue == false)
        #expect(snapshot["devices"]?.arrayValue?.isEmpty == true)
        #expect(snapshot["message"]?.stringValue == DeckLinkEnvironment.driverMissingMessage)
        #expect(snapshot["compiledAPIVersion"]?.stringValue == "16.0")
        let raw = DLBBridge.statusSnapshot()
        #expect(raw["driverPresent"] as? Bool == false)
        #expect((raw["devices"] as? [Any])?.isEmpty == true)
    }

    @Test(.enabled(if: !driverIsPresent, skipReason))
    func discoveryReportsTheMissingDriverAsAnError() {
        let discovery = DLBDiscovery(arrived: { _ in }, removed: { _ in })
        do {
            try discovery.start()
            Issue.record("discovery started without a driver")
        } catch {
            let ns = error as NSError
            #expect(ns.domain == DLBErrorDomain)
            #expect(ns.code == DLBError.Code.driverNotInstalled.rawValue)
        }
        discovery.stop()
        #expect(discovery.devices.isEmpty)
    }

    @Test func driverInfoNeverCrashesAndAgreesWithTheEnvironment() {
        let info = DLBDriverInfo.current()
        let env = DeckLinkEnvironment.current
        #expect(info.present == env.driverPresent)
        #expect(DLBDriverInfo.compiledAPIVersionString == "16.0")
    }

    @Test func environmentWordingForBothStates() {
        let missing = DeckLinkEnvironment.make(driverPresent: false, apiVersion: "ignored", compiledAPIVersion: "16.0")
        #expect(!missing.driverPresent)
        #expect(missing.apiVersion == nil)
        #expect(missing.message.contains("not installed"))
        let present = DeckLinkEnvironment.make(driverPresent: true, apiVersion: "15.3", compiledAPIVersion: "16.0")
        #expect(present.driverPresent)
        #expect(present.apiVersion == "15.3")
        #expect(present.message.contains("15.3") && present.message.contains("16.0"))
        let unknown = DeckLinkEnvironment.make(driverPresent: true, apiVersion: nil, compiledAPIVersion: "16.0")
        #expect(unknown.message.contains("unknown version"))
    }

    @Test func aCardWithNoMembersIsNotConnectedAndRefusesPorts() {
        let device = DeckLinkDevice(identifier: .group(1), members: [])
        #expect(!device.isConnected)
        #expect(!device.info.isSimulated)
        #expect(throws: SDIError.deviceDisconnected) { try device.openOutput(connector: 1) }
        #expect(throws: SDIError.deviceDisconnected) { try device.openInput(connector: 1) }
        #expect(device.subDevices.isEmpty)
        #expect(device.statusSnapshot()["connected"]?.boolValue == false)
    }
}
