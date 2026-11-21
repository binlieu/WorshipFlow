// LIB-004b: the three commands end to end through `ImportToolCLI.run`, with a fake MySQL server and a fake usage
// checker. Libraries and files are in temporary folders and deleted. Synthetic text and the KJV fixture only.
import Testing
import Foundation
import ScriptureEngine
@_spi(ScriptureStore) @testable import Persistence
@testable import ScriptureStore

private typealias F = StoreFixtures

@Suite struct ToolCLITests {
    private func server() -> FakeMySQLServer {
        FakeMySQLServer(versions: [
            .init(id: 1, code: "VI1934", name: "Vietnamese test", language: "vi", verses: ToolFixtures.smallVerses()),
            .init(id: 2, code: "EN", name: nil, language: nil, verses: Array(ToolFixtures.smallVerses().prefix(3))),
            .init(id: 3, code: "EMPTY", name: "No verses", language: nil, verses: []),
        ], bookNames: [1: "Genesis", 43: "John", 66: "Revelation"])
    }
    private let connect = ["--mysql", "--host", "localhost", "--user", "root", "--database", "bible"]

    // MARK: Help and usage

    @Test(arguments: [["--help"], ["help"], ["-h"], ["inspect", "--help"], ["export", "--help"], ["import", "--help"], ["export", "--database", "x", "-h"]])
    func helpWorksForEverySubcommandAndExitsZero(_ args: [String]) async {
        let run = await ToolHarness.run(args)
        #expect(run.status == 0 && run.err.isEmpty)
        #expect(run.out.contains("Usage") || run.out.contains("wf-bible-import"))
        #expect(!run.out.lowercased().contains("--password") || run.out.contains("never"))
        #expect(run.madeRunners.isEmpty)
    }

    @Test func helpExamplesNeverShowAPassword() {
        for text in [Help.general, Help.inspect, Help.export, Help.importCommand] {
            #expect(!text.contains("--password") && !text.contains("-p "))
        }
        #expect(Help.export.contains("MYSQL_PWD=...") && Help.inspect.contains("MYSQL_PWD=..."))
    }

    @Test func usageMistakesExitTwoWithOneLine() async {
        let cases: [([String], String)] = [
            ([], "no command"), (["frobnicate"], "unknown command"), (["inspect"], "--database is required"),
            (["inspect", "--database", "x", "--port", "99999"], "--port"), (["export", "--database", "x"], "--version is required"),
            (["export", "--database", "x", "--version", "V"], "--out is required"), (["export", "--database", "x", "--version", "V", "--out", "/tmp/x.json"], "--language is required"),
            (["import"], "--library is required"), (["import", "--library", "/tmp/x"], "--file is required"),
            (["inspect", "--database", "x", "--password", "secret"], "never accepted"), (["inspect", "--database", "x", "-psecret"], "never accepted"),
            (["inspect", "--database", "x", "--map", "nonsense"], "--map"), (["inspect", "--database", "x", "--map", "verses.nope=x"], "--map role"),
            (["export", "--database", "x", "--version", "V", "--out", "/tmp/x.json", "--language", "vi", "--owner-approval-date", "2026-11-20"], "--owner-approved"),
            (["export", "--database", "x", "--version", "V", "--out", "/tmp/x.json", "--language", "vi", "--owner-approved", "--owner-approval-date", "yesterday"], "2026-11-20"),
        ]
        for (args, fragment) in cases {
            let run = await ToolHarness.run(args)
            #expect(run.status == 2, "\(args)")
            #expect(run.err.contains(fragment), "\(args): \(run.err)")
            #expect(run.err.split(separator: "\n").count == 1, "\(args): \(run.err)")
            #expect(!run.err.contains("secret") && run.out.isEmpty)
        }
    }

    // MARK: Password handling

    @Test func thePasswordComesFromTheEnvironmentAndIsNeverPrinted() async {
        let run = await ToolHarness.run(["inspect"] + connect, server: server(), variables: ["MYSQL_PWD": "s3cr3t-pw"], interactive: true, typedPassword: "typed")
        #expect(run.status == 0)
        #expect(run.madeRunners.first?.1 == "s3cr3t-pw")
        #expect(!run.out.contains("s3cr3t-pw") && !run.err.contains("s3cr3t-pw") && !run.err.contains("PROMPT"))
    }

