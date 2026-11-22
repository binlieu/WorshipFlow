// UI-006g: which presentations have slide actions, for the Cues mode's left column. A read; nothing is written.
import Foundation
import GRDB
@_spi(CueStore) import Persistence

/// A presentation with at least one slide that has actions.
public struct SlideActionPresentation: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    /// How many of its slides have actions.
    public var slideCount: Int

    public init(id: UUID, title: String, slideCount: Int) {
        self.id = id
        self.title = title
        self.slideCount = slideCount
    }
}

extension CueStore {
    /// Every presentation with slide actions and how many of its slides have them, by title. A slide's actions go with the slide, so
    /// a row is never left over for a presentation that is gone.
    public func presentationsWithSlideActions() async throws -> [SlideActionPresentation] {
        try await library.cueRead { db in
            try CueRows.require(db)
            return try Row.fetchAll(db, sql: """
                SELECT p.id AS id, p.title AS title, COUNT(*) AS n
                FROM cueSlideActions a
                JOIN slide s ON s.id = a.slideID
                JOIN presentation p ON p.id = s.presentationID
                GROUP BY p.id
                ORDER BY p.title COLLATE NOCASE, p.id
                """).compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return SlideActionPresentation(id: id, title: row["title"], slideCount: row["n"])
            }
        }
    }
}
