// UI-001: two cheap read-only summaries for the sidebar: how many presentations each library holds, and which
// presentations carry a second language.
import Foundation
import GRDB
import Domain

extension LibraryStore {
    public func presentationCounts() async throws -> [UUID: Int] {
        try await writer.read { db in
            var result: [UUID: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT libraryID, COUNT(*) AS n FROM presentation GROUP BY libraryID") {
                if let id = UUID(uuidString: row["libraryID"] as String) { result[id] = row["n"] }
            }
            return result
        }
    }

    public func bilingualPresentationIDs() async throws -> Set<UUID> {
        try await writer.read { db in
            let ids = try String.fetchAll(db, sql: """
                SELECT DISTINCT presentationID FROM slide WHERE secondaryText IS NOT NULL AND TRIM(secondaryText) <> ''
                """)
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }
}
