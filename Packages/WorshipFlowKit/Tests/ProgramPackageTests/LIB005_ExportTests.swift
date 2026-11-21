// LIB-005 item 2 and the media rules of item 1: what an export contains and how it is written.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
import ProgramPackage

@Suite struct LIB005_ExportTests {
    @Test func theProgramJSONHasNoAbsolutePathHomeFolderOrVolumeName() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let data = try Data(contentsOf: package.appendingPathComponent(ProgramFormat.manifestName))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.isEmpty)
        for forbidden in [rig.root.path, NSHomeDirectory(), "/Users", "/Volumes", "/private", "/var/folders", "file://", "ExternalDrive",
                          "NSTemporaryDirectory", FileManager.default.temporaryDirectory.path] {
            #expect(!text.contains(forbidden), "program.json must not contain \(forbidden)")
        }
        let document = try JSONDecoder().decode(ProgramDocument.self, from: data)
        #expect(document.format == "worshipflow-program")
        #expect(document.formatVersion == 1)
        #expect(document.appVersion == "9.9.9")
        #expect(!document.media.isEmpty)
        for entry in document.media { #expect(ProgramPathRules.isSafePackagePath(entry.file)) }
        #expect(package.pathExtension == "worshipflowprogram")
    }

    @Test func identicalMediaIsStoredOnce() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        // a.png and "copy of a.png" are the same bytes: images A/B, C, the theme background and the clip are four files.
        #expect(plan.files.count == 4)
        #expect(Set(plan.files.map(\.sha256)).count == 4)
        let destination = rig.url("Once.worshipflowprogram")
        try ProgramExporter.write(plan, to: destination)
        let stored = rig.listing(destination.appendingPathComponent("media")).filter { !$0.contains("/") }
        #expect(stored.count == 4)
        #expect(plan.totalBytes == 2_000 + 2_000 + 2_000 + 5_000)
        // Both slides that used the two copies point at the one stored file.
        let document = plan.document
        let paths = document.presentations.flatMap(\.slides).flatMap(\.objects).compactMap { object -> String? in
            if case .image(let image) = object.content { return image.path } else { return nil }
        }
        #expect(paths.count == 3)
        #expect(Set(paths).count == 2)
    }

    @Test func aMissingMediaFileIsReportedAndRecordedAndTheExportStillSucceeds() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        try FileManager.default.removeItem(at: home.imageC)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        #expect(plan.missing.map(\.name) == ["c.jpg"])
        #expect(plan.files.count == 3)
        let destination = rig.url("Missing.worshipflowprogram")
        try ProgramExporter.write(plan, to: destination)
        let document = try JSONDecoder().decode(
            ProgramDocument.self, from: Data(contentsOf: destination.appendingPathComponent(ProgramFormat.manifestName)))
        let recorded = document.media.filter { $0.status == .missing }
        #expect(recorded.map(\.name) == ["c.jpg"])
        #expect(recorded.allSatisfy { $0.sha256 == nil && ProgramPathRules.isSafePackagePath($0.file) })
        let text = try String(contentsOf: destination.appendingPathComponent(ProgramFormat.manifestName), encoding: .utf8)
        #expect(!text.contains(rig.root.path))
    }

    @Test func theLibraryIsNotTouchedByAnExport() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let before = try await rowCounts(home.store)
        let slidesBefore = try await home.store.slides(of: home.songOne)
        try await home.export()
        #expect(try await rowCounts(home.store) == before)
        #expect(try await home.store.slides(of: home.songOne) == slidesBefore)
        #expect(FileManager.default.fileExists(atPath: home.imageA.path))
    }

    @Test func aCancelledExportLeavesNothingAtTheDestinationOrBesideIt() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        let outbox = rig.url("outbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let destination = outbox.appendingPathComponent("Cancelled.worshipflowprogram")
        let polls = Counter()
        #expect(throws: ProgramPackageError.cancelled) {
            try ProgramExporter.write(plan, to: destination, isCancelled: { polls.next() > 1 })
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(rig.listing(outbox).isEmpty)
        #expect(polls.count >= 2)
    }

    @Test func aFailedExportLeavesNothingAtTheDestinationOrBesideIt() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        let outbox = rig.url("outbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let destination = outbox.appendingPathComponent("Failed.worshipflowprogram")
        #expect(throws: Boom.self) {
            try ProgramExporter.write(plan, to: destination, hooks: ProgramExportHooks(afterFile: { n in if n == 2 { throw Boom() } }))
        }
        #expect(rig.listing(outbox).isEmpty)
        #expect(throws: Boom.self) {
            try ProgramExporter.write(plan, to: destination, hooks: ProgramExportHooks(beforeMove: { throw Boom() }))
        }
        #expect(rig.listing(outbox).isEmpty)
    }

    @Test func aSourceThatChangesWhileExportingFailsWithoutLeavingAPackage() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        try rig.bytes(seed: 99, count: 2_100).write(to: home.imageC)       // changed after the plan was made
        let outbox = rig.url("outbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        #expect(throws: ProgramPackageError.self) {
            try ProgramExporter.write(plan, to: outbox.appendingPathComponent("Changed.worshipflowprogram"))
        }
        #expect(rig.listing(outbox).isEmpty)
    }

    @Test func anExistingFileIsNeverReplacedWithoutBeingAsked() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        let destination = rig.url("Taken.worshipflowprogram")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: destination.appendingPathComponent("mine.txt"))
        #expect(throws: ProgramPackageError.destinationExists("Taken.worshipflowprogram")) {
            try ProgramExporter.write(plan, to: destination)
        }
        #expect(rig.listing(destination) == ["mine.txt"])
        #expect(rig.listing(rig.root).filter { $0.hasPrefix(".") || $0.contains("tmp") }.isEmpty)
        // Once the person agreed to replace it, it is replaced as a whole.
        try ProgramExporter.write(plan, to: destination, replaceExisting: true)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("program.json").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("mine.txt").path))
    }

    @Test func progressReportsEveryFileAndTheTotalBytes() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        let seen = ProgressLog()
        try ProgramExporter.write(plan, to: rig.url("P.worshipflowprogram"), progress: { seen.add($0) })
        let last = try #require(seen.all.last)
        #expect(last.bytesDone == plan.totalBytes && last.bytesTotal == plan.totalBytes)
        #expect(last.filesDone == 4 && last.filesTotal == 4)
        #expect(seen.all.map(\.bytesDone) == seen.all.map(\.bytesDone).sorted())
    }

    @Test func aProgramThatDoesNotExistIsRefused() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        await #expect(throws: ProgramPackageError.playlistNotFound) {
            _ = try await ProgramExporter.plan(store: home.store, playlistID: UUID())
        }
    }

    @Test func theActionsAreKeptExactlyIncludingAKindThisBuildDoesNotKnow() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let plan = try await ProgramExporter.plan(store: home.store, playlistID: home.playlistID)
        let song = try #require(plan.document.presentations.first { $0.id == home.songOne })
        let actions = try #require(song.slides.first?.actions)
        guard case .object(let object) = actions, case .array(let list)? = object["actions"] else { Issue.record("actions not an object"); return }
        #expect(list.count == 3)
        guard case .object(let last) = list[2] else { Issue.record("no third action"); return }
        #expect(last["kind"] == .string("future.thing"))
        // The clip, the Look and the theme the actions and presentations use travel with the program.
        #expect(plan.document.mediaAssets.map(\.id) == [home.assetID])
        #expect(plan.document.looks.map(\.id) == [home.lookID])
        #expect(plan.document.themes.map(\.id) == [home.themeID])
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ProgramProgress] = []
    func add(_ p: ProgramProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [ProgramProgress] { lock.lock(); defer { lock.unlock() }; return items }
}
