// SYS-002: themes, Looks, props, screen profiles and media assets (schema v3, KI-016).
//
// Structured values are stored as JSON text with a fixed encoding (`SettingsJSON`): sorted keys, no escaped
// slashes, UUIDs as upper-case strings. Rows are upserted with ON CONFLICT so a row keeps its rowid (and so its
// creation order) when it is edited.
import Foundation
import GRDB
import Domain

/// What a screen profile stores beyond the v3 columns (schema v6). Nil in the column when a profile has none of it.
struct ScreenProfileExtras: Codable {
    /// Set only when the primary destination is SDI.
    var destination: OutputDestination?
    var mirrors: [OutputDestination]
    var videoMode: VideoModeDescription
    /// UI-002: the typed "connected to" notes. Absent in rows written before.
    var connectedTo: [String]?

    init?(_ profile: ScreenProfile) {
        let sdi = profile.destination.isSDI ? profile.destination : nil
        guard sdi != nil || !profile.mirrors.isEmpty || profile.videoMode != .standard || !profile.connectedTo.isEmpty else { return nil }
        connectedTo = profile.connectedTo.isEmpty ? nil : profile.connectedTo
        destination = sdi
        mirrors = profile.mirrors
        videoMode = profile.videoMode
    }
}

enum SettingsJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    /// One screen's Look settings. `visibleLayers` is a sorted array, because a Set would encode in random order.
    struct StoredScreenLook: Codable {
        var themeID: String?
        var visibleLayers: [String]
    }

    /// `{"<SCREEN UUID>": {"themeID": "<UUID>", "visibleLayers": ["props", "slide"]}}`; `themeID` is omitted when nil.
    static func encodeScreens(_ screens: [UUID: ScreenLook]) throws -> String {
        var stored: [String: StoredScreenLook] = [:]
        for (id, look) in screens {
            stored[id.dbText] = StoredScreenLook(themeID: look.themeID?.dbText,
                                                 visibleLayers: look.visibleLayers.map(\.rawValue).sorted())
        }
        return try encode(stored)
    }

    static func decodeScreens(_ text: String) throws -> [UUID: ScreenLook] {
        let stored = try decode([String: StoredScreenLook].self, from: text)
        var screens: [UUID: ScreenLook] = [:]
        for (key, value) in stored {
            guard let id = UUID(uuidString: key) else { throw corrupt("Look screen key \(key)") }
            var themeID: UUID?
            if let raw = value.themeID {
                guard let parsed = UUID(uuidString: raw) else { throw corrupt("Look theme id \(raw)") }
                themeID = parsed
            }
            var layers = Set<LayerKind>()
            for name in value.visibleLayers {
                guard let layer = LayerKind(rawValue: name) else { throw corrupt("Look layer \(name)") }
                layers.insert(layer)
            }
            screens[id] = ScreenLook(themeID: themeID, visibleLayers: layers)
        }
        return screens
    }

    static func corrupt(_ what: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: [], debugDescription: "Invalid stored value: \(what)"))
    }
}

private let builtInThemeIDs: Set<UUID> = Set(Theme.builtIn.map(\.id))

extension LibraryStore {
    // MARK: Themes (PRES-06)

