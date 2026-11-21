// CUE-002a (AUTO-12, storage half): scheduled events and what the engine remembers between runs.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

extension CueStore {
    /// Events in the order they were first saved (the engine runs events with the same time in this order).
    public func scheduledEvents() async throws -> [ScheduledEvent] {
        try await library.cueRead { db in
            try CueRows.require(db)
            return try CueRows.events(db).compactMap(\.value)
        }
    }

    /// Adds the event, or replaces the one with the same id in place. An event that cannot work (the engine's
    /// `validationIssues`: no name, no weekday, a bad time or zone, no actions) or that runs a macro that does not exist is
    /// refused. Returns what was stored: a new event, an event switched on, and an event whose time changed all restart
    /// from now (`activeFrom`), so a time earlier today does not fire at once.
    @discardableResult
    public func saveScheduledEvent(_ event: ScheduledEvent) async throws -> ScheduledEvent {
        let stamp = now()
        return try await library.cueWrite { db in
            try CueRows.require(db)
            let issues = event.validationIssues
            guard issues.isEmpty else { throw CueStoreError.invalidEvent(issues) }
            try Self.requireMacros(db, event.cueActions)
            if case .macro(let id) = event.payload, try !CueRows.macroExists(db, id) { throw CueStoreError.unknownMacro(id) }

            var stored = event
            if let old = try CueRows.events(db).first(where: { $0.id == event.id.uuidString }) {
                try old.requireWritable(.scheduledEvent, currentVersion: ScheduledEvent.currentVersion)
                if let was = old.value, (!was.isEnabled && event.isEnabled) || was.timing != event.timing {
                    stored.activeFrom = max(event.activeFrom, stamp)
                }
            } else if event.activeFrom == .distantPast {
                stored.activeFrom = stamp
            }
            try db.execute(sql: """
                INSERT INTO cueScheduledEvent (id, name, enabled, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, enabled = excluded.enabled,
                                              definition = excluded.definition, updatedAt = excluded.updatedAt
                """, arguments: [stored.id.uuidString, stored.name, stored.isEnabled, try CueCoding.encode(stored), stamp, stamp])
            return stored
        }
    }

    /// Switches an event on or off using the engine's own rule: switching on restarts it from now, so times that passed
    /// while it was off do not fire. Returns the stored event.
    @discardableResult
    public func setScheduledEvent(id: UUID, enabled: Bool) async throws -> ScheduledEvent {
        let stamp = now()
        return try await library.cueWrite { db in
            try CueRows.require(db)
            guard let record = try CueRows.events(db).first(where: { $0.id == id.uuidString }) else { throw CueStoreError.notFound }
            try record.requireWritable(.scheduledEvent, currentVersion: ScheduledEvent.currentVersion)
            guard let event = record.value else { throw CueStoreError.unreadable(record: .scheduledEvent, id: record.id) }
            var engine = ScheduleEngine(events: [event])
            engine.setEnabled(enabled, for: id, now: stamp)
            guard let changed = engine.events.first else { throw CueStoreError.notFound }
            if changed != event {
                try db.execute(sql: "UPDATE cueScheduledEvent SET enabled = ?, definition = ?, updatedAt = ? WHERE id = ?",
                               arguments: [changed.isEnabled, try CueCoding.encode(changed), stamp, id.uuidString])
            }
            return changed
        }
    }

    /// Deletes the event and its place in the remembered state, in one transaction.
    public func deleteScheduledEvent(id: UUID) async throws {
        let stamp = now()
        try await library.cueWrite { db in
            try CueRows.require(db)
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM cueScheduledEvent WHERE id = ?)", arguments: [id.uuidString]) == true
            else { throw CueStoreError.notFound }
            try db.execute(sql: "DELETE FROM cueScheduledEvent WHERE id = ?", arguments: [id.uuidString])
            if let raw = try String.fetchOne(db, sql: "SELECT state FROM cueScheduleState WHERE id = 1") {
                let record = CueRows.decode(ScheduleEngineState.self, id: "1", raw: raw)
                if record.isWritable(currentVersion: ScheduleEngineState.currentVersion), var state = record.value, state.lastHandled[id] != nil {
                    state.lastHandled[id] = nil
                    try Self.writeState(db, state, stamp: stamp)
                }
            }
        }
    }

    /// What the engine remembered when it was last saved; nil if never saved. Unpruned: see `loadLibrary()`.
    public func scheduleState() async throws -> ScheduleEngineState? {
        try await library.cueRead { db in
            try CueRows.require(db)
            guard let raw = try String.fetchOne(db, sql: "SELECT state FROM cueScheduleState WHERE id = 1") else { return nil }
            guard let state = CueRows.decode(ScheduleEngineState.self, id: "1", raw: raw).value
            else { throw CueStoreError.unreadable(record: .scheduleState, id: "1") }
            return state
        }
    }

    /// Replaces the remembered state: the grace period, the last occurrence handled per event, and the latest check, in one
    /// row and one statement. Call it after each check that fired or skipped something, and on quit.
    public func saveScheduleState(_ state: ScheduleEngineState) async throws {
        let stamp = now()
        try await library.cueWrite { db in
            try CueRows.require(db)
            if let raw = try String.fetchOne(db, sql: "SELECT state FROM cueScheduleState WHERE id = 1") {
                try CueRows.decode(ScheduleEngineState.self, id: "1", raw: raw)
                    .requireWritable(.scheduleState, currentVersion: ScheduleEngineState.currentVersion)
            }
            try Self.writeState(db, state, stamp: stamp)
        }
    }

    // MARK: Helpers

    static func writeState(_ db: Database, _ state: ScheduleEngineState, stamp: Date) throws {
        try db.execute(sql: """
            INSERT INTO cueScheduleState (id, state, lastCheckedAt, updatedAt) VALUES (1, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET state = excluded.state, lastCheckedAt = excluded.lastCheckedAt, updatedAt = excluded.updatedAt
            """, arguments: [try CueCoding.encode(state), state.lastCheckedAt, stamp])
    }

    static func requireMacros(_ db: Database, _ actions: [CueAction]) throws {
        if let missing = try CueRows.firstMissingMacro(db, in: actions) { throw CueStoreError.unknownMacro(missing) }
    }
}
