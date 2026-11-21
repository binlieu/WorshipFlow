// HW-002 / OUT-005: the operator's choices for SDI destinations, keying, modes and mirrors. Pure rules, no views.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct HW002_ScreenEditingTests {
    let duo = SDIDeviceSummary(id: "sim", name: "Simulated SDI card (4 connectors)", connectorCount: 4, supportsKeying: true,
                               isSimulated: true, supportedModes: VideoModeDescription.allKnown)
    let monoCard = SDIDeviceSummary(id: "real", name: "Some card", connectorCount: 2, supportsKeying: false,
                                    isSimulated: false, supportedModes: [.hd1080p50, .hd1080p5994])
    func screen(_ d: OutputDestination = .window) -> ScreenProfile { ScreenProfile(name: "Broadcast", role: .broadcast, destination: d) }

    @Test func simulatedDevicesAreLabelledSimulatedEverywhereTheyAreShown() {
        #expect(duo.label.contains("Simulated"))
        #expect(!monoCard.label.contains("Simulated"))
        let d = OutputDestination.sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied)
        let text = ScreenEditing.destinationLabel(d, devices: [duo], displayName: { _ in "" })
        #expect(text.contains("Simulated") && text.contains("connector 3"))
        let keyed = ScreenEditing.destinationLabel(.sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .straight),
                                                   devices: [duo], displayName: { _ in "" })
        #expect(keyed.contains("1") && keyed.contains("2") && keyed.contains("fill and key"))
    }

    @Test func aDeviceIsConnectedUnlessSaidOtherwise() {
        #expect(duo.isConnected)
        var gone = duo; gone.isConnected = false
        #expect(gone != duo)
    }

    @Test func aDeviceThatIsGoneIsStillNamed() {
        let d = OutputDestination.sdi(deviceID: "gone", connector: 2, keying: false, fillAlphaMode: .premultiplied)
        #expect(ScreenEditing.destinationLabel(d, devices: [], displayName: { _ in "" }).contains("not connected"))
    }

    @Test func plainDestinationsKeepTheirLabels() {
        #expect(ScreenEditing.destinationLabel(.window, devices: [], displayName: { _ in "" }) == "Window")
        #expect(ScreenEditing.destinationLabel(.display(4), devices: [], displayName: { "Display \($0)" }) == "Display 4")
    }

    @Test func theKeyingCaptionNamesBothConnectors() {
        #expect(ScreenEditing.keyingCaption(connector: 1) == "Uses connectors 1 and 2")
        #expect(ScreenEditing.keyingCaption(connector: 3) == "Uses connectors 3 and 4")
    }

    @Test func keyedOutputsOnlyOfferTheFirstConnectorOfAPair() {
        #expect(ScreenEditing.connectorChoices(device: duo, keying: false) == [1, 2, 3, 4])
        #expect(ScreenEditing.connectorChoices(device: duo, keying: true) == [1, 3])
        #expect(ScreenEditing.connectorChoices(device: monoCard, keying: true).isEmpty)   // a card with no keying offers none
    }

    @Test func choosingAnSDIConnectorKeepsAnExistingKeyingAndAlphaChoice() {
        let start = screen(.sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .straight))
        let moved = ScreenEditing.choosingSDI(start, device: duo, connector: 3)
        #expect(moved.destination == .sdi(deviceID: "sim", connector: 3, keying: true, fillAlphaMode: .straight))
        let fresh = ScreenEditing.choosingSDI(screen(), device: duo, connector: 2)
        #expect(fresh.destination == .sdi(deviceID: "sim", connector: 2, keying: false, fillAlphaMode: .premultiplied))
    }

    @Test func turningKeyingOnFromTheSecondConnectorMovesToTheStartOfThePair() {
        let p = screen(.sdi(deviceID: "sim", connector: 4, keying: false, fillAlphaMode: .premultiplied))
        let keyed = ScreenEditing.settingKeying(p, on: true, device: duo)
        #expect(keyed.destination == .sdi(deviceID: "sim", connector: 3, keying: true, fillAlphaMode: .premultiplied))
        let off = ScreenEditing.settingKeying(keyed, on: false, device: duo)
        #expect(off.destination == .sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied))
    }

    @Test func keyingCannotBeTurnedOnForACardWithoutIt() {
        let p = screen(.sdi(deviceID: "real", connector: 1, keying: false, fillAlphaMode: .premultiplied))
        #expect(ScreenEditing.settingKeying(p, on: true, device: monoCard) == p)
    }

    @Test func keyingChangesNothingForAWindowOrDisplay() {
        let w = screen()
        #expect(ScreenEditing.settingKeying(w, on: true, device: duo) == w)
    }

    @Test func theAlphaModeIsChosenOnlyForSDI() {
        let p = screen(.sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied))
        #expect(ScreenEditing.settingAlphaMode(p, .straight).destination == .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .straight))
        let w = screen()
        #expect(ScreenEditing.settingAlphaMode(w, .straight) == w)
    }

    @Test func theModePickerIsLimitedToWhatTheCardSupports() {
        #expect(ScreenEditing.modes(for: monoCard) == [.hd1080p50, .hd1080p5994])
        #expect(ScreenEditing.modes(for: duo) == VideoModeDescription.allKnown)
    }

    @Test func switchingToACardThatLacksTheCurrentModeFallsBackToItsFirstSupportedMode() {
        var p = screen(); p.videoMode = .hd720p60
        let onMono = ScreenEditing.choosingSDI(p, device: monoCard, connector: 1)
        #expect(onMono.videoMode == .hd1080p5994)          // the standard mode when the card has it
        var q = screen(); q.videoMode = .hd720p60
        let onlyFifty = SDIDeviceSummary(id: "x", name: "x", connectorCount: 1, supportsKeying: false, isSimulated: false, supportedModes: [.hd1080p50])
        #expect(ScreenEditing.choosingSDI(q, device: onlyFifty, connector: 1).videoMode == .hd1080p50)
        var supported = screen(); supported.videoMode = .hd1080p50
        #expect(ScreenEditing.choosingSDI(supported, device: duo, connector: 1).videoMode == .hd1080p50)   // kept when supported
    }

    @Test func mirrorsAreAddedChangedAndRemovedOneAtATime() {
        var p = screen(.display(2))
        p = ScreenEditing.addingMirror(p)
        p = ScreenEditing.addingMirror(p)
        #expect(p.mirrors == [.window, .window])
        p = ScreenEditing.settingMirror(p, at: 1, to: .display(5))
        #expect(p.mirrors == [.window, .display(5)])
        p = ScreenEditing.removingMirror(p, at: 0)
        #expect(p.mirrors == [.display(5)])
        #expect(ScreenEditing.removingMirror(p, at: 7) == p)
        #expect(ScreenEditing.settingMirror(p, at: 3, to: .window) == p)
    }

    @Test func aMirrorUsesTheScreensModeSoPickingAnSDIMirrorNeedsNoModeOfItsOwn() {
        var p = screen(.display(2)); p.videoMode = .hd1080p50
        p = ScreenEditing.addingMirror(p)
        p = ScreenEditing.settingMirror(p, at: 0, to: .sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied))
        #expect(p.videoMode == .hd1080p50)
    }

    @Test func aMirrorsKeyingCanBeSetLikeAPrimarys() {
        let p = ScreenProfile(name: "x", role: .audience, destination: .display(2),
                              mirrors: [.sdi(deviceID: "sim", connector: 2, keying: false, fillAlphaMode: .premultiplied)])
        let keyed = ScreenEditing.settingMirrorKeying(p, at: 0, on: true, device: duo)
        #expect(keyed.mirrors == [.sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied)])
    }
}
