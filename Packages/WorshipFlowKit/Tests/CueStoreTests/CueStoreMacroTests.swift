// CUE-002a (AUTO-02): macros in the library file. Written by the implementer.
import Testing
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

@Suite struct CueStoreMacroTests {
    @Test func savesAndListsInOrderAndASecondSaveReplacesInPlace() async throws {
        let f = try Fixture()
        let a = macro("Intro", [.selectLook(UUID())]), b = macro("Outro", [.transport(.stop)])
        try await f.store.saveMacro(a)
        try await f.store.saveMacro(b)
        var a2 = a; a2.name = "Intro 2"; a2.steps = []
        try await f.store.saveMacro(a2)
        #expect(try await f.store.macros() == [a2, b])
        #expect(try await f.rawCount("cueMacro") == 2)
    }

    @Test func aCycleIsRejectedWithTheEnginesMessageAndNothingIsWritten() async throws {
        let f = try Fixture()
        let a = macro("A"), b = macro("B", [.runMacro(a.id)])
        try await f.store.saveMacro(a)
        try await f.store.saveMacro(b)
        var a2 = a; a2.steps = [.runMacro(b.id)]
        let error = await #expect(throws: CueStoreError.self) { try await f.store.saveMacro(a2) }
        #expect(error?.message == "Macro cycle: A \u{2192} B \u{2192} A")
        #expect(try await f.store.macros() == [a, b])
    }

    @Test func tooDeepANestIsRejected() async throws {
        let f = try Fixture()
        var chain: [Macro] = [macro("M0")]
        try await f.store.saveMacro(chain[0])
        for i in 1..<MacroLibrary.maxDepth {
            let m = macro("M\(i)", [.runMacro(chain[i - 1].id)]); chain.append(m); try await f.store.saveMacro(m)
        }
        let top = macro("Top", [.runMacro(chain[chain.count - 1].id)])
        let error = await #expect(throws: CueStoreError.self) { try await f.store.saveMacro(top) }
        #expect(error?.message == "Macro \u{201C}Top\u{201D} would nest 9 levels deep; the limit is 8")
        #expect(try await f.rawCount("cueMacro") == MacroLibrary.maxDepth)
    }

    @Test func aBlankNameIsRejected() async throws {
        let f = try Fixture()
        await #expect(throws: CueStoreError.self) { try await f.store.saveMacro(macro("  ")) }
        #expect(try await f.rawCount("cueMacro") == 0)
    }

    @Test func editingAMacroToMoveTheShowIsRefusedWhileASlideRunsIt() async throws {
        let f = try Fixture()
        let slide = try #require(try await f.slides(["one"]).first)
        let m = macro("Look", [.selectLook(UUID())])
        try await f.store.saveMacro(m)
        try await f.store.setSlideActions([.runMacro(m.id)], for: slide.id)
        var edited = m; edited.steps = [.transport(.next)]
        let error = await #expect(throws: CueStoreError.self) { try await f.store.saveMacro(edited) }
        guard case .macroBreaksSlideActions(let problems)? = error else { Issue.record("wrong error \(String(describing: error))"); return }
        #expect(problems.keys.contains(slide.id))
        #expect(try await f.store.macros() == [m])
    }

    @Test func renameChangesTheStoredDefinitionToo() async throws {
        let f = try Fixture()
        let m = macro("Old", [.selectLook(UUID())])
        try await f.store.saveMacro(m)
        try await f.store.renameMacro(id: m.id, to: "New")
        #expect(try await f.store.macros().map(\.name) == ["New"])
        #expect(try await f.rawString("SELECT name FROM cueMacro WHERE id = ?", [m.id.uuidString]) == "New")
        await #expect(throws: CueStoreError.self) { try await f.store.renameMacro(id: m.id, to: " ") }
        await #expect(throws: CueStoreError.notFound) { try await f.store.renameMacro(id: UUID(), to: "X") }
        #expect(try await f.store.macros().map(\.name) == ["New"])
    }

    @Test func reorderPlacesTheGivenOnesFirstAndRefusesUnknownIDsWithoutChange() async throws {
        let f = try Fixture()
        let a = macro("A"), b = macro("B"), c = macro("C")
        for m in [a, b, c] { try await f.store.saveMacro(m) }
        try await f.store.reorderMacros([c.id, a.id])
        #expect(try await f.store.macros().map(\.name) == ["C", "A", "B"])
        await #expect(throws: CueStoreError.notFound) { try await f.store.reorderMacros([b.id, UUID()]) }
        await #expect(throws: CueStoreError.self) { try await f.store.reorderMacros([b.id, b.id]) }
        #expect(try await f.store.macros().map(\.name) == ["C", "A", "B"])
        // Dense order after a delete.
        _ = try await f.store.deleteMacro(id: a.id)
        let orders = try await f.library.cueRead { try Int.fetchAll($0, sql: "SELECT sortOrder FROM cueMacro ORDER BY sortOrder") }
        #expect(orders == [0, 1])
    }

    @Test func anUnreferencedMacroDeletesAndAMissingOneIsNotFound() async throws {
        let f = try Fixture()
        let m = macro("M")
        try await f.store.saveMacro(m)
        let result = try await f.store.deleteMacro(id: m.id)
        #expect(result.deleted && result.blockedBy.isEmpty && result.changes.isEmpty)
        #expect(try await f.store.macros().isEmpty)
        await #expect(throws: CueStoreError.notFound) { _ = try await f.store.deleteMacro(id: m.id) }
    }

