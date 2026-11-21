// FIX-G items 11 and 14 (LIB-005): export planning hashes at utility priority and can be cancelled, a destination inside the
// library's folder is refused, and the chunked copy path of an export (used where cloning is refused) and a cancel inside it.
import Testing
import Foundation
import Darwin
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXG_ExportGuardTests {
    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var qos: [qos_class_t] = []
        private(set) var names: [String] = []
        func add(_ name: String) { lock.lock(); qos.append(qos_class_self()); names.append(name); lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return names.count }
    }

    @Test func hashingHappensAtUtilityPriority() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let seen = Seen()
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "1",
                                                  hooks: ProgramPlanHooks(onHash: { seen.add($0) }))
        #expect(plan.files.count == 4 && seen.count >= 4)
        #expect(seen.qos.allSatisfy { $0 == QOS_CLASS_UTILITY }, "every file was hashed at utility priority: \(seen.qos)")
    }

    @Test func planningCanBeCancelledAndWritesNothing() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let seen = Seen()
        let before = rig.listing(rig.root)
        do {
            _ = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "1",
                                               isCancelled: { seen.count >= 1 }, hooks: ProgramPlanHooks(onHash: { seen.add($0) }))
            Issue.record("must be cancelled")
        } catch let error as ProgramPackageError {
            #expect(error == .cancelled)
        }
        #expect(seen.count < 4, "it stopped before hashing everything")
        #expect(rig.listing(rig.root) == before)
    }

    @Test func aDestinationInsideTheLibraryFolderIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "1")
        let library = rig.url("home")
        for place in [library.appendingPathComponent("Sunday.worshipflowprogram"),
                      library.appendingPathComponent("Backups").appendingPathComponent("Sunday.worshipflowprogram"),
                      library.appendingPathComponent("Media/Imported/x/Sunday.worshipflowprogram")] {
            try FileManager.default.createDirectory(at: place.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = rig.listing(library)
            do {
                try ProgramExporter.write(plan, to: place)
                Issue.record("\(place.path) is inside the library folder and must be refused")
            } catch let error as ProgramPackageError {
                #expect(error == .destinationInsideLibrary)
                #expect(error.localizedDescription.contains("library folder"))
            }
            #expect(rig.listing(library) == before)
        }
        // A link that leads into the library does not get round it.
        let alias = rig.url("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: library)
        #expect(throws: ProgramPackageError.self) { try ProgramExporter.write(plan, to: alias.appendingPathComponent("viaLink.worshipflowprogram")) }
        // Anywhere else is fine, even a sibling whose name starts the same way.
        let sibling = rig.url("home-elsewhere")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try ProgramExporter.write(plan, to: sibling.appendingPathComponent("Sunday.worshipflowprogram"))
        #expect(FileManager.default.fileExists(atPath: sibling.appendingPathComponent("Sunday.worshipflowprogram/program.json").path))
    }

    @Test func whereCloningIsRefusedTheChunkedCopyWritesTheSameBytes() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "1")
        let pieces = ByteCounter()
        let destination = rig.url("Chunked.worshipflowprogram")
        try ProgramExporter.write(plan, to: destination, hooks: ProgramExportHooks(chunkSize: 100, cloneDisabled: true, onChunk: { pieces.add($0) }))
        #expect(pieces.total == plan.totalBytes)
        for file in plan.files {
            #expect(try Data(contentsOf: destination.appendingPathComponent(file.packagePath)) == Data(contentsOf: file.source))
        }
        // And it imports.
        let church = try rig.openStore("church")
        _ = try await ProgramImporter.apply(try ProgramPackageContents.open(destination), into: church)
        #expect(try await rowCounts(church)["presentation"] == 2)
    }

    @Test func aCancelInsideAnExportCopyLeavesNothingAtTheDestination() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID, appVersion: "1")
        let polls = Counter()
        let destination = rig.url("Cancelled.worshipflowprogram")
        let before = rig.listing(rig.root)
        do {
            try ProgramExporter.write(plan, to: destination, hooks: ProgramExportHooks(chunkSize: 64, cloneDisabled: true),
                                      isCancelled: { polls.next() > 30 })
            Issue.record("must be cancelled")
        } catch let error as ProgramPackageError {
            #expect(error == .cancelled)
        }
        #expect(polls.count > 30)
        #expect(rig.listing(rig.root) == before, "no package and no partial folder is left")
    }
}
