// SYS-001
import Foundation

public enum StoreError: Error, Equatable, Sendable {
    /// The row a call refers to does not exist.
    case notFound
    /// A name or title is empty after trimming.
    case invalidName
    /// `open(at:migratingUpTo:)` was given a migration that does not exist.
    case unknownMigration(String)
    /// A group or arrangement id does not belong to the presentation it was used with.
    case invalidReference
}
