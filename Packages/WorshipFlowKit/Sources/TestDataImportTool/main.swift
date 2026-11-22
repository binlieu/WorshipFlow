// TESTDATA-001: wf-test-data-import --library <folder or Library.sqlite> --test-data <TestData folder> [--create-library] [--dry-run]
// Adds the synthetic songs and background pictures made by scripts/make-test-data.sh to a library, through the Persistence API.
import Foundation
import TestDataKit

let usage = """
usage: wf-test-data-import --library <folder or Library.sqlite> --test-data <TestData folder> [--create-library] [--dry-run] [--force-unchecked] [--report]
  --report only reads the library back through the Persistence API and prints what it holds.
  Adds the songs (library "Performance test", one transaction) and the pictures (media bin, one transaction). Safe to repeat.
  Refuses when the library is open in another program, when it cannot be told whether it is (lsof missing or failing; --force-unchecked
  goes on anyway), when it needs a schema migration, or when the file does not exist (unless --create-library). An existing library is
  copied beside itself (file, -wal, -shm) before the first write; the copy's name is printed. The bin keeps absolute paths: leave the TestData folder where it is.
"""

var library: String?, testData: String?, create = false, dry = false, report = false, force = false
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--library": library = args.isEmpty ? nil : args.removeFirst()
    case "--test-data": testData = args.isEmpty ? nil : args.removeFirst()
    case "--create-library": create = true
    case "--dry-run": dry = true
    case "--report": report = true
    case "--force-unchecked": force = true
    case "--help", "-h": print(usage); exit(0)
    default: FileHandle.standardError.write(Data("unknown argument \(a)\n\(usage)\n".utf8)); exit(64)
    }
}
guard let library, let testData else { FileHandle.standardError.write(Data("--library and --test-data are required\n\(usage)\n".utf8)); exit(64) }

let file = TestDataImporter.libraryFile(from: library)
let options = ImportOptions(libraryFile: file, testData: URL(fileURLWithPath: testData).resolvingSymlinksInPath(), createLibrary: create, dryRun: dry, forceUnchecked: force)
if report {
    do {
        let c = try await TestDataImporter.readBack(libraryFile: file)
        print("libraries: \(c.libraries); \"Performance test\" songs: \(c.songs); slides: \(c.slides) (\(c.sectionedSlides) in a named section, \(c.secondaryLanguageSlides) with a second language); bin images: \(c.binImages); schema: \(c.lastStep) (\(c.schemaSteps) steps)")
        exit(0)
    } catch { FileHandle.standardError.write(Data("REFUSED: \(error.localizedDescription)\n".utf8)); exit(2) }
}
do {
    let r = try await TestDataImporter.run(options)
    print("library file:   \(file.path)")
    if r.dryRun {
        print("DRY RUN: nothing was opened or written. Would offer \(r.songsAdded) songs and \(r.imagesAdded) images.")
    } else {
        if let backup = r.backupFile { print("backup:         \(backup) (the library's files as they were before this run)") }
        print("library:        \"\(r.libraryName)\" (\(r.libraryCreated ? "created" : "already there"))")
        print("songs:          \(r.songsAdded) added, \(r.songsSkipped) skipped (title already in the library), \(r.slidesAdded) slides written")
        print("media bin:      \(r.imagesAdded) images added, \(r.imagesSkipped) skipped (path already in the bin); stored by absolute path, no bookmark")
        print("schema:         \(r.migrationsAfter.last ?? "?") (\(r.migrationsAfter.count) steps; before the run: \(r.migrationsBefore.count))")
    }
} catch {
    FileHandle.standardError.write(Data("REFUSED: \(error.localizedDescription)\n".utf8))
    exit(2)
}
