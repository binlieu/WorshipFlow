// CUE-002a (AUTO-03, AUTO-04): MIDI bindings, and loading everything with a report of what could not be read.
import Testing
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence
import CueStore

@Suite struct CueStoreMIDITests {
    @Test func savesListsInOrderAndReturnsTheConflictsItFound() async throws {
        let f = try Fixture()
        let a = noteBinding("A", note: 60, .transport(.next))
        #expect(try await f.store.saveMIDIBinding(a).isEmpty)
        let clash = noteBinding("B", note: 60, .transport(.previous))
        let conflicts = try await f.store.saveMIDIBinding(clash)
        #expect(conflicts == [a])
        #expect(try await f.store.midiBindings() == [a, clash])           // saved anyway: the engine's first-match rule decides
        // Replacing a binding by itself is not a conflict.
        var a2 = a; a2.name = "A2"
        #expect(try await f.store.saveMIDIBinding(a2) == [clash])
        #expect(try await f.store.midiBindings().map(\.name) == ["A2", "B"])
        #expect(try await f.store.saveMIDIBinding(noteBinding("C", note: 61, .transport(.stop))).isEmpty)
    }

    @Test func aPatternThatCanNeverMatchAndAMacroThatDoesNotExistAreRefused() async throws {
        let f = try Fixture()
        let bad = MIDIBinding(name: "Bad", pattern: MIDIPattern(kind: .noteOn, channel: 17), command: .transport(.next))
        await #expect(throws: CueStoreError.invalidBinding("Bad")) { _ = try await f.store.saveMIDIBinding(bad) }
        let missing = UUID()
        await #expect(throws: CueStoreError.unknownMacro(missing)) { _ = try await f.store.saveMIDIBinding(noteBinding("M", note: 1, .macro(missing))) }
        #expect(try await f.rawCount("cueMIDIBinding") == 0)
    }

    @Test func deleteReorderAndTheResultingSetMatchesMessages() async throws {
        let f = try Fixture()
        let a = noteBinding("A", note: 60, .transport(.next)), b = noteBinding("B", note: 61, .transport(.previous)), c = noteBinding("C", note: 62, .transport(.stop))
        for x in [a, b, c] { _ = try await f.store.saveMIDIBinding(x) }
        try await f.store.reorderMIDIBindings([c.id])
        #expect(try await f.store.midiBindings().map(\.name) == ["C", "A", "B"])
        try await f.store.deleteMIDIBinding(id: a.id)
        let orders = try await f.library.cueRead { try Int.fetchAll($0, sql: "SELECT sortOrder FROM cueMIDIBinding ORDER BY sortOrder") }
        #expect(orders == [0, 1])
        let set = try await f.store.loadLibrary().midi
        #expect(set.command(for: .noteOn(channel: 1, note: 62, velocity: 100)) == .transport(.stop))
        #expect(set.command(for: .noteOn(channel: 1, note: 60, velocity: 100)) == nil)
        await #expect(throws: CueStoreError.notFound) { try await f.store.deleteMIDIBinding(id: a.id) }
        await #expect(throws: CueStoreError.notFound) { try await f.store.reorderMIDIBindings([UUID()]) }
    }
}

@Suite struct CueStoreLoadTests {
    @Test func loadsEverythingIntoTheEngineTypesInOneRead() async throws {
        let f = try Fixture()
        let slide = try #require(try await f.slides(["one"]).first)
        let m = macro("M", [.selectLook(UUID())])
        try await f.store.saveMacro(m)
        try await f.store.setSlideActions([.runMacro(m.id)], for: slide.id)
        let e = try await f.store.saveScheduledEvent(weekly("E", payload: .macro(m.id)))
        let b = noteBinding("B", note: 1, .macro(m.id))
        _ = try await f.store.saveMIDIBinding(b)

        let lib = try await f.store.loadLibrary()
        #expect(lib.issues.isEmpty)
        #expect(lib.macros.macros == [m] && lib.macros.issues().isEmpty)
        #expect(lib.slideActions.actions(for: slide.id) == [.runMacro(m.id)])
        #expect(lib.schedule.events == [e] && lib.schedule.gracePeriod == ScheduleEngine.defaultGracePeriod)
        #expect(lib.midi.bindings == [b])
    }

    @Test func anEmptyLibraryLoadsEmpty() async throws {
        let lib = try await Fixture().store.loadLibrary()
        #expect(lib.macros.macros.isEmpty && lib.midi.bindings.isEmpty && lib.schedule.events.isEmpty && lib.issues.isEmpty)
        #expect(lib.slideActions.slideIDs.isEmpty && lib.schedule.lastCheckedAt == nil)
    }

