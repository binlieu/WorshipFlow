// FIX-T item 7 (L1, TESTDATA-001): the test-data loader does not treat "lsof could not say" as "free", and it copies an existing library beside
// itself before the first write. No real library is touched: everything is in a temporary folder.
import Testing
import Foundation
import Domain
import Persistence
@testable import TestDataKit

private struct Fixed: LibraryUsageChecking {
    var answer: LibraryUsage
    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage { answer }
}

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("fixt-testdata-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func pngHeader() -> Data {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
    for v in [1920, 1080] { bytes += [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
    return Data(bytes)
}

private func makeTestData() throws -> URL {
    let root = try scratch()
    let songs = root.appendingPathComponent("songs"), solid = root.appendingPathComponent("backgrounds/solid")
    for dir in [songs, solid] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    try "Verse 1\nOne a\nOne b\n".write(to: songs.appendingPathComponent("Test Song 001 - Synthetic.txt"), atomically: true, encoding: .utf8)
    try pngHeader().write(to: solid.appendingPathComponent("solid-001-deep-blue.png"))
    return root
}

private func siblings(of file: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path).sorted()
}

@Suite struct FIXT_ImporterSafetyTests {
    @Test func anExistingLibraryIsRefusedWhenNobodyCouldSayWhetherItIsInUse() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try LibraryStore.open(at: file).close()
        let bytes = try Data(contentsOf: file)
        let listing = try siblings(of: file)
        do {
            _ = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Fixed(answer: .unknown))
            Issue.record("an unusable lsof must not count as free")
        } catch let refusal as ImportRefusal {
            #expect(refusal.message.contains("--force-unchecked") && refusal.message.contains("Nothing was written"))
        }
        #expect(try Data(contentsOf: file) == bytes, "the library was not touched")
        #expect(try siblings(of: file) == listing, "no backup and no other file was made either")
    }

    @Test func forceUncheckedGoesOnAnyway() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try LibraryStore.open(at: file).close()
        let r = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data, forceUnchecked: true), usage: Fixed(answer: .unknown))
        #expect(r.songsAdded == 1)
    }

    @Test func aNewLibraryNeedsNoAnswerBecauseNobodyCanHaveItOpen() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        let r = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data, createLibrary: true), usage: Fixed(answer: .unknown))
        #expect(r.libraryCreated && r.backupFile == nil)
    }

    @Test func anExistingLibraryIsCopiedBesideItselfBeforeTheFirstWriteAndTheNameIsReported() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        let store = try LibraryStore.open(at: file)
        _ = try await store.createLibrary(name: "Songs")
        try store.close()
        let before = try Data(contentsOf: file)
        let r = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Fixed(answer: .free))
        let backup = try #require(r.backupFile)
        #expect(URL(fileURLWithPath: backup).deletingLastPathComponent() == file.deletingLastPathComponent())
        #expect(URL(fileURLWithPath: backup).lastPathComponent.hasPrefix("Library-before-test-data-"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: backup)) == before, "the copy is the library as it was before the run")
        let live = try LibraryStore.open(at: file)
        #expect(try await live.libraries().contains { $0.name == "Performance test" }, "and the library itself was loaded")
        try live.close()
        // The copy opens as a library and holds none of the loaded songs.
        let copy = try LibraryStore.open(at: URL(fileURLWithPath: backup))
        #expect(try await copy.libraries().filter { $0.name == "Performance test" }.isEmpty)
        try copy.close()
    }

    @Test func aDryRunAndARefusedRunMakeNoCopy() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try LibraryStore.open(at: file).close()
        let listing = try siblings(of: file)
        let dry = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data, dryRun: true), usage: Fixed(answer: .free))
        #expect(dry.backupFile == nil)
        await #expect(throws: ImportRefusal.self) {
            _ = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Fixed(answer: .inUse([LibraryHolder(pid: 1, command: "WorshipFlow")])))
        }
        #expect(try siblings(of: file) == listing)
    }

    @Test func twoRunsInTheSameSecondDoNotOverwriteEachOthersCopy() throws {
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try Data("a".utf8).write(to: file)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let one = try TestDataImporter.backUp(file, now: now)
        try Data("b".utf8).write(to: file)
        let two = try TestDataImporter.backUp(file, now: now)
        #expect(one != two)
        #expect(try Data(contentsOf: one) == Data("a".utf8) && Data(contentsOf: two) == Data("b".utf8))
    }

    @Test func theCompanionFilesAreCopiedToo() throws {
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try Data("main".utf8).write(to: file)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: file.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: file.path + "-shm"))
        let copy = try TestDataImporter.backUp(file)
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-wal")) == Data("wal".utf8))
        #expect(try Data(contentsOf: URL(fileURLWithPath: copy.path + "-shm")) == Data("shm".utf8))
    }
}
