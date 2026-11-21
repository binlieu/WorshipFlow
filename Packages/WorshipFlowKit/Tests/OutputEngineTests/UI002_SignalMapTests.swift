// UI-002 Part 2: the signal map as data. Every tile, label and badge is decided here from the profiles, what the device
// reports and the connector map; the view only draws it. Nothing is invented: a destination label appears only where
// the operator typed one.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct UI002_SignalMapTests {
    private func device(simulated: Bool = true, reversed: Bool = false, connected: Bool = true) -> SDIDeviceStatus {
        SDIDeviceStatus(id: "sim", info: reversed ? .simulatedDuo2WithReversedKeyRoute : .simulatedDuo2, isConnected: connected)
            .withSimulated(simulated)
    }
    private let keyed = ScreenProfile(name: "Livestream", role: .broadcast,
                                      destination: .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied))
    private func input(_ profiles: [ScreenProfile], _ dev: SDIDeviceStatus, _ uses: [ConnectorUse],
                       states: [OutputSlot: ScreenState] = [:]) -> SignalMapInput {
        SignalMapInput(profiles: profiles, devices: [dev], maps: ["sim": SDIConnectorMap(deviceID: "sim", uses: uses)],
                       states: states, displayName: { "Display \($0)" }, hostName: "Mac mini")
    }

    @Test func tilesFollowTheConnectorOrderAndFillKeyRouteTheDeviceReports() {
        let slot = OutputSlot(screenID: keyed.id)
        // The reversed card puts the fill on connector 2 and the key on connector 1.
        let map = SignalMapPresenter.map(input([keyed], device(reversed: true), [.key(slot), .fill(slot), .unused, .unused]))
        let tiles = map.devices[0].tiles
        #expect(tiles.map(\.title) == ["SDI 1 · Key", "SDI 2 · Fill", "SDI 3 · Unused", "SDI 4 · Unused"])
        #expect(tiles[0].kind == .key && tiles[1].kind == .fill)
        #expect(tiles[0].subtitle.contains("paired with SDI 2"))
        #expect(tiles[1].subtitle.contains("Livestream"))
    }

    @Test func theConventionalCardPutsFillFirst() {
        let slot = OutputSlot(screenID: keyed.id)
        let map = SignalMapPresenter.map(input([keyed], device(), [.fill(slot), .key(slot), .unused, .unused]))
        #expect(map.devices[0].tiles.prefix(2).map(\.title) == ["SDI 1 · Fill", "SDI 2 · Key"])
    }

    @Test func aSimulatedDeviceIsBadgedOnTheMapAndOnEveryTile() {
        let slot = OutputSlot(screenID: keyed.id)
        let map = SignalMapPresenter.map(input([keyed], device(simulated: true), [.fill(slot), .key(slot), .unused, .unused]))
        #expect(map.isSimulated && map.devices[0].isSimulated)
        #expect(map.devices[0].tiles.allSatisfy { $0.isSimulated })
    }

    @Test func aRealDeviceCarriesNoSimulatedBadge() {
        let slot = OutputSlot(screenID: keyed.id)
        let map = SignalMapPresenter.map(input([keyed], device(simulated: false), [.fill(slot), .key(slot), .unused, .unused]))
        #expect(!map.isSimulated && map.devices[0].tiles.allSatisfy { !$0.isSimulated })
    }

    @Test func aDestinationLabelAppearsOnlyWhereTheOperatorTypedOne() {
        var p = keyed
        let slot = OutputSlot(screenID: p.id)
        let uses: [ConnectorUse] = [.fill(slot), .key(slot), .unused, .unused]
        var map = SignalMapPresenter.map(input([p], device(), uses))
        #expect(map.devices[0].tiles.allSatisfy { $0.connectedTo == nil })
        p.setConnectedNote("ATEM input 5", mirror: nil)
        map = SignalMapPresenter.map(input([p], device(), uses))
        #expect(map.devices[0].tiles[0].connectedTo == "ATEM input 5" && map.devices[0].tiles[1].connectedTo == "ATEM input 5")
        #expect(map.devices[0].tiles[2].connectedTo == nil)
    }

    @Test func aMirrorAppearsAsItsOwnPathWithItsOwnNote() {
        var p = ScreenProfile(name: "Sanctuary", role: .audience,
                              destination: .sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied),
                              mirrors: [.sdi(deviceID: "sim", connector: 4, keying: false, fillAlphaMode: .premultiplied)])
        p.setConnectedNote("Projector", mirror: nil)
        p.setConnectedNote("Foyer TV", mirror: 0)
        let map = SignalMapPresenter.map(input([p], device(), [.unused, .unused, .output(OutputSlot(screenID: p.id)),
                                                               .output(OutputSlot(screenID: p.id, mirror: 0))]))
        let tiles = map.devices[0].tiles
        #expect(tiles[2].title == "SDI 3 · Output" && tiles[2].subtitle == "Sanctuary" && tiles[2].connectedTo == "Projector")
        #expect(tiles[3].subtitle == "Sanctuary (mirror 1)" && tiles[3].connectedTo == "Foyer TV" && tiles[3].isMirror)
    }

    @Test func aFaultIsWrittenOnTheTileInWords() {
        let slot = OutputSlot(screenID: keyed.id)
        let map = SignalMapPresenter.map(input([keyed], device(), [.fill(slot), .key(slot), .unused, .unused],
                                               states: [slot: .faulted("The card dropped the signal.")]))
        #expect(map.devices[0].tiles[0].faultText == "The card dropped the signal.")
        #expect(map.devices[0].tiles[1].faultText == "The card dropped the signal.")
        #expect(map.devices[0].tiles[2].faultText == nil)
    }

    @Test func aDisconnectedCardSaysSoAndNoTileClaimsAnOutput() {
        let slot = OutputSlot(screenID: keyed.id)
        let map = SignalMapPresenter.map(input([keyed], device(connected: false), [.fill(slot), .key(slot), .unused, .unused]))
        #expect(!map.devices[0].isConnected && map.devices[0].caption.contains("Not connected"))
    }

    @Test func displaysAndWindowsGetATilePerDestinationAndNoSDIBlock() {
        let a = ScreenProfile(name: "Sanctuary", role: .audience, destination: .display(7), mirrors: [.window])
        let map = SignalMapPresenter.map(SignalMapInput(profiles: [a], devices: [], maps: [:], states: [:], displayName: { "Dell \($0)" }, hostName: "Mac mini"))
        #expect(map.devices.isEmpty && !map.isSimulated)
        #expect(map.directPaths.map(\.title) == ["Dell 7", "Window"])
        #expect(map.directPaths.map(\.subtitle) == ["Sanctuary", "Sanctuary (mirror 1)"])
        #expect(map.directPaths[1].isMirror)
    }

    @Test func aDisabledScreenIsLeftOffTheMap() {
        var a = ScreenProfile(name: "Lobby", role: .audience, destination: .display(7)); a.isEnabled = false
        let map = SignalMapPresenter.map(SignalMapInput(profiles: [a], devices: [], maps: [:], states: [:], displayName: { "D\($0)" }, hostName: "Mac"))
        #expect(map.directPaths.isEmpty && map.summary == "No screens are enabled.")
    }

    @Test func theMacTileNamesTheHostAndCountsRunningScreensOnly() {
        let a = ScreenProfile(name: "A", role: .audience, destination: .window)
        let b = ScreenProfile(name: "B", role: .stage, destination: .window)
        let states: [OutputSlot: ScreenState] = [OutputSlot(screenID: a.id): .running, OutputSlot(screenID: b.id): .stopped]
        let map = SignalMapPresenter.map(SignalMapInput(profiles: [a, b], devices: [], maps: [:], states: states, displayName: { _ in "" }, hostName: "Mac mini"))
        #expect(map.hostTitle == "Mac mini" && map.summary == "1 of 2 screens running")
    }

    @Test func theReportedRouteIsStatedWithItsSource() {
        let lines = SignalMapPresenter.routeLines(for: device(reversed: true).info)
        #expect(lines == ["Connectors 1 and 2: fill on 2, key on 1 (reported by the card's simulator)",
                          "Connectors 3 and 4: fill on 4, key on 3 (reported by the card's simulator)"])
        let none = SDIDeviceInfo(displayName: "X", connectorCount: 2, supportsExternalKeying: true, isSimulated: false)
        #expect(SignalMapPresenter.routeLines(for: none) == ["The card reports no fill and key route; fill is assumed on the first connector of a pair."])
    }
}

private extension SDIDeviceStatus {
    func withSimulated(_ on: Bool) -> SDIDeviceStatus {
        var copy = self
        copy.info.isSimulated = on
        return copy
    }
}
