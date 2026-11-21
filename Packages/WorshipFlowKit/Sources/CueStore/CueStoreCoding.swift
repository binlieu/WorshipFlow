// CUE-002a: JSON text in, JSON text out, and the checks every write makes before it replaces a stored row.
import Foundation
import GRDB
import CueEngine
@_spi(CueStore) import Persistence

enum CueCoding {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func version(of text: String) -> Int? { CueStorage.version(in: Data(text.utf8)) }
}

/// A stored row, decoded as far as possible.
struct StoredRecord<T: Sendable>: Sendable {
    var id: String
    var raw: String
    var value: T?
    /// The decoder's complaint when `value` is nil.
    var failure: String?
    var version: Int?

    /// A row may be replaced only when it was read and was not written by a newer format.
    func requireWritable(_ kind: CueRecordKind, currentVersion: Int) throws {
        guard value != nil else { throw CueStoreError.unreadable(record: kind, id: id) }
        if let version, version > currentVersion { throw CueStoreError.storedByNewerVersion(record: kind, id: id, version: version) }
    }

    func isWritable(currentVersion: Int) -> Bool {
        value != nil && (version ?? 1) <= currentVersion
    }
}

enum CueRows {
    static func require(_ db: Database) throws {
        guard try db.tableExists("cueMacro"), try db.tableExists("cueScheduleState") else { throw CueStoreError.libraryNeedsUpdate }
    }

    static func decode<T: Decodable & Sendable>(_ type: T.Type, id: String, raw: String) -> StoredRecord<T> {
        do {
            let value = try JSONDecoder().decode(T.self, from: Data(raw.utf8))
            return StoredRecord(id: id, raw: raw, value: value, failure: nil, version: CueCoding.version(of: raw))
        } catch {
            return StoredRecord(id: id, raw: raw, value: nil, failure: describe(error), version: CueCoding.version(of: raw))
        }
    }

    /// A short reason without the file's own text.
    static func describe(_ error: Error) -> String {
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted: return "not valid JSON or a wrong value"
            case .keyNotFound(let key, _): return "missing \u{201C}\(key.stringValue)\u{201D}"
            case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx): return "wrong type at \(ctx.codingPath.map(\.stringValue).joined(separator: "."))"
            @unknown default: return "unreadable"
            }
        }
        return "unreadable"
    }

    static func macros(_ db: Database) throws -> [StoredRecord<Macro>] {
        try Row.fetchAll(db, sql: "SELECT id, definition FROM cueMacro ORDER BY sortOrder, rowid").map {
            decode(Macro.self, id: $0["id"], raw: $0["definition"])
        }
    }

    static func events(_ db: Database) throws -> [StoredRecord<ScheduledEvent>] {
        try Row.fetchAll(db, sql: "SELECT id, definition FROM cueScheduledEvent ORDER BY rowid").map {
            decode(ScheduledEvent.self, id: $0["id"], raw: $0["definition"])
        }
    }

    static func bindings(_ db: Database) throws -> [StoredRecord<MIDIBinding>] {
        try Row.fetchAll(db, sql: "SELECT id, definition FROM cueMIDIBinding ORDER BY sortOrder, rowid").map {
            decode(MIDIBinding.self, id: $0["id"], raw: $0["definition"])
        }
    }

    /// In slide order is not needed; the table's own order keeps this stable.
    static func slideActions(_ db: Database) throws -> [StoredRecord<CueActionList>] {
        try Row.fetchAll(db, sql: "SELECT slideID, definition FROM cueSlideActions ORDER BY rowid").map {
            decode(CueActionList.self, id: $0["slideID"], raw: $0["definition"])
        }
    }

    static func slideActionSet(_ records: [StoredRecord<CueActionList>]) -> SlideActionSet {
        var map: [UUID: [CueAction]] = [:]
        for r in records {
            if let id = UUID(uuidString: r.id), let list = r.value { map[id] = list.actions }
        }
        return SlideActionSet(unvalidated: map)
    }

    static func macroExists(_ db: Database, _ id: UUID) throws -> Bool {
        try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM cueMacro WHERE id = ?)", arguments: [id.uuidString]) ?? false
    }

    /// The first macro id in `actions` that is not in the library.
    static func firstMissingMacro(_ db: Database, in actions: [CueAction]) throws -> UUID? {
        for case .runMacro(let id) in actions where try !macroExists(db, id) { return id }
        return nil
    }

    /// Moves the given rows to the front in the given order; the rest keep their relative order after them. `table` is a fixed name.
    static func reorder(_ db: Database, table: String, ids: [UUID]) throws {
        guard Set(ids).count == ids.count else { throw CueStoreError.invalidOrder }
        let existing = try String.fetchAll(db, sql: "SELECT id FROM \(table) ORDER BY sortOrder, rowid")
        let given = ids.map(\.uuidString)
        guard given.allSatisfy(existing.contains) else { throw CueStoreError.notFound }
        let order = given + existing.filter { !given.contains($0) }
        for (index, id) in order.enumerated() {
            try db.execute(sql: "UPDATE \(table) SET sortOrder = ? WHERE id = ? AND sortOrder <> ?", arguments: [index, id, index])
        }
    }

    /// Closes gaps after a delete. `table` is a fixed name.
    static func renumber(_ db: Database, table: String) throws {
        let ids = try String.fetchAll(db, sql: "SELECT id FROM \(table) ORDER BY sortOrder, rowid")
        for (index, id) in ids.enumerated() {
            try db.execute(sql: "UPDATE \(table) SET sortOrder = ? WHERE id = ? AND sortOrder <> ?", arguments: [index, id, index])
        }
    }
}
