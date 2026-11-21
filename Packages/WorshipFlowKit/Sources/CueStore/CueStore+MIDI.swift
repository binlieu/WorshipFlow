// CUE-002a (AUTO-03, AUTO-04): MIDI bindings.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

extension CueStore {
    /// Bindings in the operator's order, which is also the engine's first-match order.
    public func midiBindings() async throws -> [MIDIBinding] {
        try await library.cueRead { db in
            try CueRows.require(db)
            return try CueRows.bindings(db).compactMap(\.value)
        }
    }

    /// Adds the binding, or replaces the one with the same id in place. A pattern no message can match, or a macro that
    /// does not exist, is refused. Overlapping bindings are saved (the first in the list wins when a message matches
    /// both) and the other bindings it overlaps are returned, so the caller can warn.
    @discardableResult
    public func saveMIDIBinding(_ binding: MIDIBinding) async throws -> [MIDIBinding] {
        try await library.cueWrite { db in
            try CueRows.require(db)
            guard binding.pattern.isValid else { throw CueStoreError.invalidBinding(binding.name) }
            if case .macro(let id) = binding.command, try !CueRows.macroExists(db, id) { throw CueStoreError.unknownMacro(id) }
            let records = try CueRows.bindings(db)
            if let old = records.first(where: { $0.id == binding.id.uuidString }) {
                try old.requireWritable(.midiBinding, currentVersion: MIDIBinding.currentVersion)
            }
            let conflicts = MIDIBindingSet(bindings: records.compactMap(\.value)).conflicts(with: binding)
            try db.execute(sql: """
                INSERT INTO cueMIDIBinding (id, definition, sortOrder)
                VALUES (?, ?, (SELECT COALESCE(MAX(sortOrder), -1) + 1 FROM cueMIDIBinding))
                ON CONFLICT(id) DO UPDATE SET definition = excluded.definition
                """, arguments: [binding.id.uuidString, try CueCoding.encode(binding)])
            return conflicts
        }
    }

    public func deleteMIDIBinding(id: UUID) async throws {
        try await library.cueWrite { db in
            try CueRows.require(db)
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM cueMIDIBinding WHERE id = ?)", arguments: [id.uuidString]) == true
            else { throw CueStoreError.notFound }
            try db.execute(sql: "DELETE FROM cueMIDIBinding WHERE id = ?", arguments: [id.uuidString])
            try CueRows.renumber(db, table: "cueMIDIBinding")
        }
    }

    /// Puts the named bindings first, in the given order; any others follow in their old order.
    public func reorderMIDIBindings(_ ids: [UUID]) async throws {
        try await library.cueWrite { db in
            try CueRows.require(db)
            try CueRows.reorder(db, table: "cueMIDIBinding", ids: ids)
        }
    }
}
