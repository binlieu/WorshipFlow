// UI-006g (CU-21): a function key that runs a macro. The key table, the one-key-one-macro rule, the stored shape, and the model's refusals.
import Testing
import Foundation
import Domain
import Persistence
import CueEngine
import CueStore
@testable import OperatorCore

@Suite struct UI006g_KeyTableTests {
    @Test func theTwelveFunctionKeysHaveTheirMacKeyCodes() {
        let codes = CueFunctionKey.allCases.map(\.keyCode)
        #expect(codes == [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111])
        #expect(Set(codes).count == 12)
        #expect(CueFunctionKey.allCases.map(\.label) == (1...12).map { "F\($0)" })
    }

    @Test func aKeyIsFoundByItsCodeAndByItsLabel() {
        #expect(CueFunctionKey(keyCode: 122) == .f1)
        #expect(CueFunctionKey(keyCode: 111) == .f12)
        #expect(CueFunctionKey(keyCode: 0) == nil)           // the letter A
        #expect(CueFunctionKey(keyCode: 49) == nil)          // Space
        #expect(CueFunctionKey(label: "F7") == .f7)
        #expect(CueFunctionKey(label: "F13") == nil)
    }

    @Test func noFunctionKeyIsOneTheShowAlreadyUses() {
        let taken = ShowShortcuts.all.map(\.key)
        for key in CueFunctionKey.allCases { #expect(!taken.contains(key.label)) }
    }
}

@Suite struct UI006g_KeyTriggersTests {
    private let a = UUID(), b = UUID()

    @Test func aKeyBelongsToOneMacroAndAssigningItAgainMovesIt() {
        var t = CueKeyTriggers()
        t.assign(.f1, to: a)
        #expect(t.key(for: a) == .f1)
        t.assign(.f1, to: b)
        #expect(t.key(for: b) == .f1)
        #expect(t.key(for: a) == nil)
        #expect(t.macroID(for: .f1, existing: [a, b]) == b)
    }

    @Test func aMacroHasOneKeyAndNilClearsIt() {
        var t = CueKeyTriggers()
        t.assign(.f1, to: a)
        t.assign(.f2, to: a)
        #expect(t.key(for: a) == .f2)
        #expect(t.macroID(for: .f1, existing: [a]) == nil)
        t.assign(nil, to: a)
        #expect(t.key(for: a) == nil)
        #expect(t.isEmpty)
    }

    @Test func aDeletedMacroNeverRuns() {
        var t = CueKeyTriggers()
        t.assign(.f3, to: a)
        #expect(t.macroID(for: .f3, existing: [b]) == nil)
        #expect(t.pruned(keeping: [b]).isEmpty)
        #expect(t.pruned(keeping: [a]) == t)
    }

    @Test func itIsStoredAsPlainJSONAndAnUnknownKeyIsDropped() throws {
        var t = CueKeyTriggers()
        t.assign(.f5, to: a)
        let data = try JSONEncoder().encode(t)
        #expect(try JSONDecoder().decode(CueKeyTriggers.self, from: data) == t)
        let newer = #"{"version": 9, "keys": [{"macro": "\#(a.uuidString)", "key": "F5"}, {"macro": "\#(b.uuidString)", "key": "F99"}]}"#
        let read = try JSONDecoder().decode(CueKeyTriggers.self, from: Data(newer.utf8))
        #expect(read.key(for: a) == .f5)
        #expect(read.key(for: b) == nil)
    }

