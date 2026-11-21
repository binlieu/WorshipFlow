// HW-002: the "Show simulated SDI device" developer setting. Off by default, remembered in the library, so a real
// operator never sees a fake device by accident.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct HW002_DeveloperSettingTests {
    func model(_ store: LibraryStore) -> SettingsModel {
        SettingsModel(store: store, legacy: nil, defaultProfiles: { [ScreenProfile(name: "A", role: .audience, destination: .window)] })
    }

    @Test func theSimulatedDeviceIsOffByDefault() async throws {
        let settings = model(try LibraryStore.inMemory())
        #expect(settings.showSimulatedSDIDevice == false)
        await settings.load()
        #expect(settings.showSimulatedSDIDevice == false)
    }

    @Test func theChoiceIsStoredAndComesBackAfterARelaunch() async throws {
        let store = try LibraryStore.inMemory()
        let first = model(store)
        await first.load()
        var calls = 0
        first.onSimulatedSDIDeviceChange = { calls += 1 }
        first.setShowSimulatedSDIDevice(true)
        #expect(first.showSimulatedSDIDevice && calls == 1)
        first.setShowSimulatedSDIDevice(true)
        #expect(calls == 1, "no change, no callback")
        await first.flush()
        let again = model(store)
        await again.load()
        #expect(again.showSimulatedSDIDevice)
        again.setShowSimulatedSDIDevice(false)
        await again.flush()
        let third = model(store)
        await third.load()
        #expect(!third.showSimulatedSDIDevice)
    }

    @Test func aProfileWithSDIAndMirrorsSurvivesTheSettingsModel() async throws {
        let store = try LibraryStore.inMemory()
        let first = model(store)
        await first.load()
        var p = try #require(first.profiles.first)
        p.destination = .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .straight)
        p.mirrors = [.window]
        p.videoMode = .hd1080p60
        first.updateProfile(p)
        await first.flush()
        let again = model(store)
        await again.load()
        #expect(again.profiles.first == p)
    }
}
