// CUE-001 (AUTO-01, AUTO-02, AUTO-04): the action vocabulary and its stable JSON.
import Testing
import Foundation
@testable import CueEngine

private let u1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111") ?? UUID()
private let u2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222") ?? UUID()

private func json(_ list: CueActionList) throws -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return String(decoding: try e.encode(list), as: UTF8.self)
}

private func decode(_ text: String) throws -> CueActionList {
    try JSONDecoder().decode(CueActionList.self, from: Data(text.utf8))
}

@Suite struct CueActionJSONTests {
    static let everyKnownAction: [CueAction] = [
        .transport(.next), .transport(.previous), .transport(.goToSlide(index: 7)), .transport(.clear), .transport(.clearAll),
        .transport(.blackout(.on)), .transport(.blackout(.off)), .transport(.blackout(.toggle)), .transport(.stop),
        .selectLook(u1),
        .prop(id: u1, isOn: true), .prop(id: u2, isOn: false),
        .showMessage(id: u1, fields: ["title": "Welcome", "body": "Please silence phones"]),
        .showMessage(id: u1, fields: [:]),
        .hideMessage(id: u1),
        .startTimer(u1), .pauseTimer(u1), .resetTimer(u2),
        .playForeground(assetID: u1), .setBackground(assetID: u2), .setBackground(assetID: nil), .stopForeground,
        .playAudio(assetID: u1), .stopAudio(assetID: u2),
        .midiOut(.noteOn(channel: 1, note: 60, velocity: 100)),
        .midiOut(.noteOff(channel: 16, note: 0, velocity: 0)),
        .midiOut(.controlChange(channel: 2, controller: 7, value: 127)),
        .midiOut(.programChange(channel: 9, program: 42)),
        .runMacro(u1),
        .wait(seconds: 2.5), .wait(seconds: 0),
    ]

    @Test(arguments: everyKnownAction) func everyActionRoundTrips(_ a: CueAction) throws {
        let list = CueActionList(actions: [a])
        let back = try JSONDecoder().decode(CueActionList.self, from: JSONEncoder().encode(list))
        #expect(back.actions == [a])
        #expect(back.unknownActions.isEmpty)
    }

    @Test func goldenEncodingIsStable() throws {
        let list = CueActionList(actions: [
            .transport(.goToSlide(index: 3)),
            .transport(.blackout(.toggle)),
            .selectLook(u1),
            .prop(id: u2, isOn: true),
            .setBackground(assetID: nil),
            .midiOut(.noteOn(channel: 1, note: 60, velocity: 100)),
            .wait(seconds: 2.5),
        ])
        #expect(try json(list) ==
            #"{"actions":[{"index":3,"kind":"transport.goToSlide"},{"kind":"transport.blackout","mode":"toggle"},"# +
            #"{"id":"11111111-1111-1111-1111-111111111111","kind":"look.select"},"# +
            #"{"id":"22222222-2222-2222-2222-222222222222","kind":"prop.set","on":true},"# +
            #"{"assetID":null,"kind":"media.setBackground"},"# +
            #"{"channel":1,"data1":60,"data2":100,"kind":"midi.out","type":"noteOn"},"# +
            #"{"kind":"wait","seconds":2.5}],"version":1}"#)
    }

