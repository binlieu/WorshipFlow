// LIB-005: the program package format. A package is a folder named `<name>.worshipflowprogram` that holds `program.json` and a
// `media/` folder. Everything in `program.json` that names a file names it by a path relative to the package, never by an
// absolute path, a bookmark, a user name or a volume name. Field by field description: docs/features/LIB-005-program-export-import.md.
// Foundation and Domain only.
import Foundation
import Domain

public enum ProgramFormat {
    /// The value of `program.json`'s `format`.
    public static let name = "worshipflow-program"
    /// The newest format this build writes and reads. A package with a larger number is refused.
    public static let version = 1
    public static let fileExtension = "worshipflowprogram"
    public static let manifestName = "program.json"
    public static let mediaFolder = "media"
    /// `program.json` larger than this is refused (a program with hundreds of songs is a few megabytes).
    public static let maxManifestBytes = 32 * 1024 * 1024
    /// More media files than this is refused.
    public static let maxMediaFiles = 20_000
}

/// Any JSON value. Used for slide actions, so a package keeps the actions exactly as the cue editor wrote them, also those
/// this build does not understand.
public indirect enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Replaces every string value that is the text of a key in `map` (UUIDs compared ignoring case); the replacement is
    /// written in the same case as the original.
    func replacingUUIDs(_ map: [UUID: UUID]) -> JSONValue {
        switch self {
        case .string(let s):
            guard let id = UUID(uuidString: s), let new = map[id] else { return self }
            return .string(s == s.lowercased() ? new.uuidString.lowercased() : new.uuidString)
        case .array(let a): return .array(a.map { $0.replacingUUIDs(map) })
        case .object(let o): return .object(o.mapValues { $0.replacingUUIDs(map) })
        default: return self
        }
    }

    static func parse(_ text: String) -> JSONValue? { try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    /// Compact JSON with sorted keys, for storing in a column.
    var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: (try? encoder.encode(self)) ?? Data("null".utf8), as: UTF8.self)
    }
}

/// The contents of `program.json`. Unknown fields are ignored when reading, so a later build may add fields (a per-slide
/// background, for example) without older readers failing.
public struct ProgramDocument: Codable, Equatable, Sendable {
    public var format: String
    public var formatVersion: Int
    /// The app version that wrote the package.
    public var appVersion: String
    /// The id of the exported playlist. Imported media is kept under `Media/Imported/<programID>/`.
    public var programID: UUID
    public var playlist: PlaylistEntry
    public var items: [ItemEntry]
    public var presentations: [PresentationEntry]
    public var themes: [Theme]
    public var looks: [LookEntry]
    public var mediaAssets: [AssetEntry]
    public var media: [MediaEntry]

    public init(format: String = ProgramFormat.name, formatVersion: Int = ProgramFormat.version, appVersion: String,
                programID: UUID, playlist: PlaylistEntry, items: [ItemEntry], presentations: [PresentationEntry],
                themes: [Theme], looks: [LookEntry], mediaAssets: [AssetEntry], media: [MediaEntry]) {
        self.format = format
        self.formatVersion = formatVersion
        self.appVersion = appVersion
        self.programID = programID
        self.playlist = playlist
        self.items = items
        self.presentations = presentations
        self.themes = themes
        self.looks = looks
        self.mediaAssets = mediaAssets
        self.media = media
    }

