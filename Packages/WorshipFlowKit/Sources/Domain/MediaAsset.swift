// SYS-002 / MEDIA-01: a reference to a media file in the media bin. Foundation only.
// The store holds the reference, never the file: removing an asset never touches the user's file.
import Foundation

public enum MediaKind: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case image, video, audio
}

public struct MediaAsset: Sendable, Equatable, Codable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var kind: MediaKind
    /// Absolute file path as last seen.
    public var path: String
    /// Security-scoped bookmark, when the file was chosen through a sandboxed panel.
    public var bookmark: Data?
    /// Seconds. Nil for images.
    public var duration: Double?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public let addedAt: Date
    /// SYS-015: seconds into the clip where playback starts, and where it ends. Nil is the start and the end of the clip. Stored only in this slice.
    public var markIn: Double?
    public var markOut: Double?

    public init(id: UUID = UUID(), name: String, kind: MediaKind, path: String, bookmark: Data? = nil,
                duration: Double? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil, addedAt: Date = Date(),
                markIn: Double? = nil, markOut: Double? = nil) {
        self.markIn = markIn
        self.markOut = markOut
        self.id = id
        self.name = name
        self.kind = kind
        self.path = path
        self.bookmark = bookmark
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.addedAt = addedAt
    }
}

/// SYS-015: the rules for a clip's mark in and mark out, and for a marker's time. Total: a number that is no time is simply not valid.
public enum MediaMarks {
    /// A time is a real number from 0 to the clip's length (to `MediaClock.longest` when the length is not known).
    public static func isValidTime(_ time: Double, length: Double?) -> Bool {
        guard time.isFinite, time >= 0 else { return false }
        if let length, length.isFinite, length >= 0 { return time <= length }
        return time <= MediaClock.longest
    }

    /// Both marks are optional; each given mark is a valid time, and the in mark is not after the out mark.
    public static func isValid(markIn: Double?, markOut: Double?, length: Double?) -> Bool {
        if let markIn, !isValidTime(markIn, length: length) { return false }
        if let markOut, !isValidTime(markOut, length: length) { return false }
        if let markIn, let markOut, markIn > markOut { return false }
        return true
    }
}

/// SYS-015: a named time in a clip, with the actions that run when playback passes it. One kind of row serves the Media bin's markers and the
/// Cues' playback markers. `actions` is the versioned JSON text the cue rows use, `{"version":1,"actions":[...]}`; this type keeps it as text so
/// Domain stays independent of the cue engine, and `validatedActions` keeps what is stored well-formed.
public struct MediaMarker: Sendable, Equatable, Hashable, Identifiable {
    public var id: UUID
    public var assetID: UUID
    /// Seconds into the clip.
    public var time: Double
    public var name: String?
    public var actions: String
    /// Breaks a tie between markers at the same time; the order they were added in.
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date

    public static let maxNameLength = 120
    /// The longest actions text kept, in bytes.
    public static let maxActionsBytes = 64 * 1024
    /// The most markers one clip keeps.
    public static let maxPerAsset = 1_000
    /// A marker that runs nothing.
    public static let emptyActions = #"{"actions":[],"version":1}"#

    public init(id: UUID = UUID(), assetID: UUID, time: Double, name: String? = nil, actions: String = MediaMarker.emptyActions,
                sortOrder: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.assetID = assetID
        self.time = time
        self.name = name
        self.actions = actions
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Trimmed, bounded, and nil when nothing is left.
    public static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxNameLength))
    }

    /// The text in its stored spelling (compact, sorted keys), or nil when it is not a JSON object with an integer `version` of at least 1 and an
    /// `actions` array of objects, or is longer than `maxActionsBytes`. The kinds of action are not judged here: a marker may hold an action this build does not know.
    public static func validatedActions(_ text: String) -> String? {
        guard text.utf8.count <= maxActionsBytes, let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = root["version"] as? Int, version >= 1,
              let list = root["actions"] as? [Any], list.allSatisfy({ $0 is [String: Any] }),
              let out = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .withoutEscapingSlashes]),
              out.count <= maxActionsBytes else { return nil }
        return String(decoding: out, as: UTF8.self)
    }
}
