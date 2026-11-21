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
    /// Added by migration v3. Read here, but never written by `insert`: the column does not exist on a v1 or v2
    /// store, and `LibraryStore.setTheme` is the only writer.
    var themeID: UUID? = nil

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.dbText
        container["libraryID"] = libraryID.dbText
        container["title"] = title
        container["kind"] = kind.rawValue
        container["titleFolded"] = titleFolded
        container["bodyFolded"] = bodyFolded
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
    }

    var domain: Presentation {
        Presentation(id: id, libraryID: libraryID, title: title, kind: kind, themeID: themeID,
                     createdAt: createdAt, updatedAt: updatedAt)
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
    /// Added by migration v2; nil for rows written under v1.
    var groupID: UUID?
    /// Added by migration v5: JSON for `SlideContent.objects`, NULL when there are none. Missing on older stores (reads
    /// as nil), and written by `insert` only when set, so a slide without objects still inserts on a v2 to v4 store.
    var objects: String? = nil

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id.dbText
        container["presentationID"] = presentationID.dbText
        container["sortOrder"] = sortOrder
        container["primaryText"] = primaryText
        container["secondaryText"] = secondaryText
        container["notes"] = notes
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt
        container["groupID"] = groupID?.dbText
        if let objects { container["objects"] = objects }
    }

    var domain: Slide {
        Slide(id: id, presentationID: presentationID, sortOrder: sortOrder,
              content: SlideContent(primary: primaryText, secondary: secondaryText, objects: SlideObjectsJSON.decode(objects)),
              notes: notes, groupID: groupID, createdAt: createdAt, updatedAt: updatedAt)
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

/// The `slide.objects` column: a JSON array of `SlideObject`, or NULL for none.
enum SlideObjectsJSON {
    static func encode(_ objects: [SlideObject]) -> String? {
        guard !objects.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(objects) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// An unreadable column reads as no objects rather than making the whole slide list fail to load in the middle of a service.
    static func decode(_ text: String?) -> [SlideObject] {
        guard let text, let data = text.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SlideObject].self, from: data)) ?? []
    }

    /// Words of the text boxes, for the search index.
    static func searchableText(_ objects: [SlideObject]) -> String {
        objects.compactMap { object -> String? in
            if case .text(let t) = object.content { return t.text }
            return nil
        }.joined(separator: "\n")
    }
}