    @Test func withoutTheEnvironmentATerminalUserIsPromptedAndANonTerminalIsNot() async {
        let asked = await ToolHarness.run(["inspect"] + connect, server: server(), variables: [:], interactive: true, typedPassword: "typed-pw")
        #expect(asked.madeRunners.first?.1 == "typed-pw" && asked.err.contains("PROMPT: MySQL password for root@localhost"))
        #expect(!asked.out.contains("typed-pw") && !asked.err.contains("typed-pw"))
        let piped = await ToolHarness.run(["inspect"] + connect, server: server(), variables: [:], interactive: false, typedPassword: "typed-pw")
        #expect(piped.madeRunners.first?.1 == nil && !piped.err.contains("PROMPT"))
        let declined = await ToolHarness.run(["inspect", "--no-password"] + connect, server: server(), variables: [:], interactive: true, typedPassword: "typed-pw")
        #expect(declined.madeRunners.first?.1 == nil && !declined.err.contains("PROMPT"))
    }

    // MARK: inspect

    @Test func inspectPrintsAVersionTableAndNoVerseText() async {
        let run = await ToolHarness.run(["inspect"] + connect, server: server())
        #expect(run.status == 0 && run.err.isEmpty)
        let lines = run.out.split(separator: "\n").map(String.init)
        #expect(lines[0] == "Database bible: 3 versions")
        #expect(lines[1].hasPrefix("CODE") && lines[1].contains("NAME") && lines[1].contains("LANGUAGE") && lines[1].hasSuffix("VERSES"))
        #expect(lines.contains { $0.hasPrefix("VI1934") && $0.contains("Vietnamese test") && $0.contains("vi") && $0.hasSuffix("6") })
        #expect(lines.contains { $0.hasPrefix("EN") && $0.hasSuffix("3") })
        #expect(lines.contains { $0.hasPrefix("EMPTY") && $0.hasSuffix("0") })
        #expect(!run.out.contains("synthetic") && !run.out.contains("second line"))
        #expect(run.madeRunners.first?.0 == MySQLConnection(host: "localhost", port: nil, user: "root", database: "bible", socket: nil, binary: nil))
    }

    @Test func inspectSchemaShowsHowTheDatabaseWasRead() async {
        let run = await ToolHarness.run(["inspect", "--schema", "--map", "verses.text=text"] + connect, server: server())
        #expect(run.out.contains("verses table: verses (version: version_id = versions.id") && run.out.contains("text: text"))
    }

    @Test func aFailingClientIsOneLineAndExitOne() async {
        let broken = server()
        broken.failure = .failed(status: 1, message: "ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)")
        let run = await ToolHarness.run(["inspect"] + connect, server: broken, variables: ["MYSQL_PWD": "s3cr3t-pw"])
        #expect(run.status == 1)
        #expect(run.err == "wf-bible-import: the mysql client exited with status 1: ERROR 1045 (28000): Access denied for user 'root'@'localhost' (using password: YES)")
        #expect(!run.err.contains("s3cr3t-pw") && !run.err.contains("--execute") && run.out.isEmpty)
        let missing = server()
        missing.failure = .binaryNotFound("mysql")
        let gone = await ToolHarness.run(["inspect", "--mysql-bin", "mysql"] + connect, server: missing)
        #expect(gone.status == 1 && gone.err.contains("not found") && gone.err.contains("--mysql-bin"))
    }

    // MARK: export

