// CUE-002a (AUTO-02): macros.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

extension CueStore {
    /// Macros in the operator's order. A row that cannot be read is left out; `loadLibrary()` reports it.
    public func macros() async throws -> [Macro] {
        try await library.cueRead { db in
            try CueRows.require(db)
            return try CueRows.macros(db).compactMap(\.value)
        }
    }

    /// Adds the macro, or replaces the one with the same id in place. The engine's rules apply (a name, no cycle, at most
    /// `MacroLibrary.maxDepth` levels), and so does the slide rule: a macro that slides run may not gain a transport command.
    /// A refusal throws and writes nothing.
    public func saveMacro(_ macro: Macro) async throws {
        let stamp = now()
        try await library.cueWrite { db in
            try CueRows.require(db)
            let records = try CueRows.macros(db)
            if let existing = records.first(where: { $0.id == macro.id.uuidString }) {
                try existing.requireWritable(.macro, currentVersion: Macro.currentVersion)
            }
            let before = MacroLibrary(unvalidated: records.compactMap(\.value))
            var after = before
            do { try after.save(macro) } catch let error as MacroLibraryError { throw CueStoreError.invalidMacro(error) }

            let slides = CueRows.slideActionSet(try CueRows.slideActions(db))
            let was = slides.problems(library: before), now = slides.problems(library: after)
            let added = now.filter { was[$0.key] == nil }
            guard added.isEmpty else { throw CueStoreError.macroBreaksSlideActions(added) }

            try db.execute(sql: """
                INSERT INTO cueMacro (id, name, definition, sortOrder, createdAt, updatedAt)
                VALUES (?, ?, ?, (SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM cueMacro), ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, definition = excluded.definition, updatedAt = excluded.updatedAt
                """, arguments: [macro.id.uuidString, macro.name, try CueCoding.encode(macro), stamp, stamp])
        }
    }

