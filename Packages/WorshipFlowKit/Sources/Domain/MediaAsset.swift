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

    public init(id: UUID = UUID(), name: String, kind: MediaKind, path: String, bookmark: Data? = nil,
                duration: Double? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil, addedAt: Date = Date()) {
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
