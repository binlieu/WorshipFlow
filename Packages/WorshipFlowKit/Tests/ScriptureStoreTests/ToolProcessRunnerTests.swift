// LIB-004b: the real process runner, against a stand-in `mysql` shell script written to a temporary folder. The script
// prints canned output or fails; no database server is involved and nothing connects anywhere.
import Testing
import Foundation
@testable import ScriptureStore

@Suite struct ToolProcessRunnerTests {
    /// Writes an executable script and returns its path. `body` is shell. The script records its arguments and the
    /// MYSQL_PWD it was given into files next to it.
    private func fakeClient(_ body: String, in dir: URL) throws -> String {
        let path = dir.appendingPathComponent("mysql").path
        let script = """
            #!/bin/sh
            printf '%s\\n' "$@" > "\(dir.path)/argv.txt"
            printf '%s' "${MYSQL_PWD-<unset>}" > "\(dir.path)/pwd.txt"
            \(body)
            """
        try script.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    private func runner(binary: String?, password: String? = "s3cr3t-pw", host: String? = "db.example.test", timeout: Int = 30,
                        path: String = "/usr/bin:/bin") -> ProcessMySQLRunner {
        ProcessMySQLRunner(connection: MySQLConnection(host: host, port: 3307, user: "reader", database: "bible", socket: nil, binary: binary),
                           password: password, environment: ["PATH": path, "HOME": "/nonexistent", "MYSQL_PWD": "inherited-should-go"], timeoutSeconds: timeout)
    }

    @Test func outputIsReturnedAndThePasswordTravelsOnlyInTheEnvironment() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("printf '41\\t42\\n'", in: dir)
        let out = try await runner(binary: client).run(sql: "SELECT 1")
        #expect(out == "41\t42\n")
        let argv = try String(contentsOfFile: dir.appendingPathComponent("argv.txt").path, encoding: .utf8)
        #expect(!argv.contains("s3cr3t-pw") && !argv.contains("inherited-should-go"))
        #expect(argv.contains("--default-character-set=utf8mb4") && argv.contains("--batch") && argv.contains("--skip-column-names"))
        #expect(argv.contains("--host=db.example.test") && argv.contains("--port=3307") && argv.contains("--user=reader") && argv.contains("--database=bible"))
        #expect(argv.contains("--init-command=SET SESSION TRANSACTION READ ONLY") && argv.contains("--execute=SELECT 1"))
        #expect(try String(contentsOfFile: dir.appendingPathComponent("pwd.txt").path, encoding: .utf8) == "s3cr3t-pw")
    }

