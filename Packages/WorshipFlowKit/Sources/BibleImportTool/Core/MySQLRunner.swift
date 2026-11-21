// LIB-004b: the one place that talks to a MySQL client. It shells out to the `mysql` binary (ADR-0008 decision 7), so the
// app carries no database client and no password. Read-only: the session is set read only, and only SELECT or SHOW
// statements are ever sent.
//
// The password travels only in the child's environment (`MYSQL_PWD`), never in its arguments, and no error text ever
// contains the password or the command line.
import Foundation

struct MySQLConnection: Equatable, Sendable {
    var host: String?
    var port: Int?
    var user: String?
    var database: String
    var socket: String?
    /// Path or bare name of the client; nil means "mysql" found on PATH.
    var binary: String?
}

enum MySQLError: Error, Equatable {
    case binaryNotFound(String)
    case couldNotStart(String)
    /// The client ran and exited non-zero. `message` is the client's own first error line, with the password removed.
    case failed(status: Int32, message: String)
    case timedOut(seconds: Int)
    case notReadOnly
    case unexpectedOutput(String)
    case schema(String)
    case versionNotFound(code: String, available: [String])
    case data(String)

    /// One line for the operator.
    var message: String {
        switch self {
        case .binaryNotFound(let name):
            return "the mysql client was not found (\(name)). Install it, or give its location with --mysql-bin."
        case .couldNotStart(let detail): return "the mysql client could not be started: \(detail)"
        case .failed(let status, let message):
            return "the mysql client exited with status \(status)" + (message.isEmpty ? "." : ": \(message)")
        case .timedOut(let seconds): return "the mysql client did not finish within \(seconds) seconds and was stopped."
        case .notReadOnly: return "refused to send a statement that is not a plain SELECT or SHOW (this tool only reads)."
        case .unexpectedOutput(let detail): return "unexpected output from the mysql client: \(detail)"
        case .schema(let detail): return detail
        case .versionNotFound(let code, let available):
            return "the database has no version with the code “\(code)”. Versions found: " + (available.isEmpty ? "none" : available.joined(separator: ", ")) + "."
        case .data(let detail): return detail
        }
    }
}

protocol MySQLRunning: Sendable {
    /// Runs one read-only statement and returns the client's standard output.
    func run(sql: String) async throws -> String
}

/// The statement check shared by the real runner and the tests' fake: only SELECT and SHOW, one statement.
enum ReadOnlyStatement {
    static func isAllowed(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("select ") || lower.hasPrefix("show ") else { return false }
        // Our statements never contain a semicolon: a second statement would be an attempt to smuggle one in.
        if trimmed.contains(";") { return false }
        for word in ["insert ", "update ", "delete ", "drop ", "alter ", "create ", "grant ", "truncate ", "replace ", "into outfile", "into dumpfile", "load_file"] {
            if lower.contains(word) { return false }
        }
        return true
    }
}

struct ProcessMySQLRunner: MySQLRunning {
    var connection: MySQLConnection
    /// Passed to the client as MYSQL_PWD. Never logged.
    var password: String?
    var environment: [String: String]
    var timeoutSeconds: Int = 600

    func run(sql: String) async throws -> String {
        guard ReadOnlyStatement.isAllowed(sql) else { throw MySQLError.notReadOnly }
        let executable = try resolveBinary()
        let arguments = clientArguments(sql: sql)
        let env = childEnvironment()
        let password = self.password
        let timeout = timeoutSeconds
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try Self.runBlocking(executable: executable, arguments: arguments, environment: env,
                                                                        password: password, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Arguments in the order the client expects. None of them carries the password.
    func clientArguments(sql: String) -> [String] {
        var args = ["--default-character-set=utf8mb4", "--batch", "--skip-column-names", "--connect-timeout=15",
                    "--init-command=SET SESSION TRANSACTION READ ONLY"]
        if let host = connection.host { args.append("--host=\(host)") }
        if let port = connection.port { args.append("--port=\(port)") }
        if let user = connection.user { args.append("--user=\(user)") }
        if let socket = connection.socket { args.append("--socket=\(socket)") }
        args.append("--database=\(connection.database)")
        args.append("--execute=\(sql)")
        return args
    }

    func childEnvironment() -> [String: String] {
        var env = environment
        env.removeValue(forKey: "MYSQL_PWD")
        if let password, !password.isEmpty { env["MYSQL_PWD"] = password }
        return env
    }

    func resolveBinary() throws -> URL {
        let wanted = connection.binary ?? "mysql"
        let manager = FileManager.default
        if wanted.contains("/") {
            guard manager.isExecutableFile(atPath: wanted) else { throw MySQLError.binaryNotFound(wanted) }
            return URL(fileURLWithPath: wanted)
        }
        for directory in (environment["PATH"] ?? "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin").split(separator: ":") {
            let candidate = String(directory) + "/" + wanted
            if manager.isExecutableFile(atPath: candidate) { return URL(fileURLWithPath: candidate) }
        }
        throw MySQLError.binaryNotFound(wanted)
    }

    private static func runBlocking(executable: URL, arguments: [String], environment: [String: String],
                                    password: String?, timeout: Int) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch {
            throw MySQLError.couldNotStart(redact(error.localizedDescription, password: password))
        }
        let box = Collected()
        let group = DispatchGroup()
        for (pipe, keyPath) in [(out, \Collected.stdout), (err, \Collected.stderr)] {
            group.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                box.set(keyPath, data)
                group.leave()
            }
        }
        let timedOut = TimeoutFlag()
        let watchdog = DispatchWorkItem { timedOut.set(); if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: watchdog)
        process.waitUntilExit()
        watchdog.cancel()
        group.wait()
        if timedOut.isSet { throw MySQLError.timedOut(seconds: timeout) }
        guard process.terminationStatus == 0 else {
            throw MySQLError.failed(status: process.terminationStatus,
                                    message: firstErrorLine(String(decoding: box.stderr, as: UTF8.self), password: password))
        }
        return String(decoding: box.stdout, as: UTF8.self)
    }

    /// The client's first "ERROR ..." line (or its first non-empty line), at most 300 characters, with the password
    /// removed wherever it appears. Never the command line.
    static func firstErrorLine(_ stderr: String, password: String?) -> String {
        let lines = stderr.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let chosen = lines.first { $0.hasPrefix("ERROR") } ?? lines.first ?? ""
        return String(redact(chosen, password: password).prefix(300))
    }

    static func redact(_ text: String, password: String?) -> String {
        guard let password, !password.isEmpty else { return text }
        return text.replacingOccurrences(of: password, with: "[hidden]")
    }
    private func redact(_ text: String) -> String { Self.redact(text, password: password) }

    private final class Collected: @unchecked Sendable {   // each field is written by one reader thread, read after group.wait()
        var stdout = Data()
        var stderr = Data()
        func set(_ keyPath: ReferenceWritableKeyPath<Collected, Data>, _ data: Data) { self[keyPath: keyPath] = data }
    }

    private final class TimeoutFlag: @unchecked Sendable {   // set by the watchdog, read after waitUntilExit
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }
}