    @Test func exportWritesAFileTheLoaderAcceptsWithTextExact() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("sub/VI.json")
        let run = await ToolHarness.run(["export"] + connect + ["--version", "VI1934", "--id", "VI1925", "--language", "vi", "--public-domain",
                                                                "--owner-approved", "--owner-approval-date", "2026-11-20", "--out", out.path],
                                        server: server(), variables: ["MYSQL_PWD": "s3cr3t-pw"])
        #expect(run.status == 0, "\(run.err)")
        #expect(run.out.contains("Wrote \(out.path)") && run.out.contains("6 verses in 3 books"))
        #expect(!run.out.contains("s3cr3t-pw") && !run.err.contains("s3cr3t-pw"))
        let loaded = try TranslationLoader.load(from: Data(contentsOf: out))
        let t = loaded.translation
        #expect(t.metadata.id == "VI1925" && t.metadata.language == "vi" && t.metadata.isPublicDomain && t.metadata.copyright == "not stated")
        #expect(t.metadata.ownerApproval == OwnerApproval(approved: true, date: "2026-11-20", note: nil))
        #expect(t.text(for: VerseRef(book: BookID("GEN"), chapter: 1, verse: 1)) == ToolFixtures.nasty.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(Array((t.text(for: VerseRef(book: BookID("GEN"), chapter: 1, verse: 2)) ?? "").unicodeScalars) == Array(ToolFixtures.stacked.unicodeScalars))
        #expect(loaded.report.verseCount == 6)
        // No temporary file is left behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("sub").path) == ["VI.json"])
    }

    @Test func aVersionThatDoesNotExistListsWhatDoes() async {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("x.json")
        let run = await ToolHarness.run(["export"] + connect + ["--version", "NOPE", "--language", "vi", "--out", out.path], server: server())
        #expect(run.status == 1)
        #expect(run.err == "wf-bible-import: the database has no version with the code “NOPE”. Versions found: VI1934, EN, EMPTY.")
        #expect(!FileManager.default.fileExists(atPath: out.path))
        // The match ignores case when the exact code is not there.
        let loose = await ToolHarness.run(["export"] + connect + ["--version", "vi1934", "--language", "vi", "--out", out.path], server: server())
        #expect(loose.status == 0)
    }

    @Test func aVersionWithNoVersesWritesNothing() async {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("x.json")
        let run = await ToolHarness.run(["export"] + connect + ["--version", "EMPTY", "--language", "vi", "--out", out.path], server: server())
        #expect(run.status == 1 && run.err.contains("has no verses"))
        #expect(!FileManager.default.fileExists(atPath: out.path))
        let drained = server()
        drained.rawOverride["FROM `verses` WHERE"] = ""
        let empty = await ToolHarness.run(["export"] + connect + ["--version", "VI1934", "--language", "vi", "--out", out.path], server: drained)
        #expect(empty.status == 1 && empty.err.contains("no usable verses"))
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func anExistingOutputFileIsNotReplacedUnlessAsked() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("x.json")
        try "keep me".write(to: out, atomically: true, encoding: .utf8)
        let args = ["export"] + connect + ["--version", "VI1934", "--language", "vi", "--out", out.path]
        let refused = await ToolHarness.run(args, server: server())
        #expect(refused.status == 3 && refused.err.contains("--overwrite"))
        #expect(refused.madeRunners.isEmpty)                                   // refused before any database work
        #expect(try String(contentsOf: out, encoding: .utf8) == "keep me")
        let replaced = await ToolHarness.run(args + ["--overwrite"], server: server())
        #expect(replaced.status == 0)
        #expect((try String(contentsOf: out, encoding: .utf8)).contains("worshipflow.translation"))
    }

    @Test func exportReportsProblemsInTheData() async {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = server()
        bad.versions[0].verses += [RawVerse(bookOrder: 1, chapter: 1, verse: 1, text: "twice"), RawVerse(bookOrder: 1, chapter: 5, verse: 1, text: " ")]
        let run = await ToolHarness.run(["export"] + connect + ["--version", "VI1934", "--language", "vi", "--out", dir.appendingPathComponent("x.json").path], server: bad)
        #expect(run.status == 0)
        #expect(run.out.contains("PROBLEM") && run.out.contains("1 verses are empty") && run.out.contains("Partial translation: 3 of 66"))
    }

    @Test func exportOverTheWholeCanonStaysFast() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = FakeMySQLServer(versions: [.init(id: 1, code: "SYN", name: "Synthetic", language: "en", verses: ToolFixtures.full(.kjv))])
        let out = dir.appendingPathComponent("syn.json")
        let clock = ContinuousClock()
        var run: ToolRun?
        let elapsed = await clock.measure { run = await ToolHarness.run(["export"] + connect + ["--version", "SYN", "--language", "en", "--out", out.path], server: big) }
        print("LIB-004b perf: export of 31,102 synthetic rows through the fake server (parse, validate, write): \(elapsed)")
        #expect(run?.status == 0)
        #expect(try TranslationLoader.load(from: Data(contentsOf: out)).report.verseCount == 31_102)
        #expect(elapsed < .seconds(30))
    }

    // MARK: import

    private func library(in dir: URL, create: Bool = true) throws -> URL {
        let url = dir.appendingPathComponent("Library.sqlite")
        if create { let store = try LibraryStore.open(at: url); try store.close() }
        return url
    }
    private func jsonFile(in dir: URL, code: String = "kjv") throws -> URL {
        let url = dir.appendingPathComponent("\(code).json")
        try F.kjvFile(code: code).encoded().write(to: url)
        return url
    }
    private func translations(_ url: URL) async throws -> [StoredTranslation] {
        let library = try LibraryStore.open(at: url)
        defer { try? library.close() }
        return try await ScriptureStore(library: library).translations()
    }

    @Test func importLoadsAJSONFileIntoALibrary() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir), file = try jsonFile(in: dir)
        let run = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path])
        #expect(run.status == 0, "\(run.err)")
        #expect(run.out.contains("Imported kjv") && run.out.contains("11 verses"))
        #expect(try await translations(lib).map(\.code) == ["kjv"])
    }

    @Test func importingAgainIsRefusedUnlessReplaceIsGiven() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir), file = try jsonFile(in: dir)
        _ = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path])
        let before = try await translations(lib)
        let again = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path])
        #expect(again.status == 3 && again.err.contains("--replace") && again.err.contains("Nothing was changed"))
        #expect(try await translations(lib) == before)
        let replaced = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path, "--replace"])
        #expect(replaced.status == 0 && replaced.out.contains("Replaced kjv"))
        #expect(try await translations(lib).count == 1)
    }

    @Test func aLibraryThatLooksInUseIsRefusedAndLeftAlone() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir), file = try jsonFile(in: dir)
        let bytes = try Data(contentsOf: lib)
        let busy = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path],
                                         usage: .inUse([LibraryHolder(pid: 4242, command: "WORSHIPFLOW")]))
        #expect(busy.status == 3)
        #expect(busy.err.contains("WORSHIPFLOW (pid 4242)") && busy.err.contains("--force") && busy.err.contains("Quit"))
        #expect(try Data(contentsOf: lib) == bytes)
        let leftover = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path], usage: .suspected("Library.sqlite-wal"))
        #expect(leftover.status == 3 && leftover.err.contains("Library.sqlite-wal"))
        #expect(try Data(contentsOf: lib) == bytes)
        let forced = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path, "--force"], usage: .inUse([LibraryHolder(pid: 4242, command: "WORSHIPFLOW")]))
        #expect(forced.status == 0)
        #expect(try await translations(lib).count == 1)
        // "Unknown" (no lsof, no sidecar files) does not block: there is nothing to go on.
        let dir2 = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir2) }
        let lib2 = try library(in: dir2)
        #expect(await ToolHarness.run(["import", "--library", lib2.path, "--file", file.path], usage: .unknown).status == 0)
    }

    @Test func aFileThatIsNotALibraryIsNeverTouched() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try jsonFile(in: dir)
        // Not SQLite at all.
        let text = dir.appendingPathComponent("notes.sqlite")
        try "hello".write(to: text, atomically: true, encoding: .utf8)
        let a = await ToolHarness.run(["import", "--library", text.path, "--file", file.path])
        #expect(a.status == 3 && a.err.contains("does not look like a WorshipFlow library"))
        #expect(try String(contentsOf: text, encoding: .utf8) == "hello")
        // A real SQLite file of someone else's: no WorshipFlow tables may be added to it.
        let other = dir.appendingPathComponent("other.sqlite")
        let created = Process()
        created.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        created.arguments = [other.path, "CREATE TABLE contacts (name TEXT); INSERT INTO contacts VALUES ('x');"]
        try created.run(); created.waitUntilExit()
        let before = try Data(contentsOf: other)
        let b = await ToolHarness.run(["import", "--library", other.path, "--file", file.path])
        #expect(b.status == 3 && b.err.contains("no WorshipFlow tables"))
        #expect(try Data(contentsOf: other) == before)
    }

    @Test func aMissingLibraryIsAnErrorUnlessCreateIsGiven() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = try jsonFile(in: dir)
        let lib = dir.appendingPathComponent("typo/Library.sqlite")
        let run = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path])
        #expect(run.status == 1 && run.err.contains("does not exist") && run.err.contains("--create"))
        #expect(!FileManager.default.fileExists(atPath: lib.deletingLastPathComponent().path))
        let made = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path, "--create"])
        #expect(made.status == 0)
        #expect(try await translations(lib).count == 1)
    }

    @Test func dryRunChecksTheFileAndTouchesNoLibrary() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir), file = try jsonFile(in: dir)
        let bytes = try Data(contentsOf: lib)
        let run = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path, "--dry-run"], usage: .inUse([LibraryHolder(pid: 1, command: "x")]))
        #expect(run.status == 0 && run.out.contains("Dry run") && run.out.contains("11 verses"))
        #expect(try Data(contentsOf: lib) == bytes)
    }

    @Test func badFilesAreReportedInOneLineAndLeaveTheLibraryAlone() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir)
        let bytes = try Data(contentsOf: lib)
        let junk = dir.appendingPathComponent("junk.json"); try "{not json".write(to: junk, atomically: true, encoding: .utf8)
        let wrong = dir.appendingPathComponent("wrong.json"); try #"{"format":"something.else","version":1}"#.write(to: wrong, atomically: true, encoding: .utf8)
        let noVerses = dir.appendingPathComponent("none.json")
        try TranslationFile(metadata: F.kjvMetadata, books: ["GEN": ["1": ["1": " "]]]).encoded().write(to: noVerses)
        let text = dir.appendingPathComponent("a.txt"); try "plain".write(to: text, atomically: true, encoding: .utf8)
        for (path, fragment) in [(junk.path, "not valid JSON"), (wrong.path, "not a WorshipFlow translation file"), (noVerses.path, "no verses"),
                                 (text.path, "not a translation file"), (dir.appendingPathComponent("absent.json").path, "does not exist")] {
            let run = await ToolHarness.run(["import", "--library", lib.path, "--file", path])
            #expect(run.status == 1, "\(path)")
            #expect(run.err.contains(fragment), "\(path): \(run.err)")
            #expect(run.err.split(separator: "\n").count == 1, "\(path): \(run.err)")
        }
        #expect(try Data(contentsOf: lib) == bytes)
    }

    @Test func importReadsAFolderOfUSFMWithMetadataFromFlags() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let usfm = dir.appendingPathComponent("usfm", isDirectory: true)
        try FileManager.default.createDirectory(at: usfm, withIntermediateDirectories: true)
        try "\\id JHN synthetic\n\\c 3\n\\p\n\\v 16 Synthetic sixteen.\n\\v 17 Synthetic seventeen.\n".write(to: usfm.appendingPathComponent("44-JHN.usfm"), atomically: true, encoding: .utf8)
        try "\\id GEN synthetic\n\\c 1\n\\p\n\\v 1 Synthetic one.\n".write(to: usfm.appendingPathComponent("01-GEN.usfm"), atomically: true, encoding: .utf8)
        try "\\id FRT front matter\n\\mt Not a book\n".write(to: usfm.appendingPathComponent("00-FRT.usfm"), atomically: true, encoding: .utf8)
        try "ignored".write(to: usfm.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let lib = try library(in: dir)
        let missing = await ToolHarness.run(["import", "--library", lib.path, "--file", usfm.path])
        #expect(missing.status == 1 && missing.err.contains("--language") )
        let noID = await ToolHarness.run(["import", "--library", lib.path, "--file", usfm.path, "--language", "en"])
        #expect(noID.status == 1 && noID.err.contains("--id"))
        let run = await ToolHarness.run(["import", "--library", lib.path, "--file", usfm.path, "--id", "syn", "--language", "en", "--name", "Synthetic USFM", "--licence", "synthetic"])
        #expect(run.status == 0, "\(run.err)")
        #expect(run.out.contains("00-FRT.usfm") && run.out.contains("not one of the 66 books"))
        let stored = try #require(try await translations(lib).first)
        #expect(stored.code == "syn" && stored.name == "Synthetic USFM" && stored.verseCount == 3 && stored.licence == "synthetic" && stored.copyright == "not stated")
        // One USFM file works too.
        let single = await ToolHarness.run(["import", "--library", lib.path, "--file", usfm.appendingPathComponent("44-JHN.usfm").path, "--id", "one", "--language", "en"])
        #expect(single.status == 0 && single.out.contains("2 verses"))
    }

    @Test func progressAndTimingAreReported() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let lib = try library(in: dir)
        let file = dir.appendingPathComponent("syn.json")
        try F.syntheticFull().encoded().write(to: file)
        let run = await ToolHarness.run(["import", "--library", lib.path, "--file", file.path])
        #expect(run.status == 0)
        #expect(run.err.contains("writing verses: 0 of 31102") && run.err.contains("writing verses: 31102 of 31102"))
        #expect(run.out.contains("31102 verses in"))
    }
}
