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
    /// SYS-015: a number or text that is not real or not in range (a mark outside the clip, a time that is not a time, actions that are not the versioned JSON), or a limit reached.
    case invalidValue
}

/// FIX-H item 14: the library was last opened by a newer WorshipFlow: its migration history holds a step this build does not know. This
/// build does not open it for writing (an older build would write rows the newer one cannot read back), and nothing is changed.
public struct LibraryFromNewerBuildError: Error, Equatable, Sendable, LocalizedError {
    /// The newest step in the library that this build does not know.
    public var found: String
    /// The newest step this build knows.
    public var known: String

    public init(found: String, known: String) {
        self.found = found
        self.known = known
    }

    /// Words for the operator. `thisBuild` is this WorshipFlow's version, when the caller has it.
    public func message(thisBuild: String?) -> String {
        let me = thisBuild.map { " (version \($0))" } ?? ""
        return "This library was last opened by a newer WorshipFlow: its data is at step \(found), and this WorshipFlow\(me) reads up to step \(known). Nothing was changed. Quit and open it with the newer WorshipFlow, or open a different library."
    }

    public var errorDescription: String? { message(thisBuild: nil) }
}
