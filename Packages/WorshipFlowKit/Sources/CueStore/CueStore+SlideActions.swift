// CUE-002a (AUTO-01): actions attached to slides.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

extension CueStore {
    /// The actions a slide runs when it goes live; empty when it has none.
    public func slideActions(for slideID: UUID) async throws -> [CueAction] {
        try await library.cueRead { db in
            try CueRows.require(db)
            guard let raw = try String.fetchOne(db, sql: "SELECT definition FROM cueSlideActions WHERE slideID = ?",
                                                arguments: [slideID.uuidString]) else { return [] }
            let record = CueRows.decode(CueActionList.self, id: slideID.uuidString, raw: raw)
            guard let list = record.value else { throw CueStoreError.unreadable(record: .slideActions, id: record.id) }
            return list.actions
        }
    }

    /// Replaces the slide's actions; an empty list removes them. Transport commands are refused, directly or through any
    /// macro they run (the engine's rule), and so is a macro that is not in the library. A refusal writes nothing.
    /// The actions go with the slide when it is deleted, and stay with it across a reflow that leaves its words alone.
    public func setSlideActions(_ actions: [CueAction], for slideID: UUID) async throws {
        let stamp = now()
        try await library.cueWrite { db in
            try CueRows.require(db)
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM slide WHERE id = ?)", arguments: [slideID.uuidString]) == true
            else { throw CueStoreError.notFound }
            let existing = try String.fetchOne(db, sql: "SELECT definition FROM cueSlideActions WHERE slideID = ?",
                                               arguments: [slideID.uuidString]).map {
                CueRows.decode(CueActionList.self, id: slideID.uuidString, raw: $0)
            }
            try existing?.requireWritable(.slideActions, currentVersion: CueActionList.currentVersion)

            let macros = MacroLibrary(unvalidated: try CueRows.macros(db).compactMap(\.value))
            if let missing = try CueRows.firstMissingMacro(db, in: actions) { throw CueStoreError.unknownMacro(missing) }
            let errors = SlideActionSet.validate(actions, library: macros)
            guard errors.isEmpty else { throw CueStoreError.invalidSlideActions(errors) }

            if actions.isEmpty {
                try db.execute(sql: "DELETE FROM cueSlideActions WHERE slideID = ?", arguments: [slideID.uuidString])
            } else {
                try db.execute(sql: """
                    INSERT INTO cueSlideActions (slideID, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?)
                    ON CONFLICT(slideID) DO UPDATE SET definition = excluded.definition, updatedAt = excluded.updatedAt
                    """, arguments: [slideID.uuidString, try CueCoding.encode(CueActionList(actions: actions)), stamp, stamp])
            }
        }
    }
}
