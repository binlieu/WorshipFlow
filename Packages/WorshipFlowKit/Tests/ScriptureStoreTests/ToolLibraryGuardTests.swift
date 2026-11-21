// LIB-004b: the checks that protect a library file: is it a library, and does another process have it open.
import Testing
import Foundation
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore

@Suite struct ToolLibraryGuardTests {
    @Test func theProbeTellsKindsOfFileApart() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(LibraryProbe.inspect(path: dir.appendingPathComponent("none").path) == .missing)
        let empty = dir.appendingPathComponent("empty"); FileManager.default.createFile(atPath: empty.path, contents: Data())
        #expect(LibraryProbe.inspect(path: empty.path) == .empty)
        let text = dir.appendingPathComponent("text"); try "hello world, not sqlite at all".write(to: text, atomically: true, encoding: .utf8)
        if case .foreign = LibraryProbe.inspect(path: text.path) {} else { Issue.record("a text file is not a library") }
        let lib = dir.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: lib)
        try store.close()
        #expect(LibraryProbe.inspect(path: lib.path) == .worshipFlowLibrary)
        // An older library file (v1) is still a library.
        let old = dir.appendingPathComponent("old.sqlite")
        try LibraryStore.open(at: old, migratingUpTo: "v1").close()
        #expect(LibraryProbe.inspect(path: old.path) == .worshipFlowLibrary)
    }

    @Test func lsofOutputIsParsedAndOurOwnProcessIsIgnored() {
        let output = "p100\ncWORSHIPFLOW\np200\ncwf-bible-import\np100\ncWORSHIPFLOW\n"
        #expect(LsofUsageChecker.parse(output, ignoring: 200) == .inUse([LibraryHolder(pid: 100, command: "WORSHIPFLOW")]))
        #expect(LsofUsageChecker.parse(output, ignoring: 100) == .inUse([LibraryHolder(pid: 200, command: "wf-bible-import")]))
        #expect(LsofUsageChecker.parse("p200\ncme\n", ignoring: 200) == .free)
        #expect(LsofUsageChecker.parse("", ignoring: 1) == .free)
    }

    @Test func withoutLsofOnlyAWalThatHoldsDataCountsAsInUse() throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = dir.appendingPathComponent("Library.sqlite")
        FileManager.default.createFile(atPath: lib.path, contents: Data("x".utf8))
        let checker = LsofUsageChecker(lsofPath: "/nonexistent/lsof")
        #expect(checker.usage(of: lib.path, ignoring: 1) == .unknown)
        // SQLite on macOS leaves an empty -wal and a -shm after a clean close: not a sign of use.
        FileManager.default.createFile(atPath: lib.path + "-wal", contents: Data())
        FileManager.default.createFile(atPath: lib.path + "-shm", contents: Data(count: 32768))
        #expect(checker.usage(of: lib.path, ignoring: 1) == .unknown)
        FileManager.default.createFile(atPath: lib.path + "-wal", contents: Data(count: 4096))
        #expect(checker.usage(of: lib.path, ignoring: 1) == .suspected("Library.sqlite-wal"))
    }

    /// The real lsof against a real process that has the file open. Skipped where lsof is not installed.
    @Test func aLibraryClosedByTheToolLeavesNothingThatBlocksTheNextRun() async throws {
        // The tool closes its store when it is done; the files SQLite leaves behind must not look like use.
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = dir.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: lib)
        _ = try await store.createLibrary(name: "x")
        try store.close()
        #expect(LsofUsageChecker(lsofPath: "/nonexistent/lsof").usage(of: lib.path, ignoring: 1) == .unknown)
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof")))
    func aProcessHoldingTheFileOpenIsFound() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = dir.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: lib)
        try store.close()
        let checker = LsofUsageChecker()
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(checker.usage(of: lib.path, ignoring: me) == .free)

        let holder = Process()
        holder.executableURL = URL(fileURLWithPath: "/bin/sh")
        holder.arguments = ["-c", "exec 3< '\(lib.path)'; exec sleep 30"]
        try holder.run()
        defer { holder.terminate(); holder.waitUntilExit() }
        var found: LibraryUsage = .free
        for _ in 0..<40 {
            found = checker.usage(of: lib.path, ignoring: me)
            if found != .free { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard case .inUse(let holders) = found else { Issue.record("the holder was not found: \(found)"); return }
        #expect(holders.contains { $0.pid == holder.processIdentifier })
        // This very process holding it is not "another program".
        let mine = try LibraryStore.open(at: lib)
        holder.terminate(); holder.waitUntilExit()
        #expect(checker.usage(of: lib.path, ignoring: me) == .free)
        try mine.close()
    }
}
