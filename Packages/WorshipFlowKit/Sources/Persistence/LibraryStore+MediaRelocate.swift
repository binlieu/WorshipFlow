// UI-006d: a bin item whose file moved keeps its identity (so slides that use it as their background recover) and gets the file's new place.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    public struct MediaPathInUse: Error, LocalizedError, Equatable {
        public var path: String
        public var errorDescription: String? { "Another item in the media bin already uses \(path)." }
    }

    /// Points the item at another file: its path, bookmark and what the file's header says. The id, the name and the date added stay.
    /// Throws `MediaPathInUse` when another item has that path (nothing changes then).
    public func relocateMediaAsset(id: UUID, path: String, bookmark: Data?, duration: Double?, pixelWidth: Int?, pixelHeight: Int?) async throws {
        let stored = storedPath(path)
        try await writer.write { db in
            try Self.requireExists(db, table: "mediaAsset", id: id)
            if let other = try String.fetchOne(db, sql: "SELECT id FROM mediaAsset WHERE path = ? AND id <> ?", arguments: [stored, id.dbText]), !other.isEmpty {
                throw MediaPathInUse(path: path)
            }
            try db.execute(sql: "UPDATE mediaAsset SET path = ?, bookmark = ?, duration = ?, pixelWidth = ?, pixelHeight = ? WHERE id = ?",
                           arguments: [stored, bookmark, duration, pixelWidth, pixelHeight, id.dbText])
        }
    }
}
