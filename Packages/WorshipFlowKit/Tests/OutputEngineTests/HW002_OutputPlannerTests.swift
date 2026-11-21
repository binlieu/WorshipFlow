// HW-002 / OUT-005: the combined plan for displays, windows, SDI connectors and mirrors. Pure, no devices.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct HW002_OutputPlannerTests {
    let card = SDIDeviceStatus(id: "sim", info: .simulatedDuo2, isConnected: true, supportedModes: SDIVideoMode.allKnown)

    func sdi(_ connector: Int, keying: Bool = false, alpha: SDIAlphaMode = .premultiplied) -> OutputDestination {
        .sdi(deviceID: "sim", connector: connector, keying: keying, fillAlphaMode: alpha)
    }
    func profile(_ name: String, _ role: ScreenRole = .broadcast, _ dest: OutputDestination, mirrors: [OutputDestination] = [],
                 mode: VideoModeDescription = .hd1080p5994, enabled: Bool = true) -> ScreenProfile {
        ScreenProfile(name: name, role: role, destination: dest, isEnabled: enabled, mirrors: mirrors, videoMode: mode)
    }
    func plan(_ profiles: [ScreenProfile], displays: [UInt32] = [1, 2, 3], operatorDisplay: UInt32? = 1,
              devices: [SDIDeviceStatus]? = nil) -> OutputPlan {
        OutputPlanner.plan(profiles: profiles, availableDisplays: displays, operatorDisplay: operatorDisplay, sdiDevices: devices ?? [card])
    }

    @Test func existingDisplayAndWindowRulesStillApplyToPrimaries() {
        let a = profile("A", .audience, .display(2)), b = profile("B", .stage, .display(2)), c = profile("C", .stage, .display(1))
        let p = plan([a, b, c])
        #expect(p.assignments[OutputSlot(screenID: a.id)] == .display(2))
        #expect(p.faults[OutputSlot(screenID: b.id)] == .routing(.displayInUse(by: a.id)))
        #expect(p.faults[OutputSlot(screenID: c.id)] == .routing(.operatorDisplay))
    }

    @Test func aPlainSDIOutputIsAssignedItsConnectorAndMode() throws {
        let a = profile("Out", .broadcast, sdi(3), mode: .hd1080p50)
        let p = plan([a])
        let planned = try #require(p.assignments[OutputSlot(screenID: a.id)])
        guard case .sdi(let s) = planned else { Issue.record("expected SDI"); return }
        #expect(s.deviceID == "sim" && s.connector == 3 && s.keyConnector == nil)
        #expect(s.mode == .hd1080p50)
        #expect(s.mode.frameDurationValue == 1000 && s.mode.timeScale == 50000)
    }

    @Test func aKeyedOutputTakesTheNextConnectorForTheKey() throws {
        let a = profile("Key", .broadcast, sdi(1, keying: true, alpha: .straight))
        let p = plan([a])
        guard case .sdi(let s)? = p.assignments[OutputSlot(screenID: a.id)] else { Issue.record("expected SDI"); return }
        #expect(s.connector == 1 && s.keyConnector == 2)
        #expect(s.fillAlphaMode == .straight)
        let map = try #require(p.connectorMaps["sim"])
        #expect(map.uses == [.fill(OutputSlot(screenID: a.id)), .key(OutputSlot(screenID: a.id)), .unused, .unused])
    }

    /// Acceptance: two screens asking for the same connector fault the later one, with the planner's message.
    @Test func twoScreensOnTheSameConnectorFaultTheLaterOne() {
        let a = profile("First", .broadcast, sdi(1)), b = profile("Second", .audience, sdi(1))
        let p = plan([a, b])
        #expect(p.assignments[OutputSlot(screenID: a.id)] != nil)
        #expect(p.assignments[OutputSlot(screenID: b.id)] == nil)
        guard case .sdiConnector(.connectorInUse)? = p.faults[OutputSlot(screenID: b.id)] else { Issue.record("expected connectorInUse"); return }
        #expect(p.faults[OutputSlot(screenID: b.id)]?.operatorMessage == SDIPlanFault.connectorInUse(by: a.id).operatorMessage)
    }

    @Test func aKeyedPairBlocksItsPartnerConnectorForOthers() {
        let a = profile("Key", .broadcast, sdi(1, keying: true)), b = profile("Plain", .audience, sdi(2))
        let p = plan([a, b])
        guard case .sdiConnector(.connectorInUse)? = p.faults[OutputSlot(screenID: b.id)] else { Issue.record("expected connectorInUse, got \(String(describing: p.faults))"); return }
    }

    @Test func connectorFaultsAreCarriedThroughWithTheirMessages() {
        let tooHigh = profile("Hi", .broadcast, sdi(9))
        let evenKey = profile("Even", .broadcast, sdi(2, keying: true))
        let p = plan([tooHigh, evenKey])
        #expect(p.faults[OutputSlot(screenID: tooHigh.id)] == .sdiConnector(.connectorOutOfRange))
        #expect(p.faults[OutputSlot(screenID: evenKey.id)] == .sdiConnector(.keyingNeedsFirstConnectorOfAPair))
        #expect(p.faults[OutputSlot(screenID: tooHigh.id)]?.operatorMessage == SDIPlanFault.connectorOutOfRange.operatorMessage)
    }

    @Test func aKeyingRequestOnACardWithoutKeyingFaults() {
        var info = SDIDeviceInfo.simulatedDuo2; info.supportsExternalKeying = false
        let plain = SDIDeviceStatus(id: "sim", info: info, isConnected: true, supportedModes: SDIVideoMode.allKnown)
        let a = profile("Key", .broadcast, sdi(1, keying: true))
        #expect(plan([a], devices: [plain]).faults[OutputSlot(screenID: a.id)] == .sdiConnector(.keyingUnsupported))
    }

    @Test func aMissingOrDisconnectedDeviceFaultsOnlyThoseScreens() {
        let a = profile("Out", .broadcast, sdi(1)), w = profile("Win", .stage, .window)
        let none = plan([a, w], devices: [])
        #expect(none.faults[OutputSlot(screenID: a.id)] == .sdiDeviceMissing)
        #expect(none.assignments[OutputSlot(screenID: w.id)] == .window)
        var gone = card; gone.isConnected = false
        #expect(plan([a], devices: [gone]).faults[OutputSlot(screenID: a.id)] == .sdiDeviceMissing)
        let other = profile("Other", .broadcast, .sdi(deviceID: "elsewhere", connector: 1, keying: false, fillAlphaMode: .premultiplied))
        #expect(plan([other]).faults[OutputSlot(screenID: other.id)] == .sdiDeviceMissing)
    }

    @Test func aModeTheDeviceDoesNotSupportIsAFaultWithItsName() {
        var limited = card; limited.supportedModes = [.hd1080p5994]
        let a = profile("Out", .broadcast, sdi(1), mode: .hd720p50)
        let fault = plan([a], devices: [limited]).faults[OutputSlot(screenID: a.id)]
        #expect(fault == .sdiModeUnsupported("720p50"))
        #expect(fault?.operatorMessage.contains("720p50") == true)
    }

    @Test func missingDeviceMessageSaysWhatToDo() {
        #expect(OutputFault.sdiDeviceMissing.operatorMessage.contains("SDI card"))
        #expect(OutputFault.routing(.displayMissing).operatorMessage == RoutingFault.displayMissing.operatorMessage)
    }

    // MARK: mirrors

    @Test func aMirrorIsPlannedAsItsOwnSlot() {
        let a = profile("Audience", .audience, .display(2), mirrors: [.window, sdi(1)])
        let p = plan([a])
        #expect(p.assignments[OutputSlot(screenID: a.id)] == .display(2))
        #expect(p.assignments[OutputSlot(screenID: a.id, mirror: 0)] == .window)
        guard case .sdi(let s)? = p.assignments[OutputSlot(screenID: a.id, mirror: 1)] else { Issue.record("expected sdi mirror"); return }
        #expect(s.connector == 1)
    }

    @Test func aMissingMirrorDisplayNeverStopsThePrimary() {
        let a = profile("Audience", .audience, .display(2), mirrors: [.display(9)])
        let p = plan([a])
        #expect(p.assignments[OutputSlot(screenID: a.id)] == .display(2))
        #expect(p.faults[OutputSlot(screenID: a.id, mirror: 0)] == .routing(.displayMissing))
        #expect(p.faults[OutputSlot(screenID: a.id)] == nil)
    }

    @Test func aMirrorOnTheOperatorDisplayIsRefused() {
        let a = profile("Audience", .audience, .display(2), mirrors: [.display(1)])
        #expect(plan([a]).faults[OutputSlot(screenID: a.id, mirror: 0)] == .routing(.operatorDisplay))
    }

    @Test func aMirrorCannotTakeADisplayAScreenAlreadyHas() {
        let a = profile("Audience", .audience, .display(2), mirrors: [.display(3)])
        let b = profile("Stage", .stage, .display(3))
        let p = plan([a, b])
        // Primaries are planned before mirrors, so the stage keeps display 3 whatever the profile order.
        #expect(p.assignments[OutputSlot(screenID: b.id)] == .display(3))
        #expect(p.faults[OutputSlot(screenID: a.id, mirror: 0)] == .routing(.displayInUse(by: b.id)))
    }

    @Test func aMirrorOnTheSameSDIConnectorAsItsPrimaryFaults() {
        let a = profile("Out", .broadcast, sdi(1), mirrors: [sdi(1)])
        let p = plan([a])
        #expect(p.assignments[OutputSlot(screenID: a.id)] != nil)
        guard case .sdiConnector(.connectorInUse)? = p.faults[OutputSlot(screenID: a.id, mirror: 0)] else { Issue.record("expected connectorInUse"); return }
    }

    @Test func aDisabledProfilePlansNeitherItselfNorItsMirrors() {
        let a = profile("Off", .audience, .display(2), mirrors: [.window], enabled: false)
        let p = plan([a])
        #expect(p.assignments.isEmpty && p.faults.isEmpty)
    }

    @Test func connectorMapNamesWhoUsesEachConnector() throws {
        let a = profile("Plain", .audience, sdi(4)), k = profile("Keyed", .broadcast, sdi(1, keying: true), mirrors: [sdi(3)])
        let p = plan([a, k])
        let map = try #require(p.connectorMaps["sim"])
        #expect(map.uses == [.fill(OutputSlot(screenID: k.id)), .key(OutputSlot(screenID: k.id)),
                             .output(OutputSlot(screenID: k.id, mirror: 0)), .output(OutputSlot(screenID: a.id))])
    }

    @Test func aDisconnectedDeviceStillGetsAnEmptyMap() throws {
        var gone = card; gone.isConnected = false
        let map = try #require(plan([], devices: [gone]).connectorMaps["sim"])
        #expect(map.uses == [.unused, .unused, .unused, .unused])
    }

    @Test func theDomainModeListMatchesTheEnginesAndConvertsBothWays() {
        #expect(VideoModeDescription.allKnown == SDIVideoMode.allKnown.map { VideoModeDescription($0) })
        for d in VideoModeDescription.allKnown { #expect(VideoModeDescription(SDIVideoMode(d)) == d) }
        #expect(AlphaMode(.straight) == .straight && AlphaMode(.premultiplied) == .premultiplied)
    }
}
