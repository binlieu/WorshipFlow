// SYS-001: library, presentation, slide, playlist records as the rest of the app sees them. Foundation only.
import Foundation

public struct Library: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var sortOrder: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum PresentationKind: String, Sendable, Equatable, Codable, CaseIterable {
    case song, sermon, scripture, other
}

public struct Presentation: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var libraryID: UUID
    public var title: String
    public var kind: PresentationKind
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), libraryID: UUID, title: String, kind: PresentationKind,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.libraryID = libraryID
        self.title = title
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Slide: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let presentationID: UUID
    public var sortOrder: Int
    public var content: SlideContent
    public var notes: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), presentationID: UUID, sortOrder: Int = 0, content: SlideContent,
                notes: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.presentationID = presentationID
        self.sortOrder = sortOrder
        self.content = content
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Playlist: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One entry in a playlist. `title` is the referenced presentation's current title.
public struct PlaylistItem: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let playlistID: UUID
    public let presentationID: UUID
    public var title: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), playlistID: UUID, presentationID: UUID, title: String, sortOrder: Int) {
        self.id = id
        self.playlistID = playlistID
        self.presentationID = presentationID
        self.title = title
        self.sortOrder = sortOrder
    }
}

public struct SearchHit: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID { presentationID }
    public let presentationID: UUID
    public let title: String
    /// True when every query term was found in the title itself.
    public let matchedTitle: Bool

    public init(presentationID: UUID, title: String, matchedTitle: Bool) {
        self.presentationID = presentationID
        self.title = title
        self.matchedTitle = matchedTitle
    }
}