    /// One macro used by another macro, a slide, an event and a MIDI binding.
    func referencedEverywhere(_ f: Fixture) async throws -> (target: Macro, other: Macro, slide: UUID, event: ScheduledEvent, event2: ScheduledEvent, binding: MIDIBinding) {
        let target = macro("Target", [.selectLook(UUID())])
        let other = macro("Other", [.selectLook(UUID()), .runMacro(target.id), .runMacro(target.id)])
        let slide = try #require(try await f.slides(["one"]).first).id
        let event = weekly("ByMacro", payload: .macro(target.id))
        let event2 = weekly("ByAction", payload: .actions([.runMacro(target.id), .selectLook(UUID())]))
        let binding = noteBinding("Pad", note: 60, .macro(target.id))
        try await f.store.saveMacro(target)
        try await f.store.saveMacro(other)
        try await f.store.setSlideActions([.runMacro(target.id)], for: slide)
        try await f.store.saveScheduledEvent(event)
        try await f.store.saveScheduledEvent(event2)
        _ = try await f.store.saveMIDIBinding(binding)
        return (target, other, slide, event, event2, binding)
    }

    @Test func aReferencedMacroIsNotDeletedAndTheReferrersAreListed() async throws {
        let f = try Fixture()
        let w = try await referencedEverywhere(f)
        let result = try await f.store.deleteMacro(id: w.target.id)
        #expect(!result.deleted && result.changes.isEmpty)
        #expect(Set(result.blockedBy) == [.macro(id: w.other.id, name: "Other"), .slide(id: w.slide),
                                          .scheduledEvent(id: w.event.id, name: "ByMacro"), .scheduledEvent(id: w.event2.id, name: "ByAction"),
                                          .midiBinding(id: w.binding.id, name: "Pad")])
        #expect(try await f.store.references(toMacro: w.target.id) == result.blockedBy)
        #expect(try await f.store.macros().count == 2)
        #expect(try await f.store.slideActions(for: w.slide) == [.runMacro(w.target.id)])
        #expect(try await f.store.midiBindings() == [w.binding])
    }

    @Test func forceRemovesEveryReferenceAndReportsWhatChanged() async throws {
        let f = try Fixture()
        let w = try await referencedEverywhere(f)
        f.clock.set(t0.addingTimeInterval(60))
        let result = try await f.store.deleteMacro(id: w.target.id, force: true)
        #expect(result.deleted && result.blockedBy.isEmpty)
        #expect(Set(result.changes) == [
            .macroStepsRemoved(id: w.other.id, name: "Other", count: 2),
            .slideActionsRemoved(id: w.slide, count: 1),
            .eventActionsRemoved(id: w.event2.id, name: "ByAction", count: 1, disabled: false),
            .eventActionsRemoved(id: w.event.id, name: "ByMacro", count: 1, disabled: true),
            .midiBindingDeleted(id: w.binding.id, name: "Pad")])
        let other = try #require(try await f.store.macros().first)
        #expect(other.steps.count == 1 && other.name == "Other")
        #expect(try await f.store.slideActions(for: w.slide).isEmpty)
        #expect(try await f.rawCount("cueSlideActions") == 0)
        let events = Dictionary(uniqueKeysWithValues: try await f.store.scheduledEvents().map { ($0.name, $0) })
        #expect(events["ByAction"]?.cueActions.count == 1 && events["ByAction"]?.isEnabled == true)
        #expect(events["ByMacro"]?.isEnabled == false && events["ByMacro"]?.cueActions.isEmpty == true)
        #expect(try await f.rawString("SELECT enabled FROM cueScheduledEvent WHERE name = 'ByMacro'") == "0")
        #expect(try await f.store.midiBindings().isEmpty)
        // Nothing refers to the id any more.
        #expect(try await f.store.references(toMacro: w.target.id).isEmpty)
    }

    @Test func aReferenceInAnUnreadableRowBlocksTheDeleteAndForceLeavesItAlone() async throws {
        let f = try Fixture()
        let m = macro("M")
        try await f.store.saveMacro(m)
        try await f.rawExec("INSERT INTO cueMIDIBinding (id, definition, sortOrder) VALUES ('X1', ?, 0)",
                            ["{\"version\":1,\"pattern\":\"garbled\",\"command\":{\"macro\":{\"_0\":\"\(m.id.uuidString.lowercased())\"}}}"])
        let blocked = try await f.store.deleteMacro(id: m.id)
        #expect(!blocked.deleted && blocked.blockedBy == [.unreadable(record: .midiBinding, id: "X1")])
        let forced = try await f.store.deleteMacro(id: m.id, force: true)
        #expect(forced.deleted && forced.leftUnreadable == [.unreadable(record: .midiBinding, id: "X1")])
        #expect(try await f.rawCount("cueMIDIBinding") == 1)
    }

    @Test func aFailureHalfWayThroughAForcedDeleteChangesNothing() async throws {
        let f = try Fixture()
        let w = try await referencedEverywhere(f)
        // A trigger makes the final DELETE fail, after the references were already rewritten inside the transaction.
        try await f.rawExec("CREATE TRIGGER stopDelete BEFORE DELETE ON cueMacro WHEN OLD.name = 'Target' BEGIN SELECT RAISE(ABORT, 'no'); END")
        await #expect(throws: (any Error).self) { _ = try await f.store.deleteMacro(id: w.target.id, force: true) }
        #expect(try await f.store.macros().count == 2)
        #expect(try await f.store.macros().last?.steps.count == 3)
        #expect(try await f.store.slideActions(for: w.slide) == [.runMacro(w.target.id)])
        #expect(try await f.store.midiBindings() == [w.binding])
        #expect(try await f.store.scheduledEvents().first?.isEnabled == true)
    }
}
