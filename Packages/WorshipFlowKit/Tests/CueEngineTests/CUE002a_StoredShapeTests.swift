// CUE-002a (KI-057): every stored cue shape carries a version, reads a missing version as 1, and reads newer data
// tolerantly (unknown keys ignored, unknown actions kept). Written by the implementer; the CUE-001 tests are unchanged.
import Testing
import Foundation
@testable import CueEngine

private func enc() -> JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }

private func topLevel(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private func uuid(_ s: String) -> UUID { UUID(uuidString: s) ?? UUID() }
private let idA = uuid("AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
private let idB = uuid("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000.25)      // a fractional second must survive

private func event() -> ScheduledEvent {
    ScheduledEvent(id: idA, name: "Sunday", isEnabled: true,
                   timing: .weekly(weekdays: [.sunday, .wednesday], hour: 10, minute: 30, timeZoneID: "America/New_York"),
                   payload: .macro(idB), activeFrom: t0)
}

@Suite struct StoredShapeVersionTests {
    @Test func macroWritesAVersionAndReadsOneWithout() throws {
        let m = Macro(id: idA, name: "Intro", steps: [.selectLook(idB), .transport(.stop)])
        let data = try enc().encode(m)
        #expect(try topLevel(data)["version"] as? Int == Macro.currentVersion)
        #expect(try JSONDecoder().decode(Macro.self, from: data) == m)

        var obj = try topLevel(data); obj["version"] = nil
        let old = try JSONSerialization.data(withJSONObject: obj)
        #expect(try JSONDecoder().decode(Macro.self, from: old) == m)
    }

    @Test func macroFromANewerVersionKeepsWhatItUnderstandsAndTheUnknownAction() throws {
        let text = """
        {"version": 99, "id": "\(idA.uuidString)", "name": "Future", "colour": "red",
         "steps": [{"kind": "look.select", "id": "\(idB.uuidString)"}, {"kind": "hologram.show", "depth": 3}]}
        """
        let m = try JSONDecoder().decode(Macro.self, from: Data(text.utf8))
        #expect(m.name == "Future" && m.steps.count == 2)
        #expect(m.steps[0] == .selectLook(idB))
        guard case .unknown(let raw) = m.steps[1] else { Issue.record("expected an unknown action"); return }
        #expect(raw.objectValue?["kind"]?.stringValue == "hologram.show")
    }

    @Test func scheduledEventRoundTripsKeepingAFractionalSecond() throws {
        let e = event()
        let data = try enc().encode(e)
        #expect(try topLevel(data)["version"] as? Int == ScheduledEvent.currentVersion)
        #expect(try JSONDecoder().decode(ScheduledEvent.self, from: data) == e)
    }

    @Test func scheduledEventReadsOlderDataWithoutOptionalFieldsAndNewerDataWithExtras() throws {
        var obj = try topLevel(try enc().encode(event()))
        obj["version"] = nil; obj["activeFrom"] = nil; obj["isEnabled"] = nil
        let old = try JSONDecoder().decode(ScheduledEvent.self, from: try JSONSerialization.data(withJSONObject: obj))
        #expect(old.activeFrom == .distantPast && old.isEnabled == true && old.name == "Sunday")

        obj["version"] = 7; obj["futureField"] = ["a": 1]
        let newer = try JSONDecoder().decode(ScheduledEvent.self, from: try JSONSerialization.data(withJSONObject: obj))
        #expect(newer.name == "Sunday")
    }

    @Test func midiBindingAndSetCarryVersions() throws {
        let b = MIDIBinding(id: idA, name: "Next", pattern: MIDIPattern(kind: .controlChange, channel: 4, number: 20, valueRange: 64...127),
                            command: .macro(idB))
        let data = try enc().encode(b)
        #expect(try topLevel(data)["version"] as? Int == MIDIBinding.currentVersion)
        #expect(try JSONDecoder().decode(MIDIBinding.self, from: data) == b)

        let set = MIDIBindingSet(bindings: [b])
        let setData = try enc().encode(set)
        #expect(try topLevel(setData)["version"] as? Int == MIDIBindingSet.currentVersion)
        #expect(try JSONDecoder().decode(MIDIBindingSet.self, from: setData) == set)

        var obj = try topLevel(setData); obj["version"] = 42; obj["extra"] = true
        let newer = try JSONDecoder().decode(MIDIBindingSet.self, from: try JSONSerialization.data(withJSONObject: obj))
        #expect(newer == set)
        obj["version"] = nil
        #expect(try JSONDecoder().decode(MIDIBindingSet.self, from: try JSONSerialization.data(withJSONObject: obj)) == set)
    }

    @Test func scheduleEngineStateHasAVersionAndSurvivesARoundTrip() throws {
        var engine = ScheduleEngine(events: [event()], gracePeriod: 120)
        _ = engine.due(after: t0.addingTimeInterval(-86_400 * 10), upTo: t0, calendar: Calendar(identifier: .gregorian))
        let data = try enc().encode(engine)
        #expect(try topLevel(data)["version"] as? Int == ScheduleEngine.currentVersion)
        let back = try JSONDecoder().decode(ScheduleEngine.self, from: data)
        #expect(back == engine)
        #expect(back.lastCheckedAt == t0 && back.gracePeriod == 120)

        // The state alone, which the store keeps apart from the events.
        let state = engine.state
        let stateData = try enc().encode(state)
        #expect(try topLevel(stateData)["version"] as? Int == ScheduleEngineState.currentVersion)
        let restored = ScheduleEngine(events: engine.events, state: try JSONDecoder().decode(ScheduleEngineState.self, from: stateData))
        #expect(restored == engine)
    }

    @Test func scheduleEngineStateReadsMissingVersionAndIgnoresUnknownKeys() throws {
        let text = """
        {"lastCheckedAt": 5.5, "gracePeriod": 60, "lastHandled": [{"event": "\(idA.uuidString)", "at": 3.0, "zzz": 1}], "futureThing": []}
        """
        let s = try JSONDecoder().decode(ScheduleEngineState.self, from: Data(text.utf8))
        #expect(s.gracePeriod == 60 && s.lastCheckedAt == Date(timeIntervalSinceReferenceDate: 5.5))
        #expect(s.lastHandled == [idA: Date(timeIntervalSinceReferenceDate: 3.0)])
        let empty = try JSONDecoder().decode(ScheduleEngineState.self, from: Data("{}".utf8))
        #expect(empty.gracePeriod == ScheduleEngine.defaultGracePeriod && empty.lastHandled.isEmpty && empty.lastCheckedAt == nil)
    }

    @Test func slideActionSetReadsMissingAndNewerVersionsAndBuildsUnvalidated() throws {
        var set = SlideActionSet()
        try set.set([.selectLook(idB)], for: idA, library: MacroLibrary())
        let data = try enc().encode(set)
        #expect(try topLevel(data)["version"] as? Int == SlideActionSet.currentVersion)

        var obj = try topLevel(data); obj["version"] = 9; obj["extra"] = 1
        #expect(try JSONDecoder().decode(SlideActionSet.self, from: try JSONSerialization.data(withJSONObject: obj)) == set)
        obj["version"] = nil
        #expect(try JSONDecoder().decode(SlideActionSet.self, from: try JSONSerialization.data(withJSONObject: obj)) == set)

        // Stored data may break the transport rule (a macro edited later); the unvalidated initialiser keeps it for `problems`.
        let bad = SlideActionSet(unvalidated: [idA: [.transport(.next)]])
        #expect(bad.actions(for: idA) == [.transport(.next)])
        #expect(bad.problems(library: MacroLibrary()).keys.contains(idA))
    }

    @Test func macroLibraryReadsAMissingVersion() throws {
        let text = "{\"macros\": [{\"id\": \"\(idA.uuidString)\", \"name\": \"A\", \"steps\": []}]}"
        let lib = try JSONDecoder().decode(MacroLibrary.self, from: Data(text.utf8))
        #expect(lib.macros.map(\.name) == ["A"])
        #expect(MacroLibrary.currentVersion == 1)
    }

    @Test func versionOfAStoredDocument() {
        #expect(CueStorage.version(in: Data("{\"version\": 3}".utf8)) == 3)
        #expect(CueStorage.version(in: Data("{}".utf8)) == nil)
        #expect(CueStorage.version(in: Data("not json".utf8)) == nil)
        #expect(CueStorage.version(in: Data("[1]".utf8)) == nil)
    }
}