    @Test func withNoPasswordTheInheritedOneIsNotPassedOn() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("true", in: dir)
        _ = try await runner(binary: client, password: nil).run(sql: "SELECT 1")
        #expect(try String(contentsOfFile: dir.appendingPathComponent("pwd.txt").path, encoding: .utf8) == "<unset>")
    }

    @Test func anAuthenticationFailureIsOneLineWithoutThePasswordOrTheCommandLine() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("""
            echo "mysql: [Warning] Using a password on the command line interface can be insecure." >&2
            echo "ERROR 1045 (28000): Access denied for user 'reader'@'db.example.test' (using password: YES)" >&2
            echo "debug: s3cr3t-pw $*" >&2
            exit 1
            """, in: dir)
        do {
            _ = try await runner(binary: client).run(sql: "SELECT secret_column FROM verses")
            Issue.record("expected the client's failure")
        } catch let error as MySQLError {
            let text = error.message
            #expect(text.contains("status 1") && text.contains("ERROR 1045") && text.contains("Access denied"))
            #expect(!text.contains("s3cr3t-pw"))
            #expect(!text.contains("--execute") && !text.contains("secret_column") && !text.contains("--host") && !text.contains(client))
            #expect(!text.contains("\n"))
        }
    }

    @Test func aServerThatEchoesThePasswordIsRedacted() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("echo \"ERROR 1045 (28000): bad login for password s3cr3t-pw at host\" >&2; exit 1", in: dir)
        do {
            _ = try await runner(binary: client).run(sql: "SELECT 1")
            Issue.record("expected the client's failure")
        } catch let error as MySQLError {
            #expect(!error.message.contains("s3cr3t-pw") && error.message.contains("[hidden]"))
        }
    }

    @Test func aMissingClientIsNamedWithTheWayToFixIt() async throws {
        do {
            _ = try await runner(binary: "/nonexistent/dir/mysql").run(sql: "SELECT 1")
            Issue.record("expected an error")
        } catch let error as MySQLError {
            #expect(error == .binaryNotFound("/nonexistent/dir/mysql"))
            #expect(error.message.contains("--mysql-bin") && error.message.contains("not found"))
        }
        // A bare name is looked up on PATH only.
        let empty = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: empty) }
        do {
            _ = try await runner(binary: nil, path: empty.path).run(sql: "SELECT 1")
            Issue.record("expected an error")
        } catch let error as MySQLError { #expect(error == .binaryNotFound("mysql")) }
        // A file that is not executable is not a client.
        let plain = empty.appendingPathComponent("mysql")
        try "x".write(to: plain, atomically: true, encoding: .utf8)
        do { _ = try await runner(binary: plain.path).run(sql: "SELECT 1"); Issue.record("expected an error") }
        catch let error as MySQLError { #expect(error == .binaryNotFound(plain.path)) }
    }

    @Test func aBareNameIsFoundOnPath() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = try fakeClient("printf ok", in: dir)
        #expect(try await runner(binary: nil, path: dir.path).run(sql: "SELECT 1") == "ok")
    }

    @Test func aStatementThatIsNotReadOnlyNeverReachesTheClient() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("touch \"\(dir.path)/ran\"", in: dir)
        for sql in ["DROP TABLE verses", "SELECT 1; DELETE FROM verses", "INSERT INTO verses VALUES (1)"] {
            do { _ = try await runner(binary: client).run(sql: sql); Issue.record("expected a refusal") }
            catch let error as MySQLError { #expect(error == .notReadOnly) }
        }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("ran").path))
    }

    @Test func largeOutputOnBothStreamsDoesNotDeadlock() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // About 6 MB on standard output and 1 MB on standard error, then success.
        let client = try fakeClient("""
            i=0; while [ $i -lt 60000 ]; do echo "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"; i=$((i+1)); done
            i=0; while [ $i -lt 10000 ]; do echo "warning line warning line warning line warning line warning line warning line warning line warn" >&2; i=$((i+1)); done
            """, in: dir)
        let out = try await runner(binary: client).run(sql: "SELECT 1")
        #expect(out.utf8.count == 60000 * 101)
    }

    @Test func aClientThatHangsIsStopped() async throws {
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let client = try fakeClient("exec sleep 20", in: dir)
        let started = ContinuousClock.now
        do { _ = try await runner(binary: client, timeout: 1).run(sql: "SELECT 1"); Issue.record("expected a timeout") }
        catch let error as MySQLError { #expect(error == .timedOut(seconds: 1)) }
        #expect(ContinuousClock.now - started < .seconds(10))
    }

    @Test func aWholeExportThroughTheProcessRunnerKeepsTextExact() async throws {
        // The stand-in client prints the hex rows a real one would; the tool then decodes them.
        let dir = ToolFixtures.tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let rows = ToolFixtures.smallVerses().map { "\($0.bookOrder)\\t\($0.chapter)\\t\($0.verse)\\t\(hex($0.text ?? ""))" }.joined(separator: "\\n")
        let client = try fakeClient("printf '\(rows)\\n'", in: dir)
        let source = MySQLBibleSource(runner: runner(binary: client))
        let schema = ResolvedSchema(versionsTable: "versions", versesTable: "verses", booksTable: nil, versionID: "id", versionCode: "code", versionName: nil,
                                    versionLanguage: nil, versesVersion: "version_id", versesVersionIsID: true, versesBook: "book_order",
                                    versesChapter: "chapter", versesVerse: "verse", versesText: "text", booksOrder: nil, booksNameEN: nil)
        let got = try await source.verses(of: VersionSummary(key: "1", code: "X", name: nil, language: nil, verseCount: 6, bookCount: 3, chapterCount: 3), schema)
        #expect(got.map(\.text) == ToolFixtures.smallVerses().map(\.text))
    }
}
