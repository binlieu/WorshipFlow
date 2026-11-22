// TESTDATA-001: is another process (the app) holding the library file open? Judged by `lsof` on the file and its -wal and -shm
// companions, excluding this process. When lsof cannot be used, a -wal file that holds data counts as "in use" (the app is running or
// was killed); with no sign at all the answer is `.unknown`, which the importer treats as free.
import Foundation

public struct LibraryHolder: Equatable, Sendable {
    public var pid: Int32
    public var command: String
}

public enum LibraryUsage: Equatable, Sendable {
    case free
    case inUse([LibraryHolder])
    case suspected(String)
    case unknown
}

public protocol LibraryUsageChecking: Sendable {
    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage
}

public struct LsofUsageChecker: LibraryUsageChecking {
    public var lsofPath = "/usr/sbin/lsof"
    public init() {}

    public func usage(of path: String, ignoring pid: Int32) -> LibraryUsage {
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
        if process.terminationStatus > 1 { return fallback }     // lsof exits 1 when nothing has the files open
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
