// TESTDATA-001: puts TestData/ into a library through the Persistence API: the songs as presentations in a library called
// "Performance test" (one transaction), the pictures into the media bin (one transaction). Running it again adds nothing.
import Foundation
import Domain
import Persistence

public struct ImportOptions: Sendable {
    public var libraryFile: URL
    public var testData: URL
    public var libraryName = "Performance test"
    /// Allow a library file that does not exist yet (a scratch library). Without it a missing file is refused, so a mistyped path never
    /// makes a new empty library somewhere else.
    public var createLibrary = false
    public var dryRun = false
    /// FIX-T item 7 (L1): go on although nobody could say whether another program has the library open (`lsof` missing or failing). Without
    /// it an existing library is refused in that case: "no answer" is not "free".
    public var forceUnchecked = false
    public init(libraryFile: URL, testData: URL, createLibrary: Bool = false, dryRun: Bool = false, forceUnchecked: Bool = false) {
        self.libraryFile = libraryFile; self.testData = testData; self.createLibrary = createLibrary; self.dryRun = dryRun
        self.forceUnchecked = forceUnchecked
    }
}

public struct ImportRefusal: Error, Equatable, Sendable, LocalizedError {
    public var message: String
    public var errorDescription: String? { message }
}

public struct ImportReport: Equatable, Sendable {
    public var libraryName: String
    public var libraryCreated: Bool
    public var songsAdded: Int
    public var songsSkipped: Int
    public var slidesAdded: Int
    public var imagesAdded: Int
    public var imagesSkipped: Int
    public var migrationsBefore: [String]
    public var migrationsAfter: [String]
    public var dryRun: Bool
    /// FIX-T item 7 (L1): the copy of the library's files made beside it before anything was written (nil for a new library or a dry run).
    public var backupFile: String? = nil
}

public enum TestDataImporter {
    /// `<folder>/Library.sqlite` when `path` is a folder (or has no extension); else the file itself. The app's own `--library`
    /// takes the file path, so both spellings work here.
    public static func libraryFile(from path: String) -> URL {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let url = URL(fileURLWithPath: path)
        if (exists && isDirectory.boolValue) || (!exists && url.pathExtension.isEmpty) {
            return url.appendingPathComponent(LibraryLocation.fileName)
        }
        return url
    }

    public static func run(_ options: ImportOptions, usage: LibraryUsageChecking = LsofUsageChecker(),
                           ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) async throws -> ImportReport {
        let file = options.libraryFile
        let exists = FileManager.default.fileExists(atPath: file.path)
        if !exists && !options.createLibrary {
            throw ImportRefusal(message: "There is no library file at \(file.path). Nothing was written. Pass --create-library to make a new one.")
        }
        switch usage.usage(of: file.path, ignoring: ownPID) {
        case .free: break
        case .unknown:
            // FIX-T item 7 (L1): nothing could be learned (lsof is missing or failed, and there is no -wal file). Not the same as free.
            if exists && !options.forceUnchecked {
                throw ImportRefusal(message: "Could not tell whether another program (WorshipFlow) has the library open: lsof is missing or did not answer. Nothing was written. Quit WorshipFlow and run this again with --force-unchecked.")
            }
        case .inUse(let holders):
            let names = holders.map { "\($0.command) (pid \($0.pid))" }.joined(separator: ", ")
            throw ImportRefusal(message: "The library is open in another program: \(names). Quit it, then run this again. Nothing was written.")
        case .suspected(let what):
            throw ImportRefusal(message: "\(what) holds changes that are not yet in the library, so WorshipFlow may be running (or was killed). Quit it and open it once, then run this again. Nothing was written.")
        }
        if exists {
            let pending = LibraryStore.pendingMigrations(at: file)
            if !pending.isEmpty {
                throw ImportRefusal(message: "The library needs \(pending.count) schema step(s) this tool will not apply (first: \(pending.first ?? "")). Open it once with the current WorshipFlow, quit, then run this again. Nothing was written.")
            }
        }
        let songs = try SongFiles.read(folder: options.testData.appendingPathComponent("songs", isDirectory: true))
        let images = try ImageFiles.specs(testData: options.testData)
        guard !songs.isEmpty || !images.isEmpty else {
            throw ImportRefusal(message: "No songs and no images under \(options.testData.path). Run scripts/make-test-data.sh first.")
        }
        if options.dryRun {
            return ImportReport(libraryName: options.libraryName, libraryCreated: false, songsAdded: songs.count, songsSkipped: 0, slidesAdded: 0,
                                imagesAdded: images.count, imagesSkipped: 0, migrationsBefore: [], migrationsAfter: [], dryRun: true)
        }
        // FIX-T item 7 (L1): an existing library is copied (the file and its -wal and -shm) beside itself before the first write.
        var backup: URL?
        if exists { backup = try Self.backUp(file) }
        let store = try LibraryStore.open(at: file)
        defer { try? store.close() }
        let before = try await store.appliedMigrations()
        let batch = try await store.addSongBatch(toLibraryNamed: options.libraryName, songs: SongFiles.specs(songs))
        let media = try await store.addMediaAssets(images)
        let after = try await store.appliedMigrations()
        if exists, before != after { throw ImportRefusal(message: "The schema version changed during the import. This must not happen.") }
        return ImportReport(libraryName: options.libraryName, libraryCreated: batch.libraryCreated, songsAdded: batch.added.count,
                            songsSkipped: batch.skippedTitles.count, slidesAdded: batch.slidesAdded, imagesAdded: media.added.count,
                            imagesSkipped: media.existing.count, migrationsBefore: before, migrationsAfter: after, dryRun: false,
                            backupFile: backup?.path)
    }

