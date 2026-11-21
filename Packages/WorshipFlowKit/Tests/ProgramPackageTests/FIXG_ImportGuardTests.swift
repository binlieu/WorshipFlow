// FIX-G items 3 and 7 (LIB-005): a backup before an import that replaces content, a live presentation is not replaced, a size
// guard before copying, and a copy that stops when a file is bigger than the manifest says. The chunked copy and a cancel inside
// a copy are exercised with a tiny chunk size, so no large file is needed.
import Testing
import Foundation
import Domain
@_spi(ProgramPackage) import Persistence
@testable import ProgramPackage

@Suite struct FIXG_ImportGuardTests {
    /// A church library that already holds the program, then edited so that the package conflicts with it.
    private func conflicted(_ rig: Rig) async throws -> (HomeProgram, URL, LibraryStore, ProgramPackageContents) {
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church)
        try await makeConflicting(church, home: home)
        return (home, package, church, contents)
    }

    private func firstSlideText(_ store: LibraryStore, _ id: UUID) async throws -> String {
        try await store.slides(of: id).first?.content.primary ?? "?"
    }

    // MARK: Backup

    @Test func anImportThatReplacesWritesABackupFirstAndTheBackupHoldsTheOldContent() async throws {
        let rig = try Rig()
        let (home, _, church, contents) = try await conflicted(rig)
        let dates = FixedDates()
        let result = try await ProgramImporter.apply(contents, into: church, choice: .useImported,
                                                     hooks: ProgramImportHooks(now: { dates.tick() }))
        let backup = try #require(result.backupURL)
        #expect(FileManager.default.fileExists(atPath: backup.path))
        #expect(backup.deletingLastPathComponent().lastPathComponent == "Backups")
        #expect(backup.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == rig.url("church").standardizedFileURL.path)
        #expect(backup.lastPathComponent.contains("before import"))
        #expect(backup.lastPathComponent.contains("2027"), "the name carries the (injected) date")
        #expect(try await firstSlideText(church, home.songOne) == "First line of verse")
        let old = try LibraryStore.open(at: backup)
        #expect(try await firstSlideText(old, home.songOne) == "First line of verse (church edit)")
        try old.close()
    }

    @Test func anImportThatReplacesNothingWritesNoBackup() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        let first = try await ProgramImporter.apply(contents, into: church)
        #expect(first.backupURL == nil)
        try await makeConflicting(church, home: home)
        let both = try await ProgramImporter.apply(contents, into: church, choice: .keepBoth)
        #expect(both.backupURL == nil && both.presentationsKeptAsCopies >= 1)
        #expect(!FileManager.default.fileExists(atPath: rig.url("church", "Backups").path))
    }

    @Test func onlyTheNewestFiveBackupsOfThatKindAreKept() async throws {
        let rig = try Rig()
        let store = try rig.openStore("church")
        _ = try await store.createLibrary(name: "Songs")
        let folder = rig.url("church", "Backups")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: folder.appendingPathComponent("Library manual copy.sqlite"))
        try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        let dates = FixedDates()
        var made: [URL] = []
        for _ in 0..<7 { made.append(try await store.backUp(beforeImportAt: dates.tick())) }
        let ours = rig.listing(folder).filter { $0.contains("before import") }
        #expect(ours.count == 5)
        #expect(Set(ours) == Set(made.suffix(5).map(\.lastPathComponent)))
        #expect(rig.listing(folder).contains("notes.txt") && rig.listing(folder).contains("Library manual copy.sqlite"))
        // A backup is a whole library: it opens and has the data.
        let newest = try LibraryStore.open(at: try #require(made.last))
        #expect(try await newest.libraries().map(\.name) == ["Songs"])
        try newest.close()
    }

    @Test func twoBackupsInTheSameSecondDoNotOverwriteEachOther() async throws {
        let rig = try Rig()
        let store = try rig.openStore("church")
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try await store.backUp(beforeImportAt: at)
        let b = try await store.backUp(beforeImportAt: at)
        #expect(a != b && FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
    }

    @Test func ifTheBackupCannotBeWrittenNothingIsReplacedAndNothingIsCopied() async throws {
        let rig = try Rig()
        let (home, _, church, contents) = try await conflicted(rig)
        // A file where the Backups folder has to be.
        try Data("blocker".utf8).write(to: rig.url("church", "Backups"))
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        do {
            _ = try await ProgramImporter.apply(contents, into: church, choice: .useImported)
            Issue.record("the replace must not happen without a backup")
        } catch let error as ProgramPackageError {
            guard case .backupFailed = error else { Issue.record("expected backupFailed, got \(error)"); return }
            #expect(error.localizedDescription.contains("nothing was replaced"))
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folder)
        #expect(try await firstSlideText(church, home.songOne) == "First line of verse (church edit)")
    }

    // MARK: A live presentation

    @Test func aLivePresentationIsNotReplacedTheImportKeepsBothForThatOneAndSaysSo() async throws {
        let rig = try Rig()
        let (home, _, church, contents) = try await conflicted(rig)
        try await church.programWrite { db, _ in
            try db.execute(sql: "UPDATE slide SET primaryText = primaryText || ' (church edit)' WHERE presentationID = ?", arguments: [home.songTwo.uuidString])
        }
        let result = try await ProgramImporter.apply(contents, into: church, choice: .useImported,
                                                     live: ProgramLiveContext(livePresentationIDs: [home.songOne]))
        #expect(try await firstSlideText(church, home.songOne) == "First line of verse (church edit)", "the live one is untouched")
        #expect(try await firstSlideText(church, home.songTwo) == "Point one", "the other one is replaced")
        #expect(result.keptBecauseLive == ["Invented Song One"])
        #expect(result.presentationsReplaced == 1 && result.presentationsKeptAsCopies == 1)
        #expect(result.warnings.contains { $0.contains("Invented Song One") && $0.contains("live") })
        let library = try #require(try await church.libraries().first)
        let titles = try await church.presentations(in: library.id).map(\.title)
        #expect(titles.contains("Invented Song One (imported)"))
        #expect(!result.replacedPresentationIDs.contains(home.songOne))
    }

    // MARK: Space and size

    @Test func anImportThatWillNotFitIsRefusedBeforeAnythingIsCopied() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let needed = try await ProgramImporter.summarize(contents, into: church).mediaBytesToCopy
        #expect(needed > 0)
        // Exactly what is needed is not enough: a margin is left.
        let margin = ProgramImporter.spaceMargin(forBytes: needed)
        #expect(margin > 0)
        do {
            _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(freeSpace: { _ in needed + margin - 1 }))
            Issue.record("must be refused")
        } catch let error as ProgramPackageError {
            guard case .notEnoughSpace(let n, let available) = error else { Issue.record("expected notEnoughSpace, got \(error)"); return }
            #expect(n == needed + margin && available == needed + margin - 1)
            #expect(error.localizedDescription.contains("not enough free space") && error.localizedDescription.contains("Nothing was imported"))
        }
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folder)
        // With the margin it goes through.
        _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(freeSpace: { _ in needed + margin }))
        #expect(try await rowCounts(church)["presentation"] == 2)
    }

    @Test func aFileAlreadyThereNeedsNoSpaceAndAnUnknownFreeSpaceDoesNotBlock() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let contents = try ProgramPackageContents.open(package)
        _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(freeSpace: { _ in nil }))
        let again = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(freeSpace: { _ in 0 }))
        #expect(again.mediaFilesCopied == 0)
    }

    @Test func aCopyStopsAsSoonAsAFileIsBiggerThanTheManifestSaysAndLeavesNothing() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let document = try JSONDecoder().decode(ProgramDocument.self, from: Data(contentsOf: package.appendingPathComponent("program.json")))
        let big = try #require(document.media.first { $0.status == .included && $0.size == 5_000 })
        // The file grew after the manifest was written.
        let handle = try FileHandle(forWritingTo: package.appendingPathComponent(big.file))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(repeating: 7, count: 100_000))
        try handle.close()
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let copied = ByteCounter()
        let contents = try ProgramPackageContents.open(package)
        do {
            _ = try await ProgramImporter.apply(contents, into: church,
                                                hooks: ProgramImportHooks(chunkSize: 1_024, onChunk: { copied.add($0) }))
            Issue.record("a file bigger than the manifest says must be refused")
        } catch let error as ProgramPackageError {
            guard case .mediaDamaged = error else { Issue.record("expected mediaDamaged, got \(error)"); return }
        }
        #expect(copied.total <= 5_000 + 1_024 + 4 * 2_000, "no more than the limit plus one chunk of this file was read (other files are small)")
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folder)
    }

    @Test func theChunkedCopyWritesTheSameBytesAndStopsAtItsLimit() throws {
        let rig = try Rig()
        let data = rig.bytes(seed: 9, count: 1_000)
        let source = try rig.write(data, to: rig.url("src.bin"))
        let target = rig.url("dst.bin")
        let reported = ByteCounter()
        let digest = try ProgramFiles.chunkedCopy(from: source, to: target, chunkSize: 64, limit: 1_000, isCancelled: { false }) { reported.add($0) }
        let copiedData = try Data(contentsOf: target)
        #expect(digest == sha256(data) && copiedData == data && reported.total == 1_000)

        let limited = rig.url("limited.bin")
        let seen = ByteCounter()
        #expect(throws: ProgramPackageError.self) {
            try ProgramFiles.chunkedCopy(from: source, to: limited, chunkSize: 64, limit: 100, isCancelled: { false }) { seen.add($0) }
        }
        #expect(seen.total <= 100, "nothing past the limit is written: \(seen.total)")
    }

    @Test func aCancelInsideACopyLeavesNothingBehind() async throws {
        let rig = try Rig()
        let home = try await HomeProgram.make(rig)
        let package = try await home.export()
        let church = try rig.openStore("church")
        let before = try await rowCounts(church)
        let folder = rig.listing(rig.url("church"))
        let contents = try ProgramPackageContents.open(package)
        let polls = Counter()
        // Cancel in the middle of the third file's copy: the chunk size is tiny, so polls happen inside each file.
        let cancelled: @Sendable () -> Bool = { polls.next() > 40 }
        do {
            _ = try await ProgramImporter.apply(contents, into: church, hooks: ProgramImportHooks(chunkSize: 128), isCancelled: cancelled)
            Issue.record("must be cancelled")
        } catch let error as ProgramPackageError {
            #expect(error == .cancelled)
        }
        #expect(polls.count > 40)
        #expect(try await rowCounts(church) == before)
        #expect(rig.listing(rig.url("church")) == folder)
    }
}