    /// Custom themes only, by folded name. Built-in themes live in code (`Theme.builtIn`).
    public func themes() async throws -> [Theme] {
        let store = self
        return try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT definition FROM theme ORDER BY nameFolded, rowid")
                .map { store.runtimeTheme(try SettingsJSON.decode(Theme.self, from: $0)) }
        }
    }

    /// Inserts or updates a custom theme by id. Built-in ids throw `invalidReference`; a blank name throws `invalidName`.
    public func saveTheme(_ theme: Theme) async throws {
        guard !builtInThemeIDs.contains(theme.id) else { throw StoreError.invalidReference }
        var theme = storedTheme(theme)
        theme.name = try Self.validName(theme.name)
        let definition = try SettingsJSON.encode(theme)
        let folded = SearchFolding.fold(theme.name)
        let (id, name) = (theme.id.dbText, theme.name)
        try await writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO theme (id, name, nameFolded, definition, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, nameFolded = excluded.nameFolded,
                    definition = excluded.definition, updatedAt = excluded.updatedAt
                """, arguments: [id, name, folded, definition, now, now])
        }
    }

    /// Deletes a custom theme and clears `presentation.themeID` where it pointed at it, in one transaction.
    /// Built-in ids throw `invalidReference`; an unknown id throws `notFound`.
    public func deleteTheme(id: UUID) async throws {
        guard !builtInThemeIDs.contains(id) else { throw StoreError.invalidReference }
        try await writer.write { db in
            try Self.requireExists(db, table: "theme", id: id)
            try db.execute(sql: "UPDATE presentation SET themeID = NULL WHERE themeID = ?", arguments: [id.dbText])
            try db.execute(sql: "DELETE FROM theme WHERE id = ?", arguments: [id.dbText])
        }
    }

    /// Sets a presentation's theme: nil, a built-in id, or a stored theme id (else `invalidReference`).
    public func setTheme(_ themeID: UUID?, forPresentation presentationID: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "presentation", id: presentationID)
            if let themeID, !builtInThemeIDs.contains(themeID) {
                guard try Self.exists(db, table: "theme", id: themeID) else { throw StoreError.invalidReference }
            }
            try db.execute(sql: "UPDATE presentation SET themeID = ? WHERE id = ?",
                           arguments: [themeID?.dbText, presentationID.dbText])
        }
    }

    // MARK: Looks (SCRN-08)

    /// In creation order.
    public func looks() async throws -> [Look] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, screens FROM look ORDER BY createdAt, rowid").map { row in
                guard let id = UUID(uuidString: row["id"] as String) else { throw SettingsJSON.corrupt("look id") }
                return Look(id: id, name: row["name"], screens: try SettingsJSON.decodeScreens(row["screens"]))
            }
        }
    }

    public func saveLook(_ look: Look) async throws {
        let name = try Self.validName(look.name)
        let screens = try SettingsJSON.encodeScreens(look.screens)
        let id = look.id.dbText
        try await writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO look (id, name, screens, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, screens = excluded.screens, updatedAt = excluded.updatedAt
                """, arguments: [id, name, screens, now, now])
        }
    }

    public func deleteLook(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "look", id: id)
            try db.execute(sql: "DELETE FROM look WHERE id = ?", arguments: [id.dbText])
        }
    }

    // MARK: Props (MEDIA-08)

    /// In creation order.
    public func props() async throws -> [Prop] {
        let store = self
        return try await writer.read { db in
            let v12 = try db.columns(in: "prop").contains { $0.name == "targets" }
            return try Row.fetchAll(db, sql: """
                SELECT id, name, imagePath, frame, opacity, isOn, \(v12 ? "targets, kind, text" : "NULL AS targets, NULL AS kind, NULL AS text")
                FROM prop ORDER BY createdAt, rowid
                """).map { row in
                guard let id = UUID(uuidString: row["id"] as String) else { throw SettingsJSON.corrupt("prop id") }
                // A damaged value reads as the old behaviour (every role, a picture), never as a prop that vanishes.
                let targets = (row["targets"] as String?).flatMap { try? SettingsJSON.decode(Set<ScreenRole>.self, from: $0) } ?? Set(ScreenRole.allCases)
                let kind = (row["kind"] as String?).flatMap(PropKind.init(rawValue:)) ?? .image
                let text = (row["text"] as String?).flatMap { try? SettingsJSON.decode(TextPropSpec.self, from: $0) }
                return Prop(id: id, name: row["name"], imagePath: store.runtimePath(row["imagePath"]),
                            frame: try SettingsJSON.decode(NormalizedRect.self, from: row["frame"]),
                            opacity: row["opacity"], isOn: row["isOn"], targets: targets, kind: kind, text: text)
            }
        }
    }

    /// Inserts or updates a prop. A nil `bookmark` keeps the stored one.
    public func saveProp(_ prop: Prop, bookmark: Data?) async throws {
        let frame = try SettingsJSON.encode(prop.frame)
        let imagePath = storedPath(prop.imagePath)
        let targets = try SettingsJSON.encode(prop.targets)
        let text = try prop.text.map { try SettingsJSON.encode($0) }
        try await writer.write { db in
            let now = Date()
            try db.execute(sql: """
                INSERT INTO prop (id, name, imagePath, bookmark, frame, opacity, isOn, createdAt, updatedAt, targets, kind, text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, imagePath = excluded.imagePath,
                    bookmark = COALESCE(excluded.bookmark, prop.bookmark), frame = excluded.frame,
                    opacity = excluded.opacity, isOn = excluded.isOn, updatedAt = excluded.updatedAt,
                    targets = excluded.targets, kind = excluded.kind, text = excluded.text
                """, arguments: [prop.id.dbText, prop.name, imagePath, bookmark, frame, prop.opacity, prop.isOn, now, now,
                                  targets, prop.kind.rawValue, text])
        }
    }

    public func bookmark(forProp id: UUID) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(db, sql: "SELECT bookmark FROM prop WHERE id = ?", arguments: [id.dbText])
        }
    }

    public func deleteProp(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "prop", id: id)
            try db.execute(sql: "DELETE FROM prop WHERE id = ?", arguments: [id.dbText])
        }
    }

    // MARK: Screen profiles (OUT-002)

    public func screenProfiles() async throws -> [ScreenProfile] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM screenProfile ORDER BY sortOrder, rowid").map { row in
                guard let id = UUID(uuidString: row["id"] as String) else { throw SettingsJSON.corrupt("screen id") }
                guard let role = ScreenRole(rawValue: row["role"]) else { throw SettingsJSON.corrupt("screen role") }
                let extras: ScreenProfileExtras? = try (row["extra"] as String?).map { try SettingsJSON.decode(ScreenProfileExtras.self, from: $0) }
                let destination: OutputDestination
                switch row["destination"] as String {
                case "sdi":
                    guard let sdi = extras?.destination else { throw SettingsJSON.corrupt("screen sdi destination") }
                    destination = sdi
                case "window": destination = .window
                case "display":
                    guard let display = row["displayID"] as Int64?, let value = UInt32(exactly: display) else {
                        throw SettingsJSON.corrupt("screen display id")
                    }
                    destination = .display(value)
                default: throw SettingsJSON.corrupt("screen destination")
                }
                return ScreenProfile(id: id, name: row["name"], role: role, destination: destination, isEnabled: row["isEnabled"],
                                     mirrors: extras?.mirrors ?? [], videoMode: extras?.videoMode ?? .standard,
                                     connectedTo: extras?.connectedTo ?? [])
            }
        }
    }

    /// Replaces the whole ordered set in one transaction. Duplicate ids throw `invalidReference`.
    public func saveScreenProfiles(_ profiles: [ScreenProfile]) async throws {
        guard Set(profiles.map(\.id)).count == profiles.count else { throw StoreError.invalidReference }
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM screenProfile")
            for (index, profile) in profiles.enumerated() {
                let kind: String
                var display: Int64?
                switch profile.destination {
                case .window: kind = "window"
                case .display(let id): kind = "display"; display = Int64(id)
                case .sdi: kind = "sdi"
                }
                let extras = ScreenProfileExtras(profile)
                let extra: String? = try extras.map { try SettingsJSON.encode($0) }
                try db.execute(sql: """
                    INSERT INTO screenProfile (id, sortOrder, name, role, destination, displayID, isEnabled, extra)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [profile.id.dbText, index, profile.name, profile.role.rawValue, kind, display, profile.isEnabled, extra])
            }
        }
    }

    // MARK: Media assets (MEDIA-01)

    /// Adds a reference to a media file. The same path returns the existing asset unchanged.
    public func addMediaAsset(name: String, kind: MediaKind, path: String, bookmark: Data?, duration: Double?,
                              pixelWidth: Int?, pixelHeight: Int?) async throws -> MediaAsset {
        let name = try Self.validName(name)
        let store = self
        let path = storedPath(path)
        return try await writer.write { db in
            if let existing = try Self.mediaAssetRow(db, sql: "SELECT * FROM mediaAsset WHERE path = ?", arguments: [path]).first {
                return store.runtimeAsset(existing)
            }
            let id = UUID()
            try db.execute(sql: """
                INSERT INTO mediaAsset (id, name, kind, path, bookmark, duration, pixelWidth, pixelHeight, addedAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [id.dbText, name, kind.rawValue, path, bookmark, duration, pixelWidth, pixelHeight, Date()])
            // Re-read so the returned value is exactly what the store holds (dates are stored to the millisecond).
            guard let stored = try Self.mediaAssetRow(db, sql: "SELECT * FROM mediaAsset WHERE id = ?", arguments: [id.dbText]).first else {
                throw StoreError.notFound
            }
            return store.runtimeAsset(stored)
        }
    }

    /// In the order added; `nil` means every kind.
    public func mediaAssets(kind: MediaKind?) async throws -> [MediaAsset] {
        let store = self
        return try await writer.read { db in
            if let kind {
                return try Self.mediaAssetRow(db, sql: "SELECT * FROM mediaAsset WHERE kind = ? ORDER BY addedAt, rowid",
                                              arguments: [kind.rawValue]).map { store.runtimeAsset($0) }
            }
            return try Self.mediaAssetRow(db, sql: "SELECT * FROM mediaAsset ORDER BY addedAt, rowid", arguments: [])
                .map { store.runtimeAsset($0) }
        }
    }

    public func renameMediaAsset(id: UUID, to name: String) async throws {
        let name = try Self.validName(name)
        try await writer.write { db in
            try Self.requireExists(db, table: "mediaAsset", id: id)
            try db.execute(sql: "UPDATE mediaAsset SET name = ? WHERE id = ?", arguments: [name, id.dbText])
        }
    }

    /// Removes the reference only. The file on disk is never touched.
    public func removeMediaAsset(id: UUID) async throws {
        try await writer.write { db in
            try Self.requireExists(db, table: "mediaAsset", id: id)
            try db.execute(sql: "DELETE FROM mediaAsset WHERE id = ?", arguments: [id.dbText])
        }
    }

    private static func mediaAssetRow(_ db: Database, sql: String, arguments: StatementArguments) throws -> [MediaAsset] {
        try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
            guard let id = UUID(uuidString: row["id"] as String) else { throw SettingsJSON.corrupt("media id") }
            guard let kind = MediaKind(rawValue: row["kind"]) else { throw SettingsJSON.corrupt("media kind") }
            return MediaAsset(id: id, name: row["name"], kind: kind, path: row["path"], bookmark: row["bookmark"],
                              duration: row["duration"], pixelWidth: row["pixelWidth"], pixelHeight: row["pixelHeight"],
                              addedAt: row["addedAt"])
        }
    }
}
