// SYS-015: the store methods for the fields migration v15 added (see `Schema`, "v15"). Slide-object name, hidden and locked flags live in the slide's
// objects JSON; the media marks are two columns of `mediaAsset`; markers are rows of `mediaMarker`; a screen's key note, signal chain and Look live in
// the profile's `extra` JSON. Every method validates before it writes and changes nothing when it throws.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    // MARK: Slide objects (name, hidden, locked)

    /// Sets (or, with nil or blank, clears) the name of one object on a slide. Returns the slide as stored. `notFound` for an unknown slide or object.
    @discardableResult
    public func setSlideObjectName(_ name: String?, objectID: UUID, inSlide slideID: UUID) async throws -> Slide {
        try await updateObject(objectID, inSlide: slideID) { $0.name = name }
    }

    /// A hidden object stays on the slide and is not drawn on any screen.
    @discardableResult
    public func setSlideObjectHidden(_ hidden: Bool, objectID: UUID, inSlide slideID: UUID) async throws -> Slide {
        try await updateObject(objectID, inSlide: slideID) { $0.isHidden = hidden }
    }

    /// A locked object is still drawn; that the editor does not move or edit it is the feature slice's work.
    @discardableResult
    public func setSlideObjectLocked(_ locked: Bool, objectID: UUID, inSlide slideID: UUID) async throws -> Slide {
        try await updateObject(objectID, inSlide: slideID) { $0.isLocked = locked }
    }

    private func updateObject(_ objectID: UUID, inSlide slideID: UUID, _ change: @escaping @Sendable (inout SlideObject) -> Void) async throws -> Slide {
        let backend = searchBackend
        let store = self
        return try await writer.write { db in
            guard let record = try SlideRecord.fetchOne(db, sql: "SELECT * FROM slide WHERE id = ?", arguments: [slideID.dbText]) else { throw StoreError.notFound }
            var slide = store.runtimeSlide(record.domain)
            guard let index = slide.content.objects.firstIndex(where: { $0.id == objectID }) else { throw StoreError.notFound }
            change(&slide.content.objects[index])
            try db.execute(sql: "UPDATE slide SET objects = ?, updatedAt = ? WHERE id = ?",
                           arguments: [SlideObjectsJSON.encode(store.storedObjects(slide.content.objects)), Date(), slideID.dbText])
            try Self.touch(db, presentationID: record.presentationID, backend: backend)
            return slide
        }
    }

    // MARK: Media marks

    /// Sets the clip's mark in and mark out together, in seconds; nil is the start or the end of the clip. Each given mark is a real time from 0 to the clip's
    /// length (to `MediaClock.longest` when the length is not known), and the in mark is not after the out mark; otherwise `invalidValue` and nothing changes.
    /// Only a video or an audio clip has marks (`invalidValue` for a picture). Returns the asset as stored.
    @discardableResult
    public func setMediaMarks(markIn: Double?, markOut: Double?, forAsset id: UUID) async throws -> MediaAsset {
        let store = self
        return try await writer.write { db in
            guard let kindText = try String.fetchOne(db, sql: "SELECT kind FROM mediaAsset WHERE id = ?", arguments: [id.dbText]) else { throw StoreError.notFound }
            if markIn != nil || markOut != nil {
                guard MediaKind(rawValue: kindText) != .image else { throw StoreError.invalidValue }
                let length = try Double.fetchOne(db, sql: "SELECT duration FROM mediaAsset WHERE id = ?", arguments: [id.dbText])
                guard MediaMarks.isValid(markIn: markIn, markOut: markOut, length: length) else { throw StoreError.invalidValue }
            }
            try db.execute(sql: "UPDATE mediaAsset SET markIn = ?, markOut = ? WHERE id = ?", arguments: [markIn, markOut, id.dbText])
            return try store.assetRow(db, id: id)
        }
    }

    /// Clears both marks: the whole clip plays.
    @discardableResult
    public func clearMediaMarks(forAsset id: UUID) async throws -> MediaAsset {
        try await setMediaMarks(markIn: nil, markOut: nil, forAsset: id)
    }

    private func assetRow(_ db: Database, id: UUID) throws -> MediaAsset {
        guard let asset = try Self.mediaAssetRows(db, sql: "SELECT * FROM mediaAsset WHERE id = ?", arguments: [id.dbText]).first else { throw StoreError.notFound }
        return runtimeAsset(asset)
    }

    // MARK: Media markers

    /// The clip's markers by time, and for the same time by the order they were added. `notFound` for an unknown asset.
    public func mediaMarkers(forAsset assetID: UUID) async throws -> [MediaMarker] {
        try await writer.read { db in
            try Self.requireExists(db, table: "mediaAsset", id: assetID)
            return try Self.markerRows(db, assetID: assetID)
        }
    }

    /// Adds a marker at `time` seconds (a real time from 0 to the clip's length), with an optional name and the actions it runs (`MediaMarker.emptyActions`
    /// runs nothing). A clip keeps at most `MediaMarker.maxPerAsset`. `invalidValue` for a time or actions that are not real or a full clip.
    @discardableResult
    public func addMediaMarker(forAsset assetID: UUID, time: Double, name: String? = nil, actions: String = MediaMarker.emptyActions) async throws -> MediaMarker {
        try await writer.write { db in
            guard let length = try Self.assetLength(db, id: assetID) else { throw StoreError.notFound }
            guard MediaMarks.isValidTime(time, length: length.value), let stored = MediaMarker.validatedActions(actions) else { throw StoreError.invalidValue }
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM mediaMarker WHERE assetID = ?", arguments: [assetID.dbText]) ?? 0
            guard count < MediaMarker.maxPerAsset else { throw StoreError.invalidValue }
            let next = (try Int.fetchOne(db, sql: "SELECT MAX(sortOrder) FROM mediaMarker WHERE assetID = ?", arguments: [assetID.dbText]) ?? -1) + 1
            let marker = MediaMarker(assetID: assetID, time: time, name: MediaMarker.cleanName(name), actions: stored, sortOrder: next)
            try db.execute(sql: """
                INSERT INTO mediaMarker (id, assetID, time, name, actions, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [marker.id.dbText, assetID.dbText, time, marker.name, stored, next, marker.createdAt, marker.updatedAt])
            return try Self.marker(db, id: marker.id)
        }
    }

    @discardableResult
    public func moveMediaMarker(id: UUID, to time: Double) async throws -> MediaMarker {
        try await writer.write { db in
            let existing = try Self.marker(db, id: id)
            guard let length = try Self.assetLength(db, id: existing.assetID), MediaMarks.isValidTime(time, length: length.value) else { throw StoreError.invalidValue }
            try db.execute(sql: "UPDATE mediaMarker SET time = ?, updatedAt = ? WHERE id = ?", arguments: [time, Date(), id.dbText])
            return try Self.marker(db, id: id)
        }
    }

    /// Nil or blank clears the name.
    @discardableResult
    public func renameMediaMarker(id: UUID, to name: String?) async throws -> MediaMarker {
        try await writer.write { db in
            _ = try Self.marker(db, id: id)
            try db.execute(sql: "UPDATE mediaMarker SET name = ?, updatedAt = ? WHERE id = ?", arguments: [MediaMarker.cleanName(name), Date(), id.dbText])
            return try Self.marker(db, id: id)
        }
    }

    @discardableResult
    public func setMediaMarkerActions(id: UUID, actions: String) async throws -> MediaMarker {
        try await writer.write { db in
            _ = try Self.marker(db, id: id)
            guard let stored = MediaMarker.validatedActions(actions) else { throw StoreError.invalidValue }
            try db.execute(sql: "UPDATE mediaMarker SET actions = ?, updatedAt = ? WHERE id = ?", arguments: [stored, Date(), id.dbText])
            return try Self.marker(db, id: id)
        }
    }

    public func deleteMediaMarker(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "mediaMarker", id: id)
            try db.execute(sql: "DELETE FROM mediaMarker WHERE id = ?", arguments: [id.dbText])
        }
    }

    private static func assetLength(_ db: Database, id: UUID) throws -> (value: Double?, kind: String)? {
        guard let row = try Row.fetchOne(db, sql: "SELECT duration, kind FROM mediaAsset WHERE id = ?", arguments: [id.dbText]) else { return nil }
        return (row["duration"], row["kind"])
    }

    private static func marker(_ db: Database, id: UUID) throws -> MediaMarker {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM mediaMarker WHERE id = ?", arguments: [id.dbText]) else { throw StoreError.notFound }
        return try markerFrom(row)
    }

    static func markerRows(_ db: Database, assetID: UUID) throws -> [MediaMarker] {
        try Row.fetchAll(db, sql: "SELECT * FROM mediaMarker WHERE assetID = ? ORDER BY time, sortOrder, rowid", arguments: [assetID.dbText]).map(markerFrom)
    }

    private static func markerFrom(_ row: Row) throws -> MediaMarker {
        guard let id = UUID(uuidString: row["id"] as String), let asset = UUID(uuidString: row["assetID"] as String) else { throw SettingsJSON.corrupt("marker id") }
        return MediaMarker(id: id, assetID: asset, time: row["time"], name: row["name"], actions: row["actions"], sortOrder: row["sortOrder"],
                           createdAt: row["createdAt"], updatedAt: row["updatedAt"])
    }

    // MARK: Screens

    /// Sets the note about where the KEY of the primary destination (`mirror == nil`) or of a mirror goes. Blank clears it. `notFound` for an unknown screen.
    public func setScreenKeyNote(_ text: String, mirror: Int?, forScreen id: UUID) async throws {
        try await changeScreen(id) { $0.setConnectedKeyNote(text, mirror: mirror) }
    }

    /// Sets the operator-typed signal chain of the primary destination or a mirror (at most `ScreenProfile.maxChainLength` boxes). An empty chain clears it.
    public func setScreenSignalChain(_ chain: [ChainNode], mirror: Int?, forScreen id: UUID) async throws {
        try await changeScreen(id) { $0.setSignalChain(chain, mirror: mirror) }
    }

    /// Sets (nil clears) the Look the screen follows on its own. `invalidReference` when no such Look is stored. Deleting a Look clears it from every screen.
    public func setScreenLook(_ lookID: UUID?, forScreen id: UUID) async throws {
        try await writer.write { db in
            if let lookID, !(try Self.exists(db, table: "look", id: lookID)) { throw StoreError.invalidReference }
            try Self.changeScreen(db, id) { $0.screenLookID = lookID }
        }
    }

    private func changeScreen(_ id: UUID, _ change: @escaping @Sendable (inout ScreenProfile) -> Void) async throws {
        try await writer.write { db in try Self.changeScreen(db, id, change) }
    }

    private static func changeScreen(_ db: Database, _ id: UUID, _ change: (inout ScreenProfile) -> Void) throws {
        var profiles = try screenProfiles(db)
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw StoreError.notFound }
        change(&profiles[index])
        try writeScreenProfiles(db, profiles)
    }
}
