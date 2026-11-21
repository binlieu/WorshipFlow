// UI-004: where the default library lives. The folder keeps the spelling the first builds used ("WORSHIPFLOW"), although the
// product is now written "WorshipFlow", so an existing library opens in place with no move (ADR-0004). The name is a constant
// here and is never read from the bundle name or the product name.
import Foundation

public enum LibraryLocation {
    public static let folderName = "WORSHIPFLOW"
    public static let fileName = "Library.sqlite"

    /// `<Application Support>/WORSHIPFLOW/Library.sqlite`.
    public static func defaultURL(applicationSupport base: URL) -> URL {
        base.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(fileName)
    }
}
