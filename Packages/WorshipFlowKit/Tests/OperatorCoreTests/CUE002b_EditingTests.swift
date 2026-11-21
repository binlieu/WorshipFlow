// CUE-002b item 6: the decisions behind the Cues mode, made where they can be tested. What an action looks like in a list, which
// kinds a picker offers and where, how steps are moved, and creating, renaming, reordering and deleting macros with the warning
// about what still uses them. The views only draw what these return.
import Testing
import Foundation
import CueEngine
import CueStore
import Persistence
@testable import OperatorCore

@Suite struct CUE002b_ActionEditingTests {
    func choices() -> CueChoices {
        CueChoices(looks: [.init(id: UUID(), name: "Worship")], props: [.init(id: UUID(), name: "Logo bug")],
                   timers: [.init(id: UUID(), name: "Service")], pictures: [.init(id: UUID(), name: "Waves.mov")],
                   sounds: [.init(id: UUID(), name: "Chime.wav")], macros: [.init(id: UUID(), name: "Start worship set")])
    }

    @Test func everyKindRoundTripsThroughItsDefaultAction() {
        let c = choices()
        for kind in CueActionKind.allCases {
            let action = CueActionEditing.defaultAction(for: kind, choices: c)
            #expect(action != nil, "\(kind)")
            #expect(action.flatMap(CueActionKind.of) == kind, "\(kind)")
        }
    }

    @Test func aKindWithNothingToChooseIsUnavailableAndSaysWhy() {
        let empty = CueChoices()
        #expect(CueActionEditing.defaultAction(for: .look, choices: empty) == nil)
        #expect(CueActionEditing.unavailableReason(for: .look, choices: empty) == "No Looks yet")
        #expect(CueActionEditing.unavailableReason(for: .playSound, choices: empty) == "No sounds in the media bin")
        #expect(CueActionEditing.unavailableReason(for: .startTimer, choices: empty) == "No timers yet")
        #expect(CueActionEditing.unavailableReason(for: .runMacro, choices: empty) == "No other macros yet")
        #expect(CueActionEditing.unavailableReason(for: .next, choices: empty) == nil)
        #expect(CueActionEditing.unavailableReason(for: .wait, choices: empty) == nil)
    }

    @Test func slideActionsOfferNoTransportKinds() {
        let kinds = CueActionKind.allCases.filter { CueActionEditing.isAllowed($0, in: .slide) }
        #expect(!kinds.isEmpty && kinds.allSatisfy { !$0.isTransport })
        #expect(CueActionKind.allCases.filter { CueActionEditing.isAllowed($0, in: .macro) }.count == CueActionKind.allCases.count)
        #expect(CueActionEditing.isAllowed(.wait, in: .slide))
    }

    @Test func aMacroPickerNeverOffersTheMacroBeingEdited() {
        let c = choices()
        let editing = c.macros[0].id
        #expect(c.macros(excluding: editing).isEmpty)
        #expect(c.macros(excluding: UUID()).count == 1)
    }

    @Test func rowsNameTheThingAndTheScreensItTouches() {
        let c = choices()
        let look = CueActionEditing.describe(.selectLook(c.looks[0].id), choices: c)
        #expect(look.title == "Set Look" && look.detail == "Worship" && look.screens == [.audience, .broadcast])
        let timer = CueActionEditing.describe(.startTimer(c.timers[0].id), choices: c)
        #expect(timer.title == "Start timer" && timer.detail == "Service" && timer.screens == [.stage])
        let message = CueActionEditing.describe(.showMessage(id: UUID(), fields: ["text": "Wrap up"]), choices: c)
        #expect(message.title == "Stage message" && message.detail == "Wrap up" && message.screens == [.stage])
        let gone = CueActionEditing.describe(.selectLook(UUID()), choices: c)
        #expect(gone.detail == "(missing Look)" && gone.isBroken)
        let wait = CueActionEditing.describe(.wait(seconds: 2.5), choices: c)
        #expect(wait.title == "Wait" && wait.detail == "2.5 s" && wait.screens.isEmpty)
        let next = CueActionEditing.describe(.transport(.next), choices: c)
        #expect(next.title == "Next slide" && next.screens == [.audience, .stage, .broadcast])
        let midi = CueActionEditing.describe(.midiOut(.noteOn(channel: 1, note: 60, velocity: 100)), choices: c)
        #expect(midi.title == "MIDI out" && midi.detail == "Note C4 on · ch 1 · velocity 100")
        let unknown = CueActionEditing.describe(.unknown(.object(["kind": .string("future.thing")])), choices: c)
        #expect(unknown.isBroken && unknown.detail.contains("future.thing"))
        let macro = CueActionEditing.describe(.runMacro(c.macros[0].id), choices: c)
        #expect(macro.title == "Run macro" && macro.detail == "Start worship set")
    }