    @Test func anUnreadableRowIsReportedAndSkippedWhileTheRestLoads() async throws {
        let f = try Fixture()
        let good = macro("Good")
        try await f.store.saveMacro(good)
        try await f.rawExec("INSERT INTO cueMacro (id, name, definition, sortOrder, createdAt, updatedAt) VALUES ('BAD', 'Bad', 'not json', 5, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')")
        try await f.rawExec("INSERT INTO cueMIDIBinding (id, definition, sortOrder) VALUES ('BADM', '{\"version\":1}', 0)")
        try await f.rawExec("INSERT INTO cueScheduledEvent (id, name, enabled, definition, createdAt, updatedAt) VALUES ('BADE', 'E', 1, '[]', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')")
        try await f.rawExec("INSERT INTO cueScheduleState (id, state, lastCheckedAt, updatedAt) VALUES (1, 'nope', NULL, '2026-01-01 00:00:00.000')")
        let lib = try await f.store.loadLibrary()
        #expect(lib.macros.macros == [good])
        let found = Set(lib.issues.map { "\($0.record.rawValue):\($0.recordID)" })
        #expect(found == ["macro:BAD", "midiBinding:BADM", "scheduledEvent:BADE", "scheduleState:1"])
        for issue in lib.issues { guard case .unreadable = issue.problem else { Issue.record("expected unreadable, got \(issue.problem)"); continue } }
        #expect(try await f.store.macros() == [good])
    }

    @Test func aNewerVersionRowLoadsAsFarAsItIsUnderstoodAndIsReportedAndNeverOverwritten() async throws {
        let f = try Fixture()
        let id = UUID()
        let text = "{\"version\": 7, \"id\": \"\(id.uuidString)\", \"name\": \"Future\", \"colour\": \"red\", \"steps\": [{\"kind\": \"hologram\", \"depth\": 3}]}"
        try await f.rawExec("INSERT INTO cueMacro (id, name, definition, sortOrder, createdAt, updatedAt) VALUES (?, 'Future', ?, 0, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')", [id.uuidString, text])
        let lib = try await f.store.loadLibrary()
        #expect(lib.macros.macros.map(\.name) == ["Future"])
        #expect(lib.issues.contains { $0.recordID == id.uuidString && $0.problem == .newerVersion(found: 7, supported: 1) })
        #expect(lib.issues.contains { $0.recordID == id.uuidString && $0.problem == .unknownAction(index: 0, kind: "hologram") })
        // Saving over it with this version would drop the fields it does not know: refused, row unchanged.
        await #expect(throws: CueStoreError.self) { try await f.store.saveMacro(macro("Mine", [], id: id)) }
        await #expect(throws: CueStoreError.self) { try await f.store.renameMacro(id: id, to: "X") }
        #expect(try await f.rawString("SELECT definition FROM cueMacro WHERE id = ?", [id.uuidString]) == text)
    }

    @Test func unknownActionsInSlideActionsAndEventsAreReported() async throws {
        let f = try Fixture()
        let slide = try #require(try await f.slides(["one"]).first)
        try await f.rawExec("INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, '{\"version\":1,\"actions\":[{\"kind\":\"zap\"}]}', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')", [slide.id.uuidString])
        let lib = try await f.store.loadLibrary()
        #expect(lib.issues.contains { $0.record == .slideActions && $0.problem == .unknownAction(index: 0, kind: "zap") })
        #expect(lib.slideActions.actions(for: slide.id).count == 1)
    }

    @Test func damagedStoredDataIsReportedNotRepaired() async throws {
        let f = try Fixture()
        // A cycle and a transport in a slide's macro, written straight to the table as a damaged file might hold them.
        let a = macro("A"), b = macro("B", [.runMacro(a.id)])
        var a2 = a; a2.steps = [.runMacro(b.id), .transport(.next)]
        let enc = JSONEncoder()
        for (i, m) in [a2, b].enumerated() {
            let text = String(decoding: try enc.encode(m), as: UTF8.self)
            try await f.rawExec("INSERT INTO cueMacro (id, name, definition, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')", [m.id.uuidString, m.name, text, String(i)])
        }
        let slide = try #require(try await f.slides(["one"]).first)
        try await f.rawExec("INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')",
                            [slide.id.uuidString, String(decoding: try enc.encode(CueActionList(actions: [.runMacro(b.id)])), as: UTF8.self)])
        let lib = try await f.store.loadLibrary()
        #expect(lib.macros.macros.count == 2)
        #expect(lib.issues.contains { if case .macroLibrary(.cycle) = $0.problem { return true } else { return false } })
        #expect(lib.issues.contains { $0.record == .slideActions && $0.recordID == slide.id.uuidString && { if case .slideActionNotAllowed = $0.problem { return true } else { return false } }($0) })
    }

    @Test func everythingSurvivesClosingAndReopeningTheFile() async throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wf-cue002a-\(UUID().uuidString)/L.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let slideID: UUID
        let m = macro("M", [.selectLook(UUID())])
        do {
            let f = try Fixture(library: try LibraryStore.open(at: url))
            slideID = try #require(try await f.slides(["one"]).first).id
            try await f.store.saveMacro(m)
            try await f.store.setSlideActions([.runMacro(m.id)], for: slideID)
            try await f.store.saveScheduleState(ScheduleEngineState(lastCheckedAt: t0))
            try f.library.close()
        }
        let f = try Fixture(library: try LibraryStore.open(at: url))
        let lib = try await f.store.loadLibrary()
        #expect(lib.macros.macros == [m] && lib.slideActions.actions(for: slideID) == [.runMacro(m.id)] && lib.schedule.lastCheckedAt == t0)
        try f.library.close()
    }
}
