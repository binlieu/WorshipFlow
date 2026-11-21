// UI-002 Part 2: the two preset buttons propose a plan for one SDI card and say what would change before anything does.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct UI002_SDIPresetTests {
    private func card(reversed: Bool = false, keying: Bool = true, connected: Bool = true) -> SDIDeviceStatus {
        var info = reversed ? SDIDeviceInfo.simulatedDuo2WithReversedKeyRoute : SDIDeviceInfo.simulatedDuo2
        if !keying { info.supportsExternalKeying = false }
        return SDIDeviceStatus(id: "sim", info: info, isConnected: connected)
    }
    private func sdi(_ c: Int, keying: Bool = false) -> OutputDestination { .sdi(deviceID: "sim", connector: c, keying: keying, fillAlphaMode: .premultiplied) }
    private let aud = ScreenProfile(name: "Sanctuary", role: .audience, destination: .window)
    private let stage = ScreenProfile(name: "Confidence", role: .stage, destination: .window)
    private let brd = ScreenProfile(name: "Livestream", role: .broadcast, destination: .window)

    @Test func independentGivesEachScreenOnTheCardItsOwnConnectorAndTurnsKeyingOff() {
        var a = aud; a.destination = sdi(1)
        var b = brd; b.destination = sdi(1, keying: true)
        var s = stage; s.destination = sdi(3)
        let p = SDIPresets.proposal(.independent, device: card(), profiles: [a, b, s])
        #expect(p.isAvailable)
        let result = p.applied(to: [a, b, s])
        #expect(result.map(\.destination) == [sdi(1), sdi(2), sdi(3)])
        #expect(p.changes.map(\.screenName) == ["Livestream"])      // only what changes is listed
        #expect(p.changes[0].before.contains("key on") && p.changes[0].after == "SDI 2")
    }

    @Test func independentLeavesScreensThatAreNotOnTheCardAlone() {
        var a = aud; a.destination = sdi(2)
        let p = SDIPresets.proposal(.independent, device: card(), profiles: [a, stage])
        #expect(p.applied(to: [a, stage])[1] == stage)
        #expect(p.applied(to: [a, stage])[0].destination == sdi(1))
    }

    @Test func fillKeyPutsTheBroadcastScreenOnThePairAndMovesOthersAside() {
        var a = aud; a.destination = sdi(1)
        var b = brd; b.destination = sdi(2)
        var s = stage; s.destination = sdi(3)
        let p = SDIPresets.proposal(.fillKeyBroadcast, device: card(), profiles: [a, b, s])
        #expect(p.isAvailable)
        let r = p.applied(to: [a, b, s])
        #expect(r[1].destination == sdi(1, keying: true))
        #expect(r[0].destination == sdi(3) && r[2].destination == sdi(4))
        #expect(p.changes.map(\.screenName).sorted() == ["Confidence", "Livestream", "Sanctuary"])
    }

    @Test func theProposalNamesTheConnectorsTheDeviceReports() {
        let p = SDIPresets.proposal(.fillKeyBroadcast, device: card(reversed: true), profiles: [brd])
        #expect(p.changes[0].after == "SDI 1 + 2 (fill on SDI 2, key on SDI 1)")
    }

    @Test func aBroadcastScreenOutsideTheCardIsBroughtOntoIt() {
        let p = SDIPresets.proposal(.fillKeyBroadcast, device: card(), profiles: [aud, brd])
        #expect(p.applied(to: [aud, brd])[1].destination == sdi(1, keying: true))
        #expect(p.changes.contains { $0.screenName == "Livestream" && $0.before == "Window" })
    }

    @Test func fillKeyIsUnavailableWithoutABroadcastScreenOrWithoutKeying() {
        #expect(!SDIPresets.proposal(.fillKeyBroadcast, device: card(), profiles: [aud, stage]).isAvailable)
        #expect(SDIPresets.proposal(.fillKeyBroadcast, device: card(), profiles: [aud]).unavailableReason == "There is no Broadcast screen to send as fill and key. Add one first.")
        let none = SDIPresets.proposal(.fillKeyBroadcast, device: card(keying: false), profiles: [brd])
        #expect(!none.isAvailable && none.unavailableReason == "This card cannot send a fill and key pair.")
        let gone = SDIPresets.proposal(.independent, device: card(connected: false), profiles: [aud])
        #expect(!gone.isAvailable && gone.unavailableReason == "This card is not connected.")
    }

    @Test func moreScreensThanConnectorsLeavesTheExtraOnesAlone() {
        let two = SDIDeviceInfo(displayName: "Two", connectorCount: 2, supportsExternalKeying: false, isSimulated: true)
        let dev = SDIDeviceStatus(id: "sim", info: two, isConnected: true)
        var p1 = aud, p2 = stage, p3 = brd
        p1.destination = sdi(1); p2.destination = sdi(2); p3.destination = sdi(2)
        let p = SDIPresets.proposal(.independent, device: dev, profiles: [p1, p2, p3])
        #expect(p.notes == ["Livestream has no free connector and was left as it is."])
        #expect(p.applied(to: [p1, p2, p3])[2] == p3)
    }

    @Test func aProposalThatChangesNothingSaysSo() {
        var a = aud; a.destination = sdi(1)
        let p = SDIPresets.proposal(.independent, device: card(), profiles: [a])
        #expect(p.isAvailable && p.changes.isEmpty && p.summary == "Already set up this way.")
    }

    @Test func theResultPlansWithoutFaults() {
        var a = aud; a.destination = sdi(1)
        var b = brd; b.destination = sdi(2)
        let p = SDIPresets.proposal(.fillKeyBroadcast, device: card(), profiles: [a, b])
        let dest = p.applied(to: [a, b])
        let requests = dest.compactMap { prof -> SDIOutputRequest? in
            if case .sdi(_, let c, let k, _) = prof.destination { return SDIOutputRequest(screenID: prof.id, connector: c, keying: k) } else { return nil }
        }
        let plan = SDIConnectorPlanner.plan(requests: requests, connectorCount: 4, supportsExternalKeying: true)
        #expect(plan.faults.isEmpty)
    }
}
