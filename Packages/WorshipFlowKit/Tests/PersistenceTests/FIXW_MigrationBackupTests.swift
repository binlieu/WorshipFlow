// FIX-W item 6 (SYS-015, ADR-0009 decision 4; REVIEW-5 L6): a library that holds data is never migrated without its copy. When its history cannot be
// read (so no copy can be judged or made) the library is refused with an actionable message and left as it was; a new, empty library still opens
// at once. Temporary libraries only.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct FIXW_MigrationBackupTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixw-\(UUID().uuidString)", isDirectory: true)
    }

    private func backups(in dir: URL) -> [String] {
        let backups = dir.appendingPathComponent(LibraryStore.importBackupFolderName, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: backups.path)) ?? []).filter { $0.hasPrefix("Library before migration") }
    }

    private func v14Library(at file: URL) async throws {
        let old = try LibraryStore.open(at: file, migratingUpTo: "v14")
        let lib = try await old.createLibrary(name: "Songs")
        _ = try await old.createPresentation(in: lib.id, title: "Song", kind: .song)
        try old.close()
    }

    @Test func aLibraryWhoseHistoryCannotBeReadIsRefusedAndLeftAsItWas() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Library.sqlite")
        let bytes = Data("This is not a library, but it is somebody's file.".utf8)
        try bytes.write(to: file)
        #expect(throws: MigrationBackupFailed.self) { _ = try LibraryStore.open(at: file) }
        #expect(try Data(contentsOf: file) == bytes)
        #expect(backups(in: dir).isEmpty)
    }

    @Test func aLibraryThatIsLockedWhenItIsOpenedIsRefusedWithTheCopyMessageAndNothingMigrates() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        try await v14Library(at: file)
        var config = Configuration()
        config.prepareDatabase { try $0.execute(sql: "PRAGMA locking_mode = EXCLUSIVE") }
        let holder = try DatabaseQueue(path: file.path, configuration: config)
        try await holder.write { try $0.execute(sql: "CREATE TABLE IF NOT EXISTS fixwProbe (x INTEGER)") }        // takes the lock and keeps it
        #expect(throws: MigrationBackupFailed.self) { _ = try LibraryStore.open(at: file) }
        try holder.close()
        #expect(backups(in: dir).isEmpty)
        let still = try LibraryStore.open(at: file, migratingUpTo: "v14")
        #expect(try await still.appliedMigrations().last == "v14")
        try still.close()
        // Once it can be read, the step runs with its copy as before.
        let opened = try LibraryStore.open(at: file)
        try opened.close()
        #expect(backups(in: dir).count == 1)
    }

    @Test func theRefusalSaysWhatToDo() {
        let text = MigrationBackupFailed(from: "", to: "v15", reason: "its history could not be read").errorDescription ?? ""
        #expect(text.contains("Nothing was changed") && text.contains("v15"))
    }

    @Test func aNewEmptyFileStillOpensWithoutACopy() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Library.sqlite")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let store = try LibraryStore.open(at: file)
        #expect(try await store.appliedMigrations().last == "v15")
        try store.close()
        #expect(backups(in: dir).isEmpty)
    }
}
