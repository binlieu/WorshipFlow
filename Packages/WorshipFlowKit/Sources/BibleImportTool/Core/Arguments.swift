// LIB-004b: command-line parsing for wf-bible-import. No password is ever accepted here (ADR-0008 decision 7).
import Foundation

/// A mistake in how the tool was called. The text is the one-line reason; it never repeats an option's value.
struct UsageError: Error, Equatable {
    var message: String
}

struct OptionSpec {
    /// Options that take a value: `--host localhost` or `--host=localhost`. Names without the dashes.
    var values: Set<String>
    /// Options without a value.
    var flags: Set<String>
}

struct ParsedArguments {
    var values: [String: [String]] = [:]
    var flags: Set<String> = []
    var positional: [String] = []

    func value(_ name: String) -> String? { values[name]?.last }
    func all(_ name: String) -> [String] { values[name] ?? [] }
    func has(_ flag: String) -> Bool { flags.contains(flag) }
}

enum ArgumentParser {
    /// Option names that would carry a password. They are refused outright, whatever their value.
    private static let passwordNames: Set<String> = ["password", "passwd", "pass", "pwd", "mysql-pwd", "mysql-password", "db-password"]

    static func parse(_ arguments: [String], spec: OptionSpec) throws -> ParsedArguments {
        var parsed = ParsedArguments()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            guard argument.hasPrefix("-"), argument != "-" else { parsed.positional.append(argument); continue }
            // mysql's own `-pSECRET` and `-p`: refused without looking at what follows.
            if !argument.hasPrefix("--"), argument.hasPrefix("-p") {
                throw UsageError(message: passwordRefusal)
            }
            if argument == "-h" { parsed.flags.insert("help"); continue }
            guard argument.hasPrefix("--") else { throw UsageError(message: "unknown option \(argument.prefix(2)). Try --help.") }
            let body = argument.dropFirst(2)
            let name: String
            var inline: String?
            if let equals = body.firstIndex(of: "=") {
                name = String(body[..<equals])
                inline = String(body[body.index(after: equals)...])
            } else {
                name = String(body)
            }
            if passwordNames.contains(name) { throw UsageError(message: passwordRefusal) }
            if name == "help" { parsed.flags.insert("help"); continue }
            if spec.flags.contains(name) {
                if inline != nil { throw UsageError(message: "--\(name) does not take a value.") }
                parsed.flags.insert(name)
            } else if spec.values.contains(name) {
                if let inline {
                    parsed.values[name, default: []].append(inline)
                } else if index < arguments.count {
                    parsed.values[name, default: []].append(arguments[index])
                    index += 1
                } else {
                    throw UsageError(message: "--\(name) needs a value.")
                }
            } else {
                throw UsageError(message: "unknown option --\(name). Try --help.")
            }
        }
        return parsed
    }

    static let passwordRefusal = "a password is never accepted on the command line. Set the MYSQL_PWD environment variable or type it at the prompt."
}
