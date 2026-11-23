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

    /// SYS-015: the prefix of the copy taken before a migration, `Library before migration to v15 (was v14) <UTC date>.sqlite`, in the same `Backups/`
    /// folder. One copy per step that actually runs on a library that holds data; none for a new library, an in-memory store or a fixture built step by
    /// step. These copies are never pruned (a schema step is rare and the file is a library).
    public static let migrationBackupPrefix = "Library before migration "

    /// Copies the library beside itself, with SQLite's backup API, when it already has applied migrations and this build knows one it lacks.
    /// Throws `MigrationBackupFailed` (and migrates nothing) when the copy cannot be written: no migration runs without its safety copy.
    static func backUpBeforeMigrating(libraryFile: URL, date: Date = Date()) throws {
        guard FileManager.default.fileExists(atPath: libraryFile.path) else { return }
        let known = Schema.makeMigrator().migrations
        var config = Configuration()
        config.readonly = true
        // FIX-W (REVIEW-5 L6): a library that cannot be read this way gets no copy and so must not be migrated: it is refused, unchanged, unless the
        // file is empty (a new library). The reason names what failed; ADR-0009 decision 4.
        let size = ((try? FileManager.default.attributesOfItem(atPath: libraryFile.path))?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { return }
        // A read-only connection to a library in WAL mode can fail to open (SQLITE_CANTOPEN) when its -wal and -shm files are not there, which is the
        // normal state of a library that was closed cleanly: then the history is read through an ordinary connection, the one the open is about to
        // make anyway. Only when neither can read it is the library refused.
        func readHistory(_ configuration: Configuration) throws -> (DatabaseQueue, [String]) {
            let queue = try DatabaseQueue(path: libraryFile.path, configuration: configuration)
            do {
                let applied = try queue.read { db in
                    try db.tableExists("grdb_migrations") ? try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY rowid") : []
                }
                return (queue, applied)
            } catch { try? queue.close(); throw error }
        }
        let source: DatabaseQueue
        let applied: [String]
        do {
            do { (source, applied) = try readHistory(config) }
            catch { (source, applied) = try readHistory(Configuration()) }
        } catch {
            throw MigrationBackupFailed(from: "", to: known.last ?? "", reason: "the library could not be read to take the copy: \(error.localizedDescription)")
        }
        defer { try? source.close() }
        guard let last = applied.last, let target = known.last, !known.allSatisfy(applied.contains) else { return }
        let fm = FileManager.default
        let folder = libraryFile.deletingLastPathComponent().appendingPathComponent(importBackupFolderName, isDirectory: true)
        let stamp = stampFormatter.string(from: date)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var counter = 1
            var name = "\(migrationBackupPrefix)to \(target) (was \(last)) \(stamp).sqlite"
            while fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                counter += 1
                name = "\(migrationBackupPrefix)to \(target) (was \(last)) \(stamp) \(counter).sqlite"
            }
            let target = folder.appendingPathComponent(name)
            let partial = folder.appendingPathComponent(".\(name).partial")
            try? fm.removeItem(at: partial)
            do {
                let destination = try DatabaseQueue(path: partial.path)
                try source.backup(to: destination)
                try destination.close()
                try fm.moveItem(at: partial, to: target)
            } catch {
                try? fm.removeItem(at: partial)
                throw error
            }
        } catch {
            throw MigrationBackupFailed(from: last, to: target, reason: error.localizedDescription)
        }
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

/// SYS-015: the safety copy before a migration could not be written, so the library was left as it was.
public struct MigrationBackupFailed: Error, Equatable, Sendable, LocalizedError {
    public var from: String
    public var to: String
    public var reason: String
    public var errorDescription: String? {
        "This library needs an update (\(from.isEmpty ? "to \(to)" : "step \(from) to \(to)")), and a copy of it could not be saved first (\(reason)). Nothing was changed. Free some space or fix the folder's permissions, then open the library again."
    }
}
