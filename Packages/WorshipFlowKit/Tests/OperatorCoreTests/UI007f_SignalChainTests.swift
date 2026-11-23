// UI-007f (SC-25, SC-31): the operator's typed signal chain and key label, edited and kept. Nothing here is read from equipment.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI007f_SignalChainTests {
    let box = ChainNode(kind: .enclosure, label: "Thunderbolt box")

    @Test func addingAppendsAnEmptyBoxUpToTheLimit() {
        var chain: [ChainNode] = []
        for _ in 0..<ScreenProfile.maxChainLength + 3 { chain = SignalChainEditing.adding(.converter, to: chain) }
        #expect(chain.count == ScreenProfile.maxChainLength && chain.allSatisfy { $0.kind == .converter && $0.label.isEmpty })
        #expect(!SignalChainEditing.canAdd(to: chain))
    }

    @Test func removingSettingAndMovingKeepTheOtherBoxes() {
        let a = box, b = ChainNode(kind: .converter, label: "SDI to HDMI"), c = ChainNode(kind: .other, label: "Splitter")
        #expect(SignalChainEditing.removing(at: 1, from: [a, b, c]) == [a, c])
        #expect(SignalChainEditing.removing(at: 9, from: [a, b, c]) == [a, b, c])
        #expect(SignalChainEditing.setting(label: "  Cable  ", at: 2, in: [a, b, c])[2] == ChainNode(kind: .other, label: "Cable"))
        #expect(SignalChainEditing.setting(kind: .converter, at: 0, in: [a, b, c])[0] == ChainNode(kind: .converter, label: "Thunderbolt box"))
        #expect(SignalChainEditing.moving(2, by: -1, in: [a, b, c]) == [a, c, b])
        #expect(SignalChainEditing.moving(0, by: -1, in: [a, b, c]) == [a, b, c])
        #expect(SignalChainEditing.moving(2, by: 1, in: [a, b, c]) == [a, b, c])
    }

    @Test func aBoxWithNoWordsIsNamedByItsKind() {
        #expect(SignalChainEditing.title(ChainNode(kind: .converter, label: "")) == "Converter")
        #expect(SignalChainEditing.title(box) == "Thunderbolt box")
    }

    @Test func aLongLabelIsBounded() {
        let long = String(repeating: "x", count: 500)
        #expect(SignalChainEditing.setting(label: long, at: 0, in: [box])[0].label.count == ChainNode.maxLabelLength)
    }

    @Test func theKeyLabelAndTheChainAreWrittenAndReadBackAfterARelaunch() async throws {
        let id = UUID()
        let defaults: @MainActor () -> [ScreenProfile] = {
            [ScreenProfile(id: id, name: "Livestream", role: .broadcast,
                           destination: .sdi(deviceID: "sim", connector: 1, keying: true, fillAlphaMode: .premultiplied))]
        }
        let store = try LibraryStore.inMemory()
        let settings = SettingsModel(store: store, legacy: nil, defaultProfiles: defaults)
        await settings.load()
        var p = try #require(settings.profiles.first)
        p.setConnectedNote("ATEM input 5", mirror: nil)
        p.setConnectedKeyNote("ATEM input 6", mirror: nil)
        p.setSignalChain([box, ChainNode(kind: .converter, label: "SDI to HDMI")], mirror: nil)
        settings.updateProfile(p)
        await settings.flush()
        let again = SettingsModel(store: store, legacy: nil, defaultProfiles: defaults)
        await again.load()
        let back = try #require(again.profiles.first)
        #expect(back.connectedNote(mirror: nil) == "ATEM input 5" && back.connectedKeyNote(mirror: nil) == "ATEM input 6")
        #expect(back.signalChain(mirror: nil).map(\.label) == ["Thunderbolt box", "SDI to HDMI"])
    }
}
