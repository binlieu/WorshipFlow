// LIB-004b: the three commands. Everything here runs through `ToolEnvironment`, so the tests call `run` with a fake
// MySQL runner and a fake usage checker and read the output and the exit status.
import Foundation
import Domain
import ScriptureEngine
import Persistence
import ScriptureStore

enum ExitStatus {
    static let ok: Int32 = 0
    static let failed: Int32 = 1
    static let usage: Int32 = 2
    static let refused: Int32 = 3
}

enum ImportToolCLI {
    static let name = "wf-bible-import"

    private static let mysqlValues: Set<String> = ["host", "port", "user", "database", "socket", "mysql-bin", "versions-table", "verses-table", "books-table", "map"]
    private static let metadataValues: Set<String> = ["id", "name", "language", "abbreviation", "copyright", "licence", "license", "source", "versification",
                                                      "owner-approval-date", "owner-approval-note"]
    private static let metadataFlags: Set<String> = ["public-domain", "owner-approved"]

    static func run(_ arguments: [String], environment env: ToolEnvironment) async -> Int32 {
        guard let first = arguments.first else {
            env.err("\(name): no command given. Try --help.")
            return ExitStatus.usage
        }
        if first == "--help" || first == "-h" || first == "help" { env.out(Help.general); return ExitStatus.ok }
        let rest = Array(arguments.dropFirst())
        do {
            switch first {
            case "inspect":
                let spec = OptionSpec(values: mysqlValues, flags: ["mysql", "schema", "no-password"])
                let parsed = try ArgumentParser.parse(rest, spec: spec)
                if parsed.has("help") { env.out(Help.inspect); return ExitStatus.ok }
                return try await inspect(parsed, env)
            case "export":
                let spec = OptionSpec(values: mysqlValues.union(metadataValues).union(["version", "out"]),
                                      flags: metadataFlags.union(["mysql", "no-password", "overwrite"]))
                let parsed = try ArgumentParser.parse(rest, spec: spec)
                if parsed.has("help") { env.out(Help.export); return ExitStatus.ok }
                return try await export(parsed, env)
            case "import":
                let spec = OptionSpec(values: metadataValues.union(["library", "file"]),
                                      flags: metadataFlags.union(["replace", "force", "create", "dry-run"]))
                let parsed = try ArgumentParser.parse(rest, spec: spec)
                if parsed.has("help") { env.out(Help.importCommand); return ExitStatus.ok }
                return try await importFile(parsed, env)
            default:
                throw UsageError(message: "unknown command “\(first.prefix(30))”. Commands are inspect, export and import. Try --help.")
            }
        } catch let error as UsageError {
            env.err("\(name): \(error.message)")
            return ExitStatus.usage
        } catch let error as MySQLError {
            env.err("\(name): \(error.message)")
            return ExitStatus.failed
        } catch let error as FileSourceError {
            env.err("\(name): \(error.text)")
            return ExitStatus.failed
        } catch {
            env.err("\(name): \(error.localizedDescription)")
            return ExitStatus.failed
        }
    }

    // MARK: Shared pieces

    private static func connection(_ parsed: ParsedArguments) throws -> MySQLConnection {
        guard let database = parsed.value("database"), !database.isEmpty else {
            throw UsageError(message: "--database is required.")
        }
        var port: Int?
        if let text = parsed.value("port") {
            guard let number = Int(text), number > 0, number < 65536 else { throw UsageError(message: "--port must be a number from 1 to 65535.") }
            port = number
        }
        return MySQLConnection(host: parsed.value("host"), port: port, user: parsed.value("user"), database: database,
                               socket: parsed.value("socket"), binary: parsed.value("mysql-bin"))
    }

    private static func mapping(_ parsed: ParsedArguments) throws -> MySQLSchemaMapping {
        var mapping = MySQLSchemaMapping()
        if let t = parsed.value("versions-table") { mapping.versionsTable = t }
        if let t = parsed.value("verses-table") { mapping.versesTable = t }
        if let t = parsed.value("books-table") { mapping.booksTable = t }
        let roles: Set<String> = ["versions.id", "versions.code", "versions.name", "versions.language", "verses.version", "verses.book",
                                  "verses.chapter", "verses.verse", "verses.text", "books.order", "books.name_en"]
        for item in parsed.all("map") {
            guard let equals = item.firstIndex(of: "=") else { throw UsageError(message: "--map needs table.role=column.") }
            let role = String(item[..<equals]), column = String(item[item.index(after: equals)...])
            guard roles.contains(role), !column.isEmpty else {
                throw UsageError(message: "--map role “\(role.prefix(30))” is not one of: \(roles.sorted().joined(separator: ", ")).")
            }
            mapping.overrides[role] = column
        }
        return mapping
    }