    @Test func goldenDecodingOfAStoredCue() throws {
        let list = try decode(#"{"version":1,"actions":[{"kind":"transport.next"},{"kind":"timer.start","id":"11111111-1111-1111-1111-111111111111"}]}"#)
        #expect(list.version == 1)
        #expect(list.actions == [.transport(.next), .startTimer(u1)])
    }

    @Test func theListCarriesAVersion() throws {
        #expect(CueActionList.currentVersion == 1)
        #expect(CueActionList(actions: []).version == CueActionList.currentVersion)
        #expect(try json(CueActionList(actions: [])) == #"{"actions":[],"version":1}"#)
    }

    @Test func aMissingVersionIsTreatedAsVersionOne() throws {
        #expect(try decode(#"{"actions":[{"kind":"transport.stop"}]}"#).version == 1)
    }

    @Test func anUnknownKindBecomesUnknownAndSurvivesARoundTrip() throws {
        let text = #"{"actions":[{"kind":"transport.next"},{"kind":"hologram.fire","nested":{"x":null,"y":true},"power":9,"tags":["a","b"]}],"version":2}"#
        let list = try decode(text)
        #expect(list.version == 2)
        #expect(list.actions.count == 2)
        guard case .unknown(let raw) = list.actions[1] else { Issue.record("expected unknown"); return }
        #expect(raw == .object(["kind": .string("hologram.fire"), "power": .number(9),
                                "tags": .array([.string("a"), .string("b")]),
                                "nested": .object(["x": .null, "y": .bool(true)])]))
        #expect(list.unknownActions.count == 1)
        #expect(try json(list) == text)          // nothing lost when a newer cue is saved by this version
    }

    @Test func aKnownKindWithBadFieldsBecomesUnknownInsteadOfThrowing() throws {
        let list = try decode(#"{"version":1,"actions":["#
            + #"{"kind":"look.select","id":"not-a-uuid"},"#
            + #"{"kind":"look.select"},"#
            + #"{"kind":"transport.goToSlide","index":"three"},"#
            + #"{"kind":"transport.goToSlide","index":-1},"#
            + #"{"kind":"transport.goToSlide","index":1.5},"#
            + #"{"kind":"transport.blackout","mode":"sideways"},"#
            + #"{"kind":"wait","seconds":-1},"#
            + #"{"kind":"midi.out","type":"noteOn","channel":17,"data1":60,"data2":100},"#
            + #"{"kind":"midi.out","type":"pitchBend","channel":1,"data1":0,"data2":0},"#
            + #"{"kind":"message.show","id":"11111111-1111-1111-1111-111111111111","fields":{"a":1}},"#
            + #"{"kind":"transport.next"}]}"#)
        #expect(list.actions.count == 11)
        #expect(list.unknownActions.count == 10)
        #expect(list.actions.last == .transport(.next))
    }

    @Test func elementsThatAreNotObjectsAreUnknownToo() throws {
        let list = try decode(#"{"version":1,"actions":[5,"next",null,[1],{}]}"#)
        #expect(list.actions.count == 5)
        #expect(list.unknownActions.count == 5)
    }

    @Test func textThatIsNotJSONStillThrowsCleanly() {
        #expect(throws: (any Error).self) { try decode("{not json") }
        #expect(throws: (any Error).self) { try decode(#"{"version":1}"#) }   // no actions array at all
    }

    @Test func unknownActionsHaveAnOperatorReadableReport() throws {
        let list = try decode(#"{"version":1,"actions":[{"kind":"hologram.fire"},{"kind":"transport.next"},{"kind":"dmx.set"}]}"#)
        #expect(list.unknownActions.map(\.index) == [0, 2])
        #expect(list.unknownActions.map(\.description) == ["hologram.fire", "dmx.set"])
    }

    @Test func summariesAreHumanReadable() {
        #expect(CueAction.transport(.next).summary == "Next slide")
        #expect(CueAction.transport(.previous).summary == "Previous slide")
        #expect(CueAction.transport(.goToSlide(index: 2)).summary == "Go to slide 3")
        #expect(CueAction.transport(.clear).summary == "Clear")
        #expect(CueAction.transport(.clearAll).summary == "Clear all")
        #expect(CueAction.transport(.blackout(.toggle)).summary == "Blackout toggle")
        #expect(CueAction.transport(.stop).summary == "Stop")
        #expect(CueAction.wait(seconds: 2.5).summary == "Wait 2.5 s")
        #expect(CueAction.unknown(.object(["kind": .string("dmx.set")])).summary == "Unknown action \"dmx.set\"")
    }

    @Test func categoriesKnowWhichActionsMoveTheShow() {
        #expect(CueAction.transport(.stop).isTransport)
        #expect(!CueAction.selectLook(u1).isTransport)
        #expect(!CueAction.runMacro(u1).isTransport)
    }
}