    /// Copies `<name>.sqlite` and its `-wal` and `-shm` to `<name>-before-test-data-<date and time>.sqlite` (and the same suffixes) in the same
    /// folder. The names are new each time; an existing file is never overwritten. Throws a refusal (nothing written) if any copy fails.
    static func backUp(_ file: URL, now: Date = Date()) throws -> URL {
        let manager = FileManager.default
        let stamp: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyyMMdd-HHmmss"
            return f.string(from: now)
        }()
        let base = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        var target: URL
        var n = 0
        repeat {
            let suffix = n == 0 ? "" : "-\(n)"
            target = file.deletingLastPathComponent().appendingPathComponent("\(base)-before-test-data-\(stamp)\(suffix)" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        } while manager.fileExists(atPath: target.path) || manager.fileExists(atPath: target.path + "-wal") || manager.fileExists(atPath: target.path + "-shm")
        var made: [URL] = []
        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: file.path + suffix)
                guard manager.fileExists(atPath: source.path) else { continue }
                let copy = URL(fileURLWithPath: target.path + suffix)
                try manager.copyItem(at: source, to: copy)
                made.append(copy)
            }
        } catch {
            for copy in made { try? manager.removeItem(at: copy) }
            throw ImportRefusal(message: "Could not copy the library to a backup beside it (\(error.localizedDescription)). Nothing was written.")
        }
        return target
    }

    /// What the library holds now, read back through the Persistence API (nothing is written; the file must be up to date).
    public struct Counts: Equatable, Sendable {
        public var libraries: Int, songs: Int, slides: Int, secondaryLanguageSlides: Int, sectionedSlides: Int, binImages: Int, schemaSteps: Int, lastStep: String
    }

    public static func readBack(libraryFile: URL, libraryName: String = "Performance test") async throws -> Counts {
        guard FileManager.default.fileExists(atPath: libraryFile.path) else { throw ImportRefusal(message: "There is no library file at \(libraryFile.path).") }
        guard LibraryStore.pendingMigrations(at: libraryFile).isEmpty else { throw ImportRefusal(message: "The library needs a schema step this tool will not apply.") }
        let store = try LibraryStore.open(at: libraryFile)
        defer { try? store.close() }
        let libraries = try await store.libraries()
        var songs = 0, slides = 0, secondary = 0, sectioned = 0
        for library in libraries where library.name == libraryName {
            for presentation in try await store.presentations(in: library.id) {
                songs += 1
                for slide in try await store.slides(of: presentation.id) {
                    slides += 1
                    if slide.content.secondary != nil { secondary += 1 }
                    if slide.groupID != nil { sectioned += 1 }
                }
            }
        }
        let steps = try await store.appliedMigrations()
        return Counts(libraries: libraries.count, songs: songs, slides: slides, secondaryLanguageSlides: secondary, sectionedSlides: sectioned,
                      binImages: try await store.mediaAssets(kind: .image).count, schemaSteps: steps.count, lastStep: steps.last ?? "?")
    }
}