    /// MYSQL_PWD from the environment, else a prompt when someone is at the terminal. Never from an argument.
    private static func password(_ connection: MySQLConnection, _ parsed: ParsedArguments, _ env: ToolEnvironment) -> String? {
        if let fromEnvironment = env.variables["MYSQL_PWD"] { return fromEnvironment }
        guard !parsed.has("no-password"), env.isInteractive else { return nil }
        let who = (connection.user ?? "") + (connection.host.map { "@" + $0 } ?? "")
        return env.promptPassword("MySQL password" + (who.isEmpty ? "" : " for \(who)") + ": ")
    }

    private static func metadata(_ parsed: ParsedArguments) throws -> ExportMetadata {
        var meta = ExportMetadata()
        meta.id = parsed.value("id")
        meta.name = parsed.value("name")
        meta.language = parsed.value("language")
        meta.abbreviation = parsed.value("abbreviation")
        meta.copyright = parsed.value("copyright")
        meta.licence = parsed.value("licence") ?? parsed.value("license")
        meta.source = parsed.value("source")
        meta.versification = parsed.value("versification")
        meta.isPublicDomain = parsed.has("public-domain")
        meta.ownerApproved = parsed.has("owner-approved")
        meta.ownerApprovalDate = parsed.value("owner-approval-date")
        meta.ownerApprovalNote = parsed.value("owner-approval-note")
        if !meta.ownerApproved, meta.ownerApprovalDate != nil || meta.ownerApprovalNote != nil {
            throw UsageError(message: "--owner-approval-date and --owner-approval-note only make sense with --owner-approved.")
        }
        if let date = meta.ownerApprovalDate, date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil {
            throw UsageError(message: "--owner-approval-date must look like 2026-11-20.")
        }
        return meta
    }

    private static func source(_ parsed: ParsedArguments, _ env: ToolEnvironment) throws -> (MySQLBibleSource, MySQLConnection) {
        let conn = try connection(parsed)
        let runner = env.makeRunner(conn, password(conn, parsed, env), env.variables)
        return (MySQLBibleSource(runner: runner, mapping: try mapping(parsed)), conn)
    }

    // MARK: inspect

    private static func inspect(_ parsed: ParsedArguments, _ env: ToolEnvironment) async throws -> Int32 {
        let (source, conn) = try source(parsed, env)
        let schema = try await source.resolveSchema()
        let versions = try await source.listVersions(schema)
        if parsed.has("schema") { schema.description.forEach(env.out) ; env.out("") }
        env.out("Database \(conn.database): \(versions.count) version\(versions.count == 1 ? "" : "s")")
        var header = ["CODE", "NAME"]
        if schema.versionLanguage != nil { header.append("LANGUAGE") }
        header += ["BOOKS", "CHAPTERS", "VERSES"]
        var table = [header]
        for v in versions {
            var row = [v.code, v.name ?? ""]
            if schema.versionLanguage != nil { row.append(v.language ?? "") }
            row += [String(v.bookCount), String(v.chapterCount), String(v.verseCount)]
            table.append(row)
        }
        let widths = header.indices.map { column in table.map { $0[column].count }.max() ?? 0 }
        let numericFrom = header.count - 3
        for row in table {
            env.out(row.indices.map { column in
                let cell = row[column]
                let padding = String(repeating: " ", count: max(0, widths[column] - cell.count))
                return column >= numericFrom ? padding + cell : cell + padding
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces))
        }
        return ExitStatus.ok
    }

    // MARK: export

