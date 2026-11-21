// LIB-004b: what the tool needs from the outside world, so tests can replace it.
import Foundation
#if canImport(Darwin)
import Darwin
#endif

struct ToolEnvironment: Sendable {
    var variables: [String: String]
    var out: @Sendable (String) -> Void
    var err: @Sendable (String) -> Void
    /// True when a person is at the terminal, so a password may be asked for.
    var isInteractive: Bool
    /// Asks for a password without echo. Nil when none was given.
    var promptPassword: @Sendable (String) -> String?
    var makeRunner: @Sendable (_ connection: MySQLConnection, _ password: String?, _ variables: [String: String]) -> any MySQLRunning
    var usage: any LibraryUsageChecking
    var processID: Int32

    static func live() -> ToolEnvironment {
        ToolEnvironment(
            variables: ProcessInfo.processInfo.environment,
            out: { text in FileHandle.standardOutput.write(Data((text + "\n").utf8)) },
            err: { text in FileHandle.standardError.write(Data((text + "\n").utf8)) },
            isInteractive: isatty(STDIN_FILENO) != 0,
            promptPassword: { prompt in
                var buffer = [CChar](repeating: 0, count: 1024)
                guard let result = readpassphrase(prompt, &buffer, buffer.count, 0) else { return nil }
                let password = String(cString: result)
                // Clear our copy of the typed characters.
                for index in buffer.indices { buffer[index] = 0 }
                return password
            },
            makeRunner: { connection, password, variables in
                ProcessMySQLRunner(connection: connection, password: password, environment: variables)
            },
            usage: LsofUsageChecker(),
            processID: ProcessInfo.processInfo.processIdentifier)
    }
}
