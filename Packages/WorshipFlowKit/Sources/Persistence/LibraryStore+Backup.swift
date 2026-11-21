// FIX-G item 3 (LIB-005): a backup of the whole library, written with SQLite's backup API before an import replaces anything.
// The copy is a complete library file (it opens like the original) in `Backups/` beside the library, named with the date and
// "before import". The newest five of that kind are kept; files of any other name are never touched.
import Foundation
import GRDB

extension LibraryStore {
    public static let importBackupPrefix = "Library before import "
    public static let importBackupFolderName = "Backups"

    /// Writes a consistent copy of the library to `<library folder>/Backups/Library before import <UTC date>.sqlite` and
    /// removes the older backups of that kind beyond the newest `keeping`. Returns the new file. Throws (and leaves the
    /// library and the folder as they were) when the copy cannot be written; an in-memory store has no folder and throws.
    /// `date` is only used for the name.
    public func backUp(beforeImportAt date: Date, keeping: Int = 5) async throws -> URL {
        guard let root = mediaPaths?.root else {
            throw BackupError.noFolder
        }
        let writer = self.writer
        return try await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let folder = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(Self.importBackupFolderName, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = Self.stampFormatter.string(from: date)
            var counter = 1
            var target = folder.appendingPathComponent("\(Self.importBackupPrefix)\(stamp).sqlite")
            while fm.fileExists(atPath: target.path) {
                counter += 1
                target = folder.appendingPathComponent("\(Self.importBackupPrefix)\(stamp) \(counter).sqlite")
            }
            let partial = folder.appendingPathComponent(".\(target.lastPathComponent).partial")
            try? fm.removeItem(at: partial)
            do {
                let destination = try DatabaseQueue(path: partial.path)
                try writer.backup(to: destination)
                try destination.close()
                try fm.moveItem(at: partial, to: target)
            } catch {
                try? fm.removeItem(at: partial)
                throw error
            }
            Self.prune(folder, keeping: max(1, keeping))
            return target
        }.value
    }

    public enum BackupError: Error, LocalizedError, Equatable, Sendable {
        case noFolder
        public var errorDescription: String? { "This library is not kept in a folder, so it cannot be backed up." }
    }

    private static var stampFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HHmmss 'UTC'"
        return f
    }

    /// Sort key of a backup file name: the date text, then the counter that was added for a second backup in the same second.
    private static func sortKey(_ name: String) -> (String, Int)? {
        guard name.hasPrefix(importBackupPrefix), name.hasSuffix(".sqlite") else { return nil }
        let body = String(name.dropFirst(importBackupPrefix.count).dropLast(".sqlite".count))
        let parts = body.split(separator: " ")
        guard parts.count >= 3 else { return nil }
        return (parts[0...2].joined(separator: " "), parts.count > 3 ? Int(parts[3]) ?? 1 : 1)
    }

    private static func prune(_ folder: URL, keeping: Int) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { return }
        let ours = names.compactMap { name in sortKey(name).map { (name, $0) } }
            .sorted { ($0.1.0, $0.1.1) > ($1.1.0, $1.1.1) }
        for (name, _) in ours.dropFirst(keeping) { try? fm.removeItem(at: folder.appendingPathComponent(name)) }
    }
}
