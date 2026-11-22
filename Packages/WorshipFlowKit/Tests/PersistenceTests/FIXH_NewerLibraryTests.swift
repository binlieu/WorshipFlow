// FIX-H item 14: a library whose applied migrations include one this build does not know was last opened by a newer WorshipFlow. This
// build must not open it for writing: it says so in plain words (naming both versions) and writes nothing.
import Testing
import Foundation
import GRDB
@testable import Persistence

@Suite struct FIXH_NewerLibraryTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixh14-\(UUID().uuidString)", isDirectory: true)
    }

    /// A library file written by this build, then given one migration row this build has never heard of.
    private func newerLibrary(_ extra: String = "v99") async throws -> URL {
        let file = folder().appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: file)
        try await store.writer.write { db in
            try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES (?)", arguments: [extra])
        }
        try store.close()
        return file
    }

    private func bytes(_ file: URL) throws -> [String: Data] {
        let dir = file.deletingLastPathComponent()
        var all: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() {
            all[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return all
    }

    @Test func aLibraryWithAnUnknownMigrationIsNotOpenedAndNothingIsWritten() async throws {
        let file = try await newerLibrary()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let before = try Data(contentsOf: file)
        do {
            _ = try LibraryStore.open(at: file)
            Issue.record("the library should not have been opened for writing")
        } catch let error as LibraryFromNewerBuildError {
            #expect(error.found == "v99" && error.known == Schema.makeMigrator().migrations.last)
        }
        #expect(try Data(contentsOf: file) == before)                           // the library file is byte for byte what it was
        #expect(try await readMigrations(file).contains("v99"))                  // and the foreign row is still there
    }

    @Test func theMessageIsPlainAndNamesBothVersions() async throws {
        let file = try await newerLibrary("v31")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        do { _ = try LibraryStore.open(at: file) } catch let error as LibraryFromNewerBuildError {
            let text = error.message(thisBuild: "1.4 (28)")
            #expect(text.contains("newer WorshipFlow") && text.contains("v31") && text.contains(error.known) && text.contains("1.4 (28)"))
            #expect(text.contains("Nothing was changed") && text.localizedCaseInsensitiveContains("quit") && text.localizedCaseInsensitiveContains("different library"))
            #expect(error.errorDescription == error.message(thisBuild: nil))
            #expect(!error.message(thisBuild: nil).contains("(nil)"))
        }
    }

    @Test func anUnknownRowInTheMiddleOfTheHistoryCountsToo() async throws {
        let file = try await newerLibrary("v7b")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(throws: LibraryFromNewerBuildError.self) { _ = try LibraryStore.open(at: file) }
    }

    @Test func aLibraryThisBuildWroteAndANewOneStillOpen() async throws {
        let file = folder().appendingPathComponent("Library.sqlite")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let first = try LibraryStore.open(at: file)                              // a new file
        try first.close()
        let again = try LibraryStore.open(at: file)                              // an existing one at the current version
        #expect(try await again.appliedMigrations() == Schema.makeMigrator().migrations)
        try again.close()
        // An older library (only some migrations applied) is migrated forward as before.
        let old = folder().appendingPathComponent("Library.sqlite")
        defer { try? FileManager.default.removeItem(at: old.deletingLastPathComponent()) }
        let v5 = try LibraryStore.open(at: old, migratingUpTo: "v5")
        try v5.close()
        let migrated = try LibraryStore.open(at: old)
        #expect(try await migrated.appliedMigrations().last == Schema.makeMigrator().migrations.last)
        try migrated.close()
    }

    private func readMigrations(_ file: URL) async throws -> [String] {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: file.path, configuration: config)
        return try await queue.read { try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations") }
    }
}
