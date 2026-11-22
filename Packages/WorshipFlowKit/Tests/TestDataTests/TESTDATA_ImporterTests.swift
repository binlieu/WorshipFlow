// TESTDATA-001: the performance-test loader. Synthetic songs and 1x1 stand-in pictures in a temporary folder; no real library is touched.
import Testing
import Foundation
import Domain
import Persistence
@testable import TestDataKit

private struct Holder: LibraryUsageChecking {
    var answer: LibraryUsage
    func usage(of path: String, ignoring pid: Int32) -> LibraryUsage { answer }
}

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("testdata-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A PNG header with the given size (enough for the loader, which reads only the header).
private func pngHeader(width: Int, height: Int) -> Data {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
    for v in [width, height] { bytes += [UInt8(v >> 24 & 255), UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255)] }
    return Data(bytes)
}

/// A TestData folder with `songs` songs (the first is bilingual) and one solid and one gradient picture.
private func makeTestData(songs: Int = 3) throws -> URL {
    let root = try scratch()
    let songDir = root.appendingPathComponent("songs"), solid = root.appendingPathComponent("backgrounds/solid"), gradient = root.appendingPathComponent("backgrounds/gradient")
    for dir in [songDir, solid, gradient] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    for i in 1...songs {
        let title = String(format: "Test Song %03d - Synthetic", i)
        try "Verse 1\nOne \(i) a\nOne \(i) b\nOne \(i) c\nOne \(i) d\n\nChorus\nTwo \(i) a\nTwo \(i) b\n".write(to: songDir.appendingPathComponent(title + ".txt"), atomically: true, encoding: .utf8)
        if i == 1 {
            try "Câu 1\nMột a\nMột b\nMột c\nMột d\n\nĐiệp khúc\nHai a\nHai b\n".write(to: songDir.appendingPathComponent(title + ".vi.txt"), atomically: true, encoding: .utf8)
        }
    }
    try pngHeader(width: 1920, height: 1080).write(to: solid.appendingPathComponent("solid-001-deep-blue.png"))
    try pngHeader(width: 1920, height: 1080).write(to: gradient.appendingPathComponent("gradient-001-blue-to-violet.png"))
    return root
}

@Suite struct TestDataImporterTests {
    @Test func songFilesBecomeSectionedSlidesWithTheSecondLanguagePaired() throws {
        let data = try makeTestData()
        let songs = try SongFiles.read(folder: data.appendingPathComponent("songs"))
        #expect(songs.map(\.title) == ["Test Song 001 - Synthetic", "Test Song 002 - Synthetic", "Test Song 003 - Synthetic"])
        #expect(songs[0].secondary != nil && songs[1].secondary == nil)
        let first = SongFiles.specs(songs)[0].results
        #expect(first.map(\.sectionName) == ["Verse 1", "Verse 1", "Chorus"])      // 2 lines per slide, like the import sheet
        #expect(first[0].content.secondary == "Một a\nMột b")
        #expect(first[2].content.primary == "Two 1 a\nTwo 1 b" && first[2].content.secondary == "Hai a\nHai b")
    }

    @Test func importAddsEverythingOnceAndASecondRunAddsNothing() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        let options = ImportOptions(libraryFile: file, testData: data, createLibrary: true)
        let one = try await TestDataImporter.run(options, usage: Holder(answer: .free))
        #expect(one.libraryCreated && one.songsAdded == 3 && one.songsSkipped == 0 && one.slidesAdded == 9)
        #expect(one.imagesAdded == 2 && one.imagesSkipped == 0)
        let two = try await TestDataImporter.run(options, usage: Holder(answer: .free))
        #expect(!two.libraryCreated && two.songsAdded == 0 && two.songsSkipped == 3 && two.slidesAdded == 0)
        #expect(two.imagesAdded == 0 && two.imagesSkipped == 2)
        #expect(one.migrationsBefore == two.migrationsAfter && one.migrationsAfter == two.migrationsAfter)

        let store = try LibraryStore.open(at: file)
        let libraries = try await store.libraries().filter { $0.name == "Performance test" }
        #expect(libraries.count == 1)
        let presentations = try await store.presentations(in: libraries[0].id)
        #expect(presentations.count == 3 && presentations.allSatisfy { $0.kind == .song })
        let slides = try await store.slides(of: presentations[0].id)
        #expect(slides.count == 3 && slides.allSatisfy { $0.groupID != nil })
        let bin = try await store.mediaAssets(kind: .image)
        #expect(bin.count == 2 && bin.allSatisfy { $0.pixelWidth == 1920 && $0.pixelHeight == 1080 && $0.bookmark == nil })
        #expect(try await store.search("synthetic", limit: 50).count == 3)
        try store.close()
    }

    @Test func aMissingLibraryIsRefusedUnlessCreationIsAsked() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        await #expect(throws: ImportRefusal.self) {
            _ = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Holder(answer: .free))
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func aLibraryOpenInAnotherProgramIsRefusedAndLeftAlone() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        try LibraryStore.open(at: file).close()
        let sizeBefore = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        for answer in [LibraryUsage.inUse([LibraryHolder(pid: 1, command: "WorshipFlow")]), .suspected("Library.sqlite-wal")] {
            await #expect(throws: ImportRefusal.self) {
                _ = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Holder(answer: answer))
            }
        }
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int == sizeBefore)
    }

    @Test func aLibraryThatNeedsAMigrationIsRefusedNotMigrated() async throws {
        let data = try makeTestData()
        let file = try scratch().appendingPathComponent("Library.sqlite")
        let old = try LibraryStore.open(at: file, migratingUpTo: "v1")
        let applied = try await old.appliedMigrations()
        try old.close()
        #expect(!LibraryStore.pendingMigrations(at: file).isEmpty)
        await #expect(throws: ImportRefusal.self) {
            _ = try await TestDataImporter.run(ImportOptions(libraryFile: file, testData: data), usage: Holder(answer: .free))
        }
        let reopened = try LibraryStore.open(at: file, migratingUpTo: "v1")
        #expect(try await reopened.appliedMigrations() == applied)
        try reopened.close()
    }

    @Test func aBatchWithAnEmptySongWritesNothingAtAll() async throws {
        let store = try LibraryStore.inMemory()
        let good = LibraryStore.SongSpec(title: "A", results: [ReflowResult(sectionName: nil, content: SlideContent(primary: "x", secondary: nil))])
        let bad = LibraryStore.SongSpec(title: "B", results: [])
        await #expect(throws: StoreError.self) { _ = try await store.addSongBatch(toLibraryNamed: "Performance test", songs: [good, bad]) }
        #expect(try await store.libraries().isEmpty)
    }

    @Test func lsofOutputNamesTheOtherProcessButNotThisOne() {
        let out = "p100\ncWorshipFlow\np200\ncwf-test-data-import\n"
        #expect(LsofUsageChecker.parse(out, ignoring: 200) == .inUse([LibraryHolder(pid: 100, command: "WorshipFlow")]))
        #expect(LsofUsageChecker.parse(out, ignoring: 100) != .free)
        #expect(LsofUsageChecker.parse("p200\ncx\n", ignoring: 200) == .free)
    }
}
