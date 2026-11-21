// LIB-004b: protecting a church's library file from a bad import.
//
// Two checks before anything is written: the file really is a WorshipFlow library (so a wrong path never gets a
// WorshipFlow schema written into somebody else's database), and no other process has it open (the app, or another
// tool). "In use" is judged by `lsof` on the file and its -wal and -shm companions, excluding this process. When lsof is
// not available, a -wal file that holds data counts as "in use" (changes not yet folded into the main file: the app is
// running or was killed). An empty -wal or a -shm file alone does not: SQLite on macOS leaves those behind after a clean close.
import Foundation
import SQLite3

enum LibraryFileKind: Equatable {
    case missing
    case empty
    case worshipFlowLibrary
    /// A SQLite file that is not a WorshipFlow library, or not SQLite at all. The text says what.
    case foreign(String)
}

enum LibraryProbe {
    static func inspect(path: String) -> LibraryFileKind {
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else { return .missing }
        let size = (try? manager.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        if size == 0 { return .empty }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return .foreign("it cannot be opened as a SQLite database")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil) == SQLITE_OK, let statement else {
            return .foreign("it is not a SQLite database")
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let c = sqlite3_column_text(statement, 0) { names.insert(String(cString: c)) }
        }
        if names.isEmpty { return .empty }
        return names.isSuperset(of: ["library", "presentation", "slide"]) ? .worshipFlowLibrary : .foreign("it has no WorshipFlow tables")
    }
}

struct LibraryHolder: Equatable {
    var pid: Int32
    var command: String
}

enum LibraryUsage: Equatable {
    case free
    case inUse([LibraryHolder])
    /// lsof could not be used, and a -wal file holds data.
    case suspected(String)
    /// lsof could not be used and there is no sign of use.
    case unknown
}

protocol LibraryUsageChecking: Sendable {
    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage
}

struct LsofUsageChecker: LibraryUsageChecking {
    var lsofPath = "/usr/sbin/lsof"

    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage {
        let manager = FileManager.default
        let companions = [path + "-wal", path + "-shm"].filter { manager.fileExists(atPath: $0) }
        let walSize = (try? manager.attributesOfItem(atPath: path + "-wal")[.size] as? Int) ?? 0
        let fallback: LibraryUsage = walSize > 0 ? .suspected((path as NSString).lastPathComponent + "-wal") : .unknown
        guard manager.isExecutableFile(atPath: lsofPath) else { return fallback }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = ["-F", "pc", "--", path] + companions
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return fallback }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // lsof exits 1 when nothing has the files open; other failures mean it could not tell.
        if process.terminationStatus > 1 { return fallback }
        return Self.parse(String(decoding: data, as: UTF8.self), ignoring: pid)
    }

    /// `lsof -F pc` prints `p<pid>` then `c<command>` for each process.
    static func parse(_ output: String, ignoring ownPID: Int32) -> LibraryUsage {
        var holders: [LibraryHolder] = []
        var pid: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let value = Int32(line.dropFirst()) { pid = value }
            else if line.hasPrefix("c"), let current = pid {
                if current != ownPID, !holders.contains(where: { $0.pid == current }) { holders.append(LibraryHolder(pid: current, command: String(line.dropFirst()))) }
                pid = nil
            }
        }
        return holders.isEmpty ? .free : .inUse(holders)
    }
}
