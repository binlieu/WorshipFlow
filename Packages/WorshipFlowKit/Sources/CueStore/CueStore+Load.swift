// CUE-002a: the whole library in one read, with a report of what could not be loaded cleanly.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

extension CueStore {
    /// Reads macros, slide actions, events, the engine's state and MIDI bindings in one snapshot and returns them as the
    /// cue engine's own types. A row that cannot be decoded is skipped, one from a newer format is loaded as far as it is
    /// understood, an unknown action is kept; each is listed in `issues`. Nothing is repaired or rewritten.
    public func loadLibrary() async throws -> CueLibrary {
        try await library.cueRead { db in
            try CueRows.require(db)
            var issues: [CueLoadIssue] = []

            func check<T>(_ r: StoredRecord<T>, _ kind: CueRecordKind, current: Int) {
                if let failure = r.failure { issues.append(CueLoadIssue(record: kind, recordID: r.id, problem: .unreadable(failure))) }
                else if let v = r.version, v > current { issues.append(CueLoadIssue(record: kind, recordID: r.id, problem: .newerVersion(found: v, supported: current))) }
            }
            func unknown(_ actions: [CueAction], _ kind: CueRecordKind, _ id: String) {
                for u in CueActionList(actions: actions).unknownActions {
                    issues.append(CueLoadIssue(record: kind, recordID: id, problem: .unknownAction(index: u.index, kind: u.description)))
                }
            }

            let macroRecords = try CueRows.macros(db)
            for r in macroRecords {
                check(r, .macro, current: Macro.currentVersion)
                if let m = r.value { unknown(m.steps, .macro, r.id) }
            }
            let macros = MacroLibrary(unvalidated: macroRecords.compactMap(\.value))
            for problem in macros.issues() {
                issues.append(CueLoadIssue(record: .macro, recordID: Self.macroID(for: problem, in: macros), problem: .macroLibrary(problem)))
            }

            let slideRecords = try CueRows.slideActions(db)
            for r in slideRecords {
                check(r, .slideActions, current: CueActionList.currentVersion)
                if let list = r.value { unknown(list.actions, .slideActions, r.id) }
            }
            let slideSet = CueRows.slideActionSet(slideRecords)
            for (slide, errors) in slideSet.problems(library: macros).sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
                for e in errors { issues.append(CueLoadIssue(record: .slideActions, recordID: slide.uuidString, problem: .slideActionNotAllowed(e))) }
            }

            let eventRecords = try CueRows.events(db)
            for r in eventRecords {
                check(r, .scheduledEvent, current: ScheduledEvent.currentVersion)
                if let e = r.value { unknown(e.cueActions, .scheduledEvent, r.id) }
            }
            let events = eventRecords.compactMap(\.value)

            var state = ScheduleEngineState()
            if let raw = try String.fetchOne(db, sql: "SELECT state FROM cueScheduleState WHERE id = 1") {
                let r = CueRows.decode(ScheduleEngineState.self, id: "1", raw: raw)
                check(r, .scheduleState, current: ScheduleEngineState.currentVersion)
                if let s = r.value { state = s }
            }
            let known = Set(events.map(\.id))
            state.lastHandled = state.lastHandled.filter { known.contains($0.key) }

            let bindingRecords = try CueRows.bindings(db)
            for r in bindingRecords { check(r, .midiBinding, current: MIDIBinding.currentVersion) }

            return CueLibrary(macros: macros, slideActions: slideSet, schedule: ScheduleEngine(events: events, state: state),
                              midi: MIDIBindingSet(bindings: bindingRecords.compactMap(\.value)), issues: issues)
        }
    }

    /// The id of the first macro a library problem is about, or "" when it cannot be told.
    static func macroID(for problem: MacroLibraryError, in library: MacroLibrary) -> String {
        let name: String?
        switch problem {
        case .cycle(let names): name = names.first
        case .tooDeep(let macro, _, _): name = macro
        case .emptyName: name = nil
        }
        return library.macros.first { $0.name == name }?.id.uuidString ?? ""
    }
}