    public struct PlaylistEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public init(id: UUID, name: String) { self.id = id; self.name = name }
    }

    /// One row of the playlist, in order. `kind` is `presentation`, `header`, `countdown` or `scripture`.
    public struct ItemEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var kind: String
        /// A header's label.
        public var label: String?
        public var countdown: CountdownSpec?
        /// A scripture item: the reference and translation codes. Never the words.
        public var scripture: ScriptureItemSpec?
        public var presentationID: UUID?
        public var arrangementID: UUID?

        public init(id: UUID, kind: String, label: String? = nil, countdown: CountdownSpec? = nil, scripture: ScriptureItemSpec? = nil,
                    presentationID: UUID? = nil, arrangementID: UUID? = nil) {
            self.id = id
            self.kind = kind
            self.label = label
            self.countdown = countdown
            self.scripture = scripture
            self.presentationID = presentationID
            self.arrangementID = arrangementID
        }
    }

    public struct PresentationEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var title: String
        public var kind: PresentationKind
        public var themeID: UUID?
        public var slides: [SlideEntry]
        public var groups: [GroupEntry]
        public var arrangements: [ArrangementEntry]

        public init(id: UUID, title: String, kind: PresentationKind, themeID: UUID?, slides: [SlideEntry],
                    groups: [GroupEntry], arrangements: [ArrangementEntry]) {
            self.id = id
            self.title = title
            self.kind = kind
            self.themeID = themeID
            self.slides = slides
            self.groups = groups
            self.arrangements = arrangements
        }
    }

    public struct SlideEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var primary: String
        public var secondary: String?
        public var notes: String
        public var groupID: UUID?
        /// Text boxes, shapes and images, back to front. An image's `path` is a package path (`media/...`).
        public var objects: [SlideObject]
        /// The slide's actions as the cue editor stored them (`{"version":1,"actions":[...]}`), or nil for none.
        public var actions: JSONValue?

        public init(id: UUID, primary: String, secondary: String?, notes: String, groupID: UUID?, objects: [SlideObject],
                    actions: JSONValue?) {
            self.id = id
            self.primary = primary
            self.secondary = secondary
            self.notes = notes
            self.groupID = groupID
            self.objects = objects
            self.actions = actions
        }

        private enum CodingKeys: String, CodingKey { case id, primary, secondary, notes, groupID, objects, actions }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            primary = try c.decode(String.self, forKey: .primary)
            secondary = try c.decodeIfPresent(String.self, forKey: .secondary)
            notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
            groupID = try c.decodeIfPresent(UUID.self, forKey: .groupID)
            objects = try c.decodeIfPresent([SlideObject].self, forKey: .objects) ?? []
            actions = try c.decodeIfPresent(JSONValue.self, forKey: .actions)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(primary, forKey: .primary)
            try c.encodeIfPresent(secondary, forKey: .secondary)
            try c.encode(notes, forKey: .notes)
            try c.encodeIfPresent(groupID, forKey: .groupID)
            if !objects.isEmpty { try c.encode(objects, forKey: .objects) }
            try c.encodeIfPresent(actions, forKey: .actions)
        }
    }

    public struct GroupEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public init(id: UUID, name: String) { self.id = id; self.name = name }
    }

    public struct ArrangementEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var groupIDs: [UUID]
        public init(id: UUID, name: String, groupIDs: [UUID]) { self.id = id; self.name = name; self.groupIDs = groupIDs }
    }

    /// A Look. `screens` is keyed by the upper-case text of a screen profile id.
    public struct LookEntry: Codable, Equatable, Sendable {
        public struct Screen: Codable, Equatable, Sendable {
            public var themeID: UUID?
            public var visibleLayers: [String]
            public init(themeID: UUID?, visibleLayers: [String]) { self.themeID = themeID; self.visibleLayers = visibleLayers }
        }
        public var id: UUID
        public var name: String
        public var screens: [String: Screen]
        public init(id: UUID, name: String, screens: [String: Screen]) { self.id = id; self.name = name; self.screens = screens }
    }

    /// A media bin entry that slide actions refer to by id. `file` is the package path of its file.
    public struct AssetEntry: Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var kind: MediaKind
        public var duration: Double?
        public var pixelWidth: Int?
        public var pixelHeight: Int?
        public var file: String
        public init(id: UUID, name: String, kind: MediaKind, duration: Double?, pixelWidth: Int?, pixelHeight: Int?, file: String) {
            self.id = id
            self.name = name
            self.kind = kind
            self.duration = duration
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.file = file
        }
    }

    /// One file of the package's `media/` folder, or a file that could not be read when the package was written.
    public struct MediaEntry: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Sendable { case included, missing }
        /// The package path: `media/<sha256>.<extension>`, or `media/missing/<file name>` for a missing one.
        public var file: String
        /// The file's name where it came from, without its folder.
        public var name: String
        public var status: Status
        public var sha256: String?
        public var size: Int64?
        public init(file: String, name: String, status: Status, sha256: String?, size: Int64?) {
            self.file = file
            self.name = name
            self.status = status
            self.sha256 = sha256
            self.size = size
        }
    }
}

/// What is asked of a path found in a package, and of the names the importer builds from it.
public enum ProgramPathRules {
    /// A package path is relative, starts with `media/`, and has no `.`, `..`, empty, backslash, control or NUL part.
    public static func isSafePackagePath(_ path: String) -> Bool {
        guard path.hasPrefix(ProgramFormat.mediaFolder + "/"), !path.hasSuffix("/") else { return false }
        if path.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\\" }) { return false }
        for part in path.split(separator: "/", omittingEmptySubsequences: false) {
            if part.isEmpty || part == "." || part == ".." { return false }
        }
        return true
    }

    /// A file name safe to write: no folders, no control characters, not empty, at most 120 bytes.
    static func safeName(_ raw: String, fallback: String = "file") -> String {
        var name = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? raw
        name = String(name.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name == "." || name == ".." { name = fallback }
        while name.utf8.count > 120 { name.removeLast() }
        return name
    }

    /// The extension kept on a stored media file: letters and digits only, at most 8, lower case. Possibly empty.
    static func safeExtension(of name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        guard ext.count <= 8, ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return "" }
        return ext
    }
}
