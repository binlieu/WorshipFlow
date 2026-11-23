// UI-007f (OUT, SC-25, SC-31): the key's own "connected to" label and the signal chain the operator typed. Both are the operator's words: the map
// carries them as typed notes, never as something the card or the cable reported.
import Testing
import Foundation
import Domain
import SDIEngine
@testable import OutputEngine

@Suite struct UI007f_SignalMapNotesTests {
    private func device() -> SDIDeviceStatus { SDIDeviceStatus(id: "sim", info: .simulatedDuo2, isConnected: true) }
    private func keyed(_ note: String? = nil, key: String? = nil, chain: [ChainNode] = []) -> ScreenProfile {
        var p = ScreenProfile(name: "Livestream", role: .broadcast,
                              destination: .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied))
        if let note { p.setConnectedNote(note, mirror: nil) }
        if let key { p.setConnectedKeyNote(key, mirror: nil) }
        p.setSignalChain(chain, mirror: nil)
        return p
    }
    private func map(_ p: ScreenProfile) -> SignalMap {
        let slot = OutputSlot(screenID: p.id)
        return SignalMapPresenter.map(SignalMapInput(
            profiles: [p], devices: [device()], maps: ["sim": SDIConnectorMap(deviceID: "sim", uses: [.fill(slot), .key(slot), .unused, .unused])],
            states: [:], displayName: { "Display \($0)" }, hostName: "Mac mini"))
    }

    @Test func theKeyTileShowsItsOwnLabelAndTheFillTileItsOwn() {
        let tiles = map(keyed("ATEM input 5", key: "ATEM input 6")).devices[0].tiles
        #expect(tiles[0].connectedTo == "ATEM input 5" && tiles[1].connectedTo == "ATEM input 6")
    }

    @Test func aKeyWithNoLabelOfItsOwnShowsTheFillsLabelAsBefore() {
        let tiles = map(keyed("ATEM input 5")).devices[0].tiles
        #expect(tiles[0].connectedTo == "ATEM input 5" && tiles[1].connectedTo == "ATEM input 5")
    }

    @Test func aKeyLabelWithNoFillLabelIsShownOnTheKeyOnly() {
        let tiles = map(keyed(nil, key: "ATEM input 6")).devices[0].tiles
        #expect(tiles[0].connectedTo == nil && tiles[1].connectedTo == "ATEM input 6")
    }

    @Test func theChainIsCarriedOnTheFillTileNotTheKeyTileAndOnlyWhenTyped() {
        #expect(map(keyed("x")).devices[0].tiles.allSatisfy { $0.chain.isEmpty })
        let chain = [ChainNode(kind: .enclosure, label: "Thunderbolt box"), ChainNode(kind: .converter, label: "SDI to HDMI")]
        let tiles = map(keyed("x", chain: chain)).devices[0].tiles
        #expect(tiles[0].chain == chain && tiles[1].chain.isEmpty && tiles[2].chain.isEmpty)
    }

    @Test func aMirrorsChainBelongsToThatMirror() {
        var p = ScreenProfile(name: "Sanctuary", role: .audience,
                              destination: .sdi(deviceID: "sim", connector: 3, keying: false, fillAlphaMode: .premultiplied),
                              mirrors: [.sdi(deviceID: "sim", connector: 4, keying: false, fillAlphaMode: .premultiplied)])
        p.setSignalChain([ChainNode(kind: .converter, label: "Primary converter")], mirror: nil)
        p.setSignalChain([ChainNode(kind: .other, label: "Foyer extender")], mirror: 0)
        let m = SignalMapPresenter.map(SignalMapInput(
            profiles: [p], devices: [device()],
            maps: ["sim": SDIConnectorMap(deviceID: "sim", uses: [.unused, .unused, .output(OutputSlot(screenID: p.id)), .output(OutputSlot(screenID: p.id, mirror: 0))])],
            states: [:], displayName: { "Display \($0)" }, hostName: "Mac mini"))
        #expect(m.devices[0].tiles[2].chain.map(\.label) == ["Primary converter"])
        #expect(m.devices[0].tiles[3].chain.map(\.label) == ["Foyer extender"])
    }

    @Test func aDisplayPathCarriesItsChainToo() {
        var p = ScreenProfile(name: "Lobby", role: .audience, destination: .display(7))
        p.setSignalChain([ChainNode(kind: .other, label: "HDMI splitter")], mirror: nil)
        let m = SignalMapPresenter.map(SignalMapInput(profiles: [p], devices: [], maps: [:], states: [:], displayName: { "Display \($0)" }, hostName: "Mac"))
        #expect(m.directPaths.first?.chain.map(\.label) == ["HDMI splitter"])
    }
}
