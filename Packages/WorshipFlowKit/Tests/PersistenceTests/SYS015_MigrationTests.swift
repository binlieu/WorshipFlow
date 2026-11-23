// SYS-015 (SYS): migration v15 is additive. It adds `mediaAsset.markIn` and `mediaAsset.markOut` (REAL, NULL) and the table `mediaMarker`
// (cascades with its asset). Nothing else changes: every v14 row reads back by value, running the migrator again does nothing, a fresh
// library reaches the same shape by the same path, and a library that already holds data is copied aside before the step runs.
import Testing
import Foundation
import GRDB
import Domain
@testable import Persistence

@Suite struct SYS015_MigrationTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("wf-sys015-\(UUID().uuidString)", isDirectory: true)
    }

    /// A v14 library with content in every table the earlier slices write to.
    private func v14Library(at file: URL) async throws -> (presentation: UUID, asset: UUID) {
        let old = try LibraryStore.open(at: file, migratingUpTo: "v14")
        let lib = try await old.createLibrary(name: "Songs")
        let p = try await old.createPresentation(in: lib.id, title: "Song", kind: .song)
        let shape = SlideObject(frame: NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), content: .shape(ShapeObject(shape: .ellipse, fill: .white)))
        _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: "one", secondary: "một", objects: [shape]))
        _ = try await old.appendSlide(to: p.id, content: SlideContent(primary: "two"))
        let asset = try await old.addMediaAsset(name: "Loop", kind: .video, path: "/media/loop.mov", bookmark: nil, duration: 12.5, pixelWidth: 1920, pixelHeight: 1080)
        _ = try await old.addMediaAsset(name: "Picture", kind: .image, path: "/media/pic.png", bookmark: Data([1, 2]), duration: nil, pixelWidth: 10, pixelHeight: 20)
        try await old.saveScreenProfiles([ScreenProfile(name: "Audience", role: .audience, destination: .window, connectedTo: ["Projector"]),
                                          ScreenProfile(name: "Stage", role: .stage, destination: .window)])
        try await old.saveLook(Look(id: UUID(), name: "Everything"))
        try old.close()
        return (p.id, asset.id)
    }

    /// Every row of every table as text, per table, for the columns named in `columns` (the table's v14 columns).
    private func dump(_ store: LibraryStore, columns: [String: [String]]) async throws -> [String: [[String]]] {
        try await store.writer.read { db in
            var out: [String: [[String]]] = [:]
            for (table, names) in columns {
                let rows = try Row.fetchAll(db, sql: "SELECT \(names.map { "\"\($0)\"" }.joined(separator: ", ")) FROM \"\(table)\"")
                out[table] = rows.map { row in names.map { String(describing: row[$0] as DatabaseValue) } }.sorted { $0.joined(separator: "\u{1}") < $1.joined(separator: "\u{1}") }
            }
            return out
        }
    }

    /// The ordinary tables and their columns. A full-text index and the tables SQLite keeps for it are not data and are left out.
    private func tableColumns(_ store: LibraryStore) async throws -> [String: [String]] {
        try await store.writer.read { db in
            let virtual = try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND sql LIKE 'CREATE VIRTUAL%'")
            var out: [String: [String]] = [:]
            for table in try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name") {
                if table.hasPrefix("grdb_") || virtual.contains(table) || virtual.contains(where: { table.hasPrefix($0 + "_") }) { continue }
                out[table] = try db.columns(in: table).map(\.name)
            }
            return out
        }
    }

    @Test func v15AddsTheColumnsAndTheTableAndKeepsEveryOlderRowByValue() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        let ids = try await v14Library(at: file)

        let probe = try LibraryStore.open(at: file, migratingUpTo: "v14")
        let columns = try await tableColumns(probe)
        #expect(!(columns["mediaAsset"] ?? []).contains("markIn") && columns["mediaMarker"] == nil)
        let before = try await dump(probe, columns: columns)
        try probe.close()

        let new = try LibraryStore.open(at: file)
        let applied = try await new.appliedMigrations()
        #expect(applied == (1...15).map { "v\($0)" })
        let after = try await dump(new, columns: columns)
        #expect(after == before)
        let assetColumns = try await new.columnNames(of: "mediaAsset")
        #expect(assetColumns.contains("markIn") && assetColumns.contains("markOut"))
        let marker = try await new.columnNames(of: "mediaMarker")
        #expect(marker == ["id", "assetID", "time", "name", "actions", "sortOrder", "createdAt", "updatedAt"])
        // The new columns start empty.
        let marked = try await new.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM mediaAsset WHERE markIn IS NOT NULL OR markOut IS NOT NULL") }
        #expect(marked == 0)
        #expect(try await new.slides(of: ids.presentation).map(\.content.primary) == ["one", "two"])
        let fk = try await new.writer.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }
        #expect(fk.isEmpty)
    }

    @Test func runningTheMigratorAgainIsANoOp() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        _ = try await v14Library(at: file)
        let first = try LibraryStore.open(at: file)
        let columns = try await tableColumns(first)
        let snapshot = try await dump(first, columns: columns)
        try first.close()
        let again = try LibraryStore.open(at: file)
        #expect(try await again.appliedMigrations().filter { $0 == "v15" }.count == 1)
        #expect(try await tableColumns(again) == columns)
        #expect(try await dump(again, columns: columns) == snapshot)
        // The step itself, run on a database that already has it, is refused by the migrator's own bookkeeping and writes nothing.
        let migrator = Schema.makeMigrator()
        try migrator.migrate(again.writer)
        #expect(try await dump(again, columns: columns) == snapshot)
    }

    @Test func aFreshLibraryReachesTheSameShapeByTheSamePath() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fresh = try LibraryStore.open(at: dir.appendingPathComponent("Fresh.sqlite"))
        _ = try await v14Library(at: dir.appendingPathComponent("Old.sqlite"))
        let migrated = try LibraryStore.open(at: dir.appendingPathComponent("Old.sqlite"))
        #expect(try await fresh.appliedMigrations() == (1...15).map { "v\($0)" })
        #expect(try await tableColumns(fresh) == tableColumns(migrated))
        let freshIndexes = try await fresh.writer.read { try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'mediaMarker' ORDER BY name") }
        #expect(freshIndexes.contains { $0.contains("assetID") })
        let inMemory = try LibraryStore.inMemory()
        #expect(try await inMemory.appliedMigrations().last == "v15")
    }

    @Test func deletingAMediaAssetRemovesItsMarkers() async throws {
        let store = try LibraryStore.inMemory()
        let a = try await store.addMediaAsset(name: "A", kind: .video, path: "/m/a.mov", bookmark: nil, duration: 60, pixelWidth: nil, pixelHeight: nil)
        let b = try await store.addMediaAsset(name: "B", kind: .video, path: "/m/b.mov", bookmark: nil, duration: 60, pixelWidth: nil, pixelHeight: nil)
        try await store.writer.write { db in
            for (n, asset) in [(0, a.id), (1, a.id), (2, b.id)] {
                try db.execute(sql: "INSERT INTO mediaMarker (id, assetID, time, name, actions, sortOrder, createdAt, updatedAt) VALUES (?, ?, ?, NULL, ?, ?, ?, ?)",
                               arguments: [UUID().uuidString, asset.uuidString, Double(n), #"{"version":1,"actions":[]}"#, n, Date(), Date()])
            }
        }
        try await store.removeMediaAsset(id: a.id)
        let left = try await store.writer.read { try Row.fetchAll($0, sql: "SELECT assetID FROM mediaMarker") }
        #expect(left.map { $0["assetID"] as String } == [b.id.uuidString])
        let fk = try await store.writer.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_check") }
        #expect(fk.isEmpty)
    }

    // MARK: The copy taken before the step

    private func backups(in dir: URL) -> [String] {
        let folder = dir.appendingPathComponent(LibraryStore.importBackupFolderName, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { $0.hasPrefix("Library before migration") && $0.hasSuffix(".sqlite") }.sorted()
    }

    @Test func aLibraryThatHoldsDataIsCopiedAsideBeforeV15RunsAndTheCopyIsTheOldLibrary() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        let ids = try await v14Library(at: file)
        #expect(backups(in: dir).isEmpty)

        let new = try LibraryStore.open(at: file)
        try new.close()
        let made = backups(in: dir)
        #expect(made.count == 1)
        let name = try #require(made.first)
        #expect(name.contains("v14") && name.contains("v15") && name.hasSuffix(".sqlite"))

        // The copy opens as the old library: at v14, with its rows, and without the new columns.
        let copy = dir.appendingPathComponent(LibraryStore.importBackupFolderName).appendingPathComponent(name)
        let old = try LibraryStore.open(at: copy, migratingUpTo: "v14")
        #expect(try await old.appliedMigrations().last == "v14")
        #expect(!(try await old.columnNames(of: "mediaAsset").contains("markIn")))
        #expect(try await old.slides(of: ids.presentation).map(\.content.primary) == ["one", "two"])
        try old.close()

        // Opening again takes no second copy: the step ran once.
        let again = try LibraryStore.open(at: file)
        try again.close()
        #expect(backups(in: dir) == made)
    }

    @Test func aFreshLibraryAndAnInMemoryStoreTakeNoCopy() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fresh = try LibraryStore.open(at: dir.appendingPathComponent("Library.sqlite"))
        try fresh.close()
        #expect(backups(in: dir).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(LibraryStore.importBackupFolderName).path))
    }

    @Test func aFixtureBuiltStepByStepIsNotCopiedAtEachStep() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        let step = try LibraryStore.open(at: file, migratingUpTo: "v5")
        try step.close()
        let more = try LibraryStore.open(at: file, migratingUpTo: "v9")
        try more.close()
        #expect(backups(in: dir).isEmpty)
    }

    @Test func whenTheCopyCannotBeWrittenNothingIsMigrated() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        _ = try await v14Library(at: file)
        // A plain file where the Backups folder belongs.
        try Data("not a folder".utf8).write(to: dir.appendingPathComponent(LibraryStore.importBackupFolderName))
        #expect(throws: MigrationBackupFailed.self) { _ = try LibraryStore.open(at: file) }
        let still = try LibraryStore.open(at: file, migratingUpTo: "v14")
        #expect(try await still.appliedMigrations().last == "v14")
        #expect(!(try await still.columnNames(of: "mediaAsset").contains("markIn")))
    }

    /// Decision for item 1 of the brief: a build older than v15 cannot read a `video` object, so it must never open a library that has been through v15. The
    /// refusal is the existing newer-library guard (FIX-H item 14): any migration the build does not know. This build applies the same rule to a later step.
    @Test func aLibraryAtAStepThisBuildDoesNotKnowIsRefusedAndLeftAsItWas() async throws {
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: file)
        _ = try await store.addMediaAsset(name: "A", kind: .video, path: "/m/a.mov", bookmark: nil, duration: 5, pixelWidth: nil, pixelHeight: nil)
        try await store.writer.write { try $0.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v16')") }
        try store.close()
        #expect(throws: LibraryFromNewerBuildError(found: "v16", known: "v15")) { _ = try LibraryStore.open(at: file) }
        #expect(backups(in: dir).isEmpty)        // refused before anything is copied or changed
    }

    @Test func aStoredObjectOfAKindThisBuildDoesNotKnowReadsAsNoObjectsAndDoesNotStopTheListLoading() async throws {
        let store = try LibraryStore.inMemory()
        let lib = try await store.createLibrary(name: "Songs")
        let p = try await store.createPresentation(in: lib.id, title: "Song", kind: .song)
        _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "one"))
        let future = #"[{"content":{"hologram":{"_0":{}}},"frame":{"height":1,"width":1,"x":0,"y":0},"id":"00000000-0000-0000-0000-0000000000AA","opacity":1}]"#
        try await store.writer.write { try $0.execute(sql: "UPDATE slide SET objects = ?", arguments: [future]) }
        #expect(try await store.slides(of: p.id).map(\.content.primary) == ["one"])
        #expect(try await store.slides(of: p.id)[0].content.objects.isEmpty)
    }
}
