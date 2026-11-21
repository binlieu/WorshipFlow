// SYS-001: GRDB records. Internal; the public API speaks Domain types only.
import Foundation
import GRDB
import Domain

extension UUID {
    /// UUIDs are stored as upper-case text (ADR-0004 decision 10). Raw SQL must bind this form.
    var dbText: String { uuidString }
}

struct LibraryRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "library"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
    var id: UUID
    var name: String
    var sortOrder: Int
    var createdAt: Date
    var updatedAt: Date

    var domain: Library { Library(id: id, name: name, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt) }
}

struct PresentationRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "presentation"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
    var id: UUID
    var libraryID: UUID
    var title: String
    var kind: PresentationKind
    var titleFolded: String
    var bodyFolded: String
    var createdAt: Date
    var updatedAt: Date

    var domain: Presentation {
        Presentation(id: id, libraryID: libraryID, title: title, kind: kind, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct SlideRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "slide"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
    var id: UUID
    var presentationID: UUID
    var sortOrder: Int
    var primaryText: String
    var secondaryText: String?
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    var domain: Slide {
        Slide(id: id, presentationID: presentationID, sortOrder: sortOrder,
              content: SlideContent(primary: primaryText, secondary: secondaryText),
              notes: notes, createdAt: createdAt, updatedAt: updatedAt)
    }
}

struct PlaylistRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "playlist"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    var domain: Playlist { Playlist(id: id, name: name, createdAt: createdAt, updatedAt: updatedAt) }
}

struct PlaylistItemRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "playlistItem"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .uppercaseString }
    var id: UUID
    var playlistID: UUID
    var presentationID: UUID
    var sortOrder: Int
    var createdAt: Date
}