    @Test func stepsMoveInsertReplaceAndRemoveInPlace() {
        var steps: [CueAction] = [.wait(seconds: 1), .wait(seconds: 2), .wait(seconds: 3)]
        CueStepEditing.move(&steps, from: 0, to: 2)
        #expect(steps == [.wait(seconds: 2), .wait(seconds: 3), .wait(seconds: 1)])
        CueStepEditing.move(&steps, from: 2, to: 0)
        #expect(steps == [.wait(seconds: 1), .wait(seconds: 2), .wait(seconds: 3)])
        CueStepEditing.move(&steps, from: 1, to: 9)                       // clamped
        #expect(steps.last == .wait(seconds: 2))
        CueStepEditing.insert(.stopForeground, into: &steps, at: 1)
        #expect(steps[1] == .stopForeground && steps.count == 4)
        CueStepEditing.replace(&steps, at: 1, with: .playAudio(assetID: UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))))
        #expect(steps[1] == .playAudio(assetID: UUID(uuid: (1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1))))
        CueStepEditing.remove(&steps, at: 1)
        #expect(steps.count == 3)
        CueStepEditing.remove(&steps, at: 50)                             // out of range: nothing
        #expect(steps.count == 3)
    }
}

@MainActor
@Suite struct CUE002b_MacroEditingTests {
    func make() throws -> (CueModel, FakeShow, CueStore) {
        let library = try LibraryStore.inMemory()
        let store = CueStore(library: library)
        let show = FakeShow()
        let cue = CueModel(store: store, ports: CuePorts(transport: show, looks: show, stage: show, media: show, midiOut: { nil }), clock: TestCueClock())
        return (cue, show, store)
    }

    @Test func createRenameReorderAndSaveSteps() async throws {
        let (cue, _, _) = try make()
        await cue.reload()
        let a = try #require(await cue.createMacro(name: "  Start  "))
        let b = try #require(await cue.createMacro(name: "End"))
        #expect(cue.macros.map(\.name) == ["Start", "End"])
        await cue.renameMacro(a.id, to: "Open")
        #expect(cue.macros.first?.name == "Open")
        await cue.moveMacro(b.id, to: 0)
        #expect(cue.macros.map(\.name) == ["End", "Open"])
        await cue.setSteps([.wait(seconds: 1), .stopForeground], of: a.id)
        #expect(cue.macro(a.id)?.steps == [.wait(seconds: 1), .stopForeground])
        #expect(await cue.createMacro(name: "   ") == nil)
        #expect(cue.lastError != nil)
    }

    @Test func aCycleIsRefusedWithTheEnginesWordsAndNothingChanges() async throws {
        let (cue, _, _) = try make()
        await cue.reload()
        let a = try #require(await cue.createMacro(name: "A"))
        let b = try #require(await cue.createMacro(name: "B"))
        await cue.setSteps([.runMacro(b.id)], of: a.id)
        await cue.setSteps([.runMacro(a.id)], of: b.id)
        #expect(cue.lastError?.contains("cycle") == true)
        #expect(cue.macro(b.id)?.steps.isEmpty == true)
    }

    @Test func deletingAMacroSomethingStillUsesWarnsFirstAndForceRewritesTheReferences() async throws {
        let (cue, _, store) = try make()
        await cue.reload()
        let used = try #require(await cue.createMacro(name: "Used"))
        let caller = try #require(await cue.createMacro(name: "Caller"))
        await cue.setSteps([.runMacro(used.id)], of: caller.id)
        await cue.saveBinding(MIDIBinding(name: "Pad", pattern: MIDIPattern(kind: .noteOn, channel: 1, number: 60), command: .macro(used.id)))
        let first = await cue.deleteMacro(used.id)
        guard case .blocked(let lines) = first else { Issue.record("expected blocked"); return }
        #expect(lines.contains { $0.contains("Caller") } && lines.contains { $0.contains("Pad") })
        #expect(cue.macro(used.id) != nil)                                  // nothing was deleted
        let forced = await cue.deleteMacro(used.id, force: true)
        guard case .deleted(let changes) = forced else { Issue.record("expected deleted"); return }
        #expect(changes.count == 2)
        #expect(cue.macro(used.id) == nil && cue.macro(caller.id)?.steps.isEmpty == true && cue.bindings.bindings.isEmpty)
        #expect(try await store.midiBindings().isEmpty)
    }

    @Test func aMacroNobodyUsesIsDeletedAtOnce() async throws {
        let (cue, _, _) = try make()
        await cue.reload()
        let m = try #require(await cue.createMacro(name: "Lonely"))
        guard case .deleted(let changes) = await cue.deleteMacro(m.id) else { Issue.record("expected deleted"); return }
        #expect(changes.isEmpty && cue.macros.isEmpty)
    }

    @Test func referrersAreDescribedInWords() {
        #expect(CueModel.describe(.macro(id: UUID(), name: "Caller")) == "the macro \u{201C}Caller\u{201D}")
        #expect(CueModel.describe(.scheduledEvent(id: UUID(), name: "Doors")) == "the scheduled event \u{201C}Doors\u{201D}")
        #expect(CueModel.describe(.midiBinding(id: UUID(), name: "Pad")) == "the MIDI binding \u{201C}Pad\u{201D}")
        #expect(CueModel.describe(.slide(id: UUID())) == "a slide\u{2019}s actions")
        #expect(CueModel.describe(.unreadable(record: .macro, id: "x")).contains("cannot be read"))
        #expect(CueModel.describe(change: .macroStepsRemoved(id: UUID(), name: "Caller", count: 1)).contains("Caller"))
    }
}