    private static func export(_ parsed: ParsedArguments, _ env: ToolEnvironment) async throws -> Int32 {
        guard let code = parsed.value("version"), !code.isEmpty else { throw UsageError(message: "--version is required (a code from `inspect`).") }
        guard let out = parsed.value("out"), !out.isEmpty else { throw UsageError(message: "--out is required.") }
        let meta = try metadata(parsed)
        guard let language = meta.language, !language.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UsageError(message: "--language is required (for example --language vi).")
        }
        let outURL = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: outURL.path), !parsed.has("overwrite") {
            env.err("\(name): \(outURL.path) already exists. Use --overwrite to replace it.")
            return ExitStatus.refused
        }
        _ = language
        let (source, conn) = try source(parsed, env)
        let schema = try await source.resolveSchema()
        let versions = try await source.listVersions(schema)
        let match = versions.first { $0.code == code } ?? versions.first { $0.code.lowercased() == code.lowercased() }
        guard let version = match else { throw MySQLError.versionNotFound(code: code, available: versions.map(\.code)) }
        guard version.verseCount > 0 else { throw MySQLError.data("version “\(version.code)” has no verses in the database.") }
        let names = (try? await source.bookNames(schema)) ?? [:]
        let rows = try await source.verses(of: version, schema)
        let built = try TranslationExporter.build(
            code: version.code, versionName: version.name, rows: rows, bookNames: names, metadata: meta,
            sourceDescription: "MySQL database “\(conn.database)”, version \(version.code), exported by \(name)")
        built.report.lines.forEach(env.out)

        let data = try built.file.encoded()
        try FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = outURL.deletingLastPathComponent().appendingPathComponent(".\(outURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            if FileManager.default.fileExists(atPath: outURL.path) { _ = try FileManager.default.replaceItemAt(outURL, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: outURL) }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        let loaded = TranslationLoader.validate(built.file)
        for message in loaded.report.messages { env.out("Check: \(message)") }
        env.out("Wrote \(outURL.path) (\(data.count / 1024) KiB). Do not commit it: it is Bible text.")
        return ExitStatus.ok
    }

    // MARK: import

    private static func importFile(_ parsed: ParsedArguments, _ env: ToolEnvironment) async throws -> Int32 {
        guard let libraryArgument = parsed.value("library"), !libraryArgument.isEmpty else { throw UsageError(message: "--library is required.") }
        guard let fileArgument = parsed.value("file"), !fileArgument.isEmpty else { throw UsageError(message: "--file is required.") }
        let meta = try metadata(parsed)
        let libraryPath = URL(fileURLWithPath: (libraryArgument as NSString).expandingTildeInPath).path
        let source = try TranslationFileSource.load(path: (fileArgument as NSString).expandingTildeInPath, metadata: meta)
        source.notes.forEach { env.out("Note: \($0)") }

        let loaded = TranslationLoader.validate(source.file)
        env.out("File: \(loaded.translation.metadata.id) “\(loaded.translation.metadata.name)”, \(loaded.report.verseCount) verses in \(loaded.report.bookCount) books.")
        loaded.report.messages.forEach { env.out("Check: \($0)") }
        guard loaded.report.verseCount > 0 else { throw FileSourceError.message("the file has no verses that can be imported.") }
        if parsed.has("dry-run") {
            env.out("Dry run: the library was not opened and nothing was written.")
            return ExitStatus.ok
        }

        switch LibraryProbe.inspect(path: libraryPath) {
        case .missing:
            guard parsed.has("create") else {
                env.err("\(name): the library \(libraryPath) does not exist. Check the path, or add --create to make a new library file.")
                return ExitStatus.failed
            }
        case .foreign(let why):
            env.err("\(name): \(libraryPath) does not look like a WorshipFlow library (\(why)). Nothing was changed.")
            return ExitStatus.refused
        case .empty, .worshipFlowLibrary: break
        }

        if !parsed.has("force") {
            switch env.usage.usage(of: libraryPath, ignoring: env.processID) {
            case .free, .unknown: break
            case .inUse(let holders):
                let list = holders.map { "\($0.command) (pid \($0.pid))" }.joined(separator: ", ")
                env.err("\(name): the library is open in another program: \(list). Quit it and run again. --force overrides this, but two programs writing one file can lose changes and the app will not show the new translation until it restarts.")
                return ExitStatus.refused
            case .suspected(let file):
                env.err("\(name): the library has unsaved changes waiting in \(file), so it is open in a program or was closed badly. Quit the app and run again; --force overrides this.")
                return ExitStatus.refused
            }
        }

        let library: LibraryStore
        do { library = try LibraryStore.open(at: URL(fileURLWithPath: libraryPath)) } catch {
            env.err("\(name): could not open the library: \(error.localizedDescription). Nothing was changed.")
            return ExitStatus.failed
        }
        let store = ScriptureStore(library: library)
        let marks = ProgressMarks(print: env.err)
        let clock = ContinuousClock()
        var result: ScriptureImportResult?
        var failure: Error?
        let elapsed = await clock.measure {
            do { result = try await store.importTranslation(source.file, replaceExisting: parsed.has("replace"), progress: { marks.report($0) }) }
            catch { failure = error }
        }
        try? library.close()
        if let failure {
            if let known = failure as? ScriptureStoreError {
                if case .alreadyExists(let code) = known {
                    env.err("\(name): the library already has a translation “\(code)”. Add --replace to replace it. Nothing was changed.")
                    return ExitStatus.refused
                }
                env.err("\(name): \(known.message) Nothing was changed.")
                return ExitStatus.failed
            }
            env.err("\(name): the import failed and was rolled back: \(failure.localizedDescription). Nothing was changed.")
            return ExitStatus.failed
        }
        guard let result else { return ExitStatus.failed }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        env.out("\(result.replaced ? "Replaced" : "Imported") \(result.translation.code) “\(result.translation.name)”: \(result.translation.verseCount) verses in \(String(format: "%.1f", seconds)) s into \(libraryPath).")
        return ExitStatus.ok
    }
}

/// Prints progress at about every quarter, from the writer's queue.
final class ProgressMarks: @unchecked Sendable {   // the lock guards `next`
    private let lock = NSLock()
    private var next = 0
    private let print: @Sendable (String) -> Void
    init(print: @escaping @Sendable (String) -> Void) { self.print = print }

    func report(_ progress: ScriptureImportProgress) {
        lock.lock()
        let percent = progress.versesTotal == 0 ? 100 : progress.versesDone * 100 / progress.versesTotal
        let shouldPrint = percent >= next
        if shouldPrint { next = (percent / 25 + 1) * 25 }
        lock.unlock()
        if shouldPrint { print("  writing verses: \(progress.versesDone) of \(progress.versesTotal)") }
    }
}