    public func renameMacro(id: UUID, to name: String) async throws {
        let stamp = now()
        try await library.cueWrite { db in
            try CueRows.require(db)
            guard let record = try CueRows.macros(db).first(where: { $0.id == id.uuidString }) else { throw CueStoreError.notFound }
            try record.requireWritable(.macro, currentVersion: Macro.currentVersion)
            guard var macro = record.value else { throw CueStoreError.unreadable(record: .macro, id: record.id) }
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CueStoreError.invalidMacro(.emptyName) }
            macro.name = name
            try db.execute(sql: "UPDATE cueMacro SET name = ?, definition = ?, updatedAt = ? WHERE id = ?",
                           arguments: [name, try CueCoding.encode(macro), stamp, id.uuidString])
        }
    }

    /// Puts the named macros first, in the given order; any others follow in their old order. An unknown id or a repeated
    /// id throws and changes nothing.
    public func reorderMacros(_ ids: [UUID]) async throws {
        try await library.cueWrite { db in
            try CueRows.require(db)
            try CueRows.reorder(db, table: "cueMacro", ids: ids)
        }
    }

    /// Everything that runs this macro: other macros, slides, events and MIDI bindings. Rows that cannot be read are
    /// listed as `.unreadable` when their text mentions the id.
    public func references(toMacro id: UUID) async throws -> [CueReferrer] {
        try await library.cueRead { db in
            try CueRows.require(db)
            return try Self.referrers(db, toMacro: id)
        }
    }

    /// Deletes the macro. While anything still runs it, nothing is deleted and the referrers come back in `blockedBy`.
    /// With `force`, the references are removed first, in the same transaction, and reported in `changes`: macro steps and
    /// slide actions that run it are dropped (a slide left with none loses its row); an event that runs it as its macro
    /// has nothing left and is switched off, as is an event whose last action it was; a MIDI binding that runs it is deleted.
    /// Rows that cannot be read are left as they are and listed in `leftUnreadable`.
    public func deleteMacro(id: UUID, force: Bool = false) async throws -> MacroDeletion {
        let stamp = now()
        return try await library.cueWrite { db in
            try CueRows.require(db)
            guard try CueRows.macroExists(db, id) else { throw CueStoreError.notFound }
            let referrers = try Self.referrers(db, toMacro: id)
            if !referrers.isEmpty && !force {
                return MacroDeletion(deleted: false, blockedBy: referrers, changes: [], leftUnreadable: [])
            }
            var changes: [CueReferenceChange] = []
            var left: [CueReferrer] = []
            let drop = CueAction.runMacro(id)

            for record in try CueRows.macros(db) where record.id != id.uuidString {
                guard var m = record.value, record.isWritable(currentVersion: Macro.currentVersion) else {
                    if let r = Self.rawReferrer(record, kind: .macro, id: id) { left.append(r) }
                    continue
                }
                let kept = m.steps.filter { $0 != drop }
                guard kept.count != m.steps.count else { continue }
                changes.append(.macroStepsRemoved(id: m.id, name: m.name, count: m.steps.count - kept.count))
                m.steps = kept
                try db.execute(sql: "UPDATE cueMacro SET definition = ?, updatedAt = ? WHERE id = ?",
                               arguments: [try CueCoding.encode(m), stamp, record.id])
            }

            for record in try CueRows.slideActions(db) {
                guard let list = record.value, record.isWritable(currentVersion: CueActionList.currentVersion) else {
                    if let r = Self.rawReferrer(record, kind: .slideActions, id: id) { left.append(r) }
                    continue
                }
                let kept = list.actions.filter { $0 != drop }
                guard kept.count != list.actions.count, let slide = UUID(uuidString: record.id) else { continue }
                changes.append(.slideActionsRemoved(id: slide, count: list.actions.count - kept.count))
                if kept.isEmpty {
                    try db.execute(sql: "DELETE FROM cueSlideActions WHERE slideID = ?", arguments: [record.id])
                } else {
                    try db.execute(sql: "UPDATE cueSlideActions SET definition = ?, updatedAt = ? WHERE slideID = ?",
                                   arguments: [try CueCoding.encode(CueActionList(actions: kept)), stamp, record.id])
                }
            }

            for record in try CueRows.events(db) {
                guard var event = record.value, record.isWritable(currentVersion: ScheduledEvent.currentVersion) else {
                    if let r = Self.rawReferrer(record, kind: .scheduledEvent, id: id) { left.append(r) }
                    continue
                }
                let wasEnabled = event.isEnabled
                switch event.payload {
                case .macro(let target) where target == id:
                    event.payload = .actions([])
                    event.isEnabled = false
                    changes.append(.eventActionsRemoved(id: event.id, name: event.name, count: 1, disabled: wasEnabled))
                case .actions(let actions):
                    let kept = actions.filter { $0 != drop }
                    guard kept.count != actions.count else { continue }
                    event.payload = .actions(kept)
                    if kept.isEmpty { event.isEnabled = false }
                    changes.append(.eventActionsRemoved(id: event.id, name: event.name, count: actions.count - kept.count,
                                                        disabled: wasEnabled && !event.isEnabled))
                default: continue
                }
                try db.execute(sql: "UPDATE cueScheduledEvent SET enabled = ?, definition = ?, updatedAt = ? WHERE id = ?",
                               arguments: [event.isEnabled, try CueCoding.encode(event), stamp, record.id])
            }

            var bindingDeleted = false
            for record in try CueRows.bindings(db) {
                guard let binding = record.value, record.isWritable(currentVersion: MIDIBinding.currentVersion) else {
                    if let r = Self.rawReferrer(record, kind: .midiBinding, id: id) { left.append(r) }
                    continue
                }
                guard binding.command == .macro(id) else { continue }
                try db.execute(sql: "DELETE FROM cueMIDIBinding WHERE id = ?", arguments: [record.id])
                changes.append(.midiBindingDeleted(id: binding.id, name: binding.name))
                bindingDeleted = true
            }
            if bindingDeleted { try CueRows.renumber(db, table: "cueMIDIBinding") }

            try db.execute(sql: "DELETE FROM cueMacro WHERE id = ?", arguments: [id.uuidString])
            try CueRows.renumber(db, table: "cueMacro")
            return MacroDeletion(deleted: true, blockedBy: [], changes: changes, leftUnreadable: left)
        }
    }

    // MARK: References

    /// An unreadable or newer-version row is judged by its text, since its fields cannot be trusted.
    static func rawReferrer<T>(_ record: StoredRecord<T>, kind: CueRecordKind, id: UUID) -> CueReferrer? {
        record.raw.lowercased().contains(id.uuidString.lowercased()) ? .unreadable(record: kind, id: record.id) : nil
    }

    static func referrers(_ db: Database, toMacro id: UUID) throws -> [CueReferrer] {
        let drop = CueAction.runMacro(id)
        var out: [CueReferrer] = []
        for r in try CueRows.macros(db) where r.id != id.uuidString {
            if let m = r.value, r.isWritable(currentVersion: Macro.currentVersion) {
                if m.steps.contains(drop) { out.append(.macro(id: m.id, name: m.name)) }
            } else if let u = rawReferrer(r, kind: .macro, id: id) { out.append(u) }
        }
        for r in try CueRows.slideActions(db) {
            if let list = r.value, r.isWritable(currentVersion: CueActionList.currentVersion) {
                if list.actions.contains(drop), let slide = UUID(uuidString: r.id) { out.append(.slide(id: slide)) }
            } else if let u = rawReferrer(r, kind: .slideActions, id: id) { out.append(u) }
        }
        for r in try CueRows.events(db) {
            if let e = r.value, r.isWritable(currentVersion: ScheduledEvent.currentVersion) {
                let uses: Bool
                switch e.payload {
                case .macro(let target): uses = target == id
                case .actions(let actions): uses = actions.contains(drop)
                }
                if uses { out.append(.scheduledEvent(id: e.id, name: e.name)) }
            } else if let u = rawReferrer(r, kind: .scheduledEvent, id: id) { out.append(u) }
        }
        for r in try CueRows.bindings(db) {
            if let b = r.value, r.isWritable(currentVersion: MIDIBinding.currentVersion) {
                if b.command == .macro(id) { out.append(.midiBinding(id: b.id, name: b.name)) }
            } else if let u = rawReferrer(r, kind: .midiBinding, id: id) { out.append(u) }
        }
        return out
    }
}