    @Test func theBarTextNamesTheKeyAndTheMIDIPadsInOneLine() {
        #expect(CueTriggerText.summary(key: .f1, midi: ["Note C2"]) == "F1 \u{00B7} MIDI Note C2")
        #expect(CueTriggerText.summary(key: nil, midi: ["Note C2", "CC 7"]) == "MIDI Note C2, CC 7")
        #expect(CueTriggerText.summary(key: .f4, midi: []) == "F4")
        #expect(CueTriggerText.summary(key: nil, midi: []) == "none")
    }
}

/// Keys that must never run a macro, whatever the screen shows. Pure: the key monitor asks this before it asks the model.
@Suite struct UI006g_KeyGateTests {
    @Test func onlyABareFunctionKeyOutsideTextAndSheetsAndNotRepeatingGetsThrough() {
        func gate(code: UInt16 = 122, held: Bool = false, shift: Bool = false, repeating: Bool = false, text: Bool = false, sheet: Bool = false) -> CueFunctionKey? {
            CueKeyGate.key(forKeyCode: code, commandControlOptionDown: held, shiftDown: shift, isRepeat: repeating, inTextInput: text, sheetOpen: sheet)
        }
        #expect(gate() == .f1)
        #expect(gate(code: 0) == nil)
        #expect(gate(held: true) == nil)
        #expect(gate(shift: true) == nil)
        #expect(gate(repeating: true) == nil)         // a held key never runs it twice
        #expect(gate(text: true) == nil)
        #expect(gate(sheet: true) == nil)
    }
}

@MainActor
@Suite struct UI006g_KeyTriggerModelTests {
    private func rig(settings: Bool = true) async throws -> (cue: CueModel, show: FakeShow, library: LibraryStore) {
        let library = try LibraryStore.inMemory()
        let show = FakeShow()
        let workspace = WorkspaceModel(store: library)
        await workspace.load()
        let cue = CueModel(store: CueStore(library: library), ports: CuePorts(transport: workspace, looks: show, stage: show, media: show, midiOut: { show }),
                           clock: TestCueClock(), settingsStore: settings ? library : nil)
        await cue.start()
        return (cue, show, library)
    }

    @Test func aBoundKeyRunsItsMacroThroughTheOneCommandPathAndSaysSo() async throws {
        let r = try await rig()
        let look = UUID()
        r.show.looks = [look]
        let macro = try #require(await r.cue.createMacro(name: "Start"))
        await r.cue.setSteps([.selectLook(look)], of: macro.id)
        await r.cue.setKey(.f1, for: macro.id)
        #expect(r.cue.runKeyTrigger(.f1))
        await r.cue.settled()
        #expect(r.show.log == ["look \(look.uuidString.prefix(4))"])
        #expect(r.cue.activity.contains { $0.source == .key })
    }

    @Test func aKeyWithNoMacroIsLeftToTheApp() async throws {
        let r = try await rig()
        #expect(!r.cue.runKeyTrigger(.f2))
        await r.cue.settled()
        #expect(r.show.log.isEmpty)
    }

    @Test func deletingTheMacroFreesItsKey() async throws {
        let r = try await rig()
        let macro = try #require(await r.cue.createMacro(name: "Gone"))
        await r.cue.setKey(.f3, for: macro.id)
        _ = await r.cue.deleteMacro(macro.id)
        #expect(!r.cue.runKeyTrigger(.f3))
        #expect(r.cue.keyTriggers.isEmpty)
    }

    @Test func keysComeBackAfterARestartAndAMovedKeyStaysMoved() async throws {
        let r = try await rig()
        let first = try #require(await r.cue.createMacro(name: "One"))
        let second = try #require(await r.cue.createMacro(name: "Two"))
        await r.cue.setKey(.f6, for: first.id)
        await r.cue.setKey(.f6, for: second.id)          // moves it
        #expect(r.cue.keyTriggers.key(for: first.id) == nil)

        let again = CueModel(store: CueStore(library: r.library), ports: CuePorts(transport: WorkspaceModel(store: r.library), looks: r.show, stage: r.show, media: r.show, midiOut: { r.show }),
                             clock: TestCueClock(), settingsStore: r.library)
        await again.start()
        #expect(again.keyTriggers.key(for: second.id) == .f6)
        #expect(again.keyTriggers.key(for: first.id) == nil)
    }
}
