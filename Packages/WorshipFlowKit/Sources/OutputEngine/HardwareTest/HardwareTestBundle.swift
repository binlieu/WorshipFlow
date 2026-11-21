// HWTEST-001: the bundle the tester sends back. A folder written step by step while the test runs, zipped at the end:
// report.json (every step's structured result and raw samples), summary.txt (one page a person can read),
// engine-log.txt, and any photos the tester attached.
import Foundation

/// Takes personal details out of anything written to a bundle: the home folder path becomes `~`, any other
/// `/Users/<name>` path is anonymised, and the user's name is replaced wherever it appears.
public struct HardwareTestRedactor: Sendable {
    private let homePath: String
    private let userName: String

    public init(homePath: String = NSHomeDirectory(), userName: String = NSUserName()) {
        self.homePath = homePath
        self.userName = userName
    }

    public func scrub(_ text: String) -> String {
        var s = text
        if homePath.count > 1 {
            let escaped = NSRegularExpression.escapedPattern(for: homePath)
            s = s.replacingOccurrences(of: escaped + "(?![A-Za-z0-9._-])", with: "~", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "/Users/(?!<user>)[^/\\s\"'\\\\]+", with: "/Users/<user>", options: .regularExpression)
        if userName.count >= 3 {
            let escaped = NSRegularExpression.escapedPattern(for: userName)
            s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])", with: "<user>", options: .regularExpression)
        }
        return s
    }
}

public struct LoadedHardwareTestBundle: Sendable {
    public var report: HardwareTestReport
    public var summary: String
    public var engineLog: String
    public var photoNames: [String]

    /// The summary with every measurement, rendered from the report (the file `summary.txt` is the brief one).
    public var fullSummary: String { HardwareTestSummary.render(report, detail: .full) }
}

public enum HardwareTestBundleError: Error, LocalizedError, Equatable {
    case notABundle(String)
    case photoUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notABundle(let why): return "This is not a WORSHIPFLOW hardware test bundle: \(why)"
        case .photoUnreadable(let name): return "The photo could not be read: \(name)"
        }
    }
}

public enum HardwareTestBundle {
    /// `2026-11-20-0905-WORSHIPFLOW-hardware-test.zip`, with `SIMULATED-` before `WORSHIPFLOW` for a simulated run.
    public static func fileName(simulated: Bool, date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        return "\(stamp)-\(simulated ? "SIMULATED-" : "")WORSHIPFLOW-hardware-test.zip"
    }

    /// Reads a bundle from its zip or from the folder it was built in.
    public static func load(from url: URL) throws -> LoadedHardwareTestBundle {
        var files: [String: Data] = [:]
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            let base = url.standardizedFileURL.path
            if let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let file as URL in walker {
                    let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    let path = file.standardizedFileURL.path
                    guard path.hasPrefix(base + "/") else { continue }
                    files[String(path.dropFirst(base.count + 1))] = try Data(contentsOf: file)
                }
            }
        } else {
            for entry in try HardwareTestZip.read(from: url) { files[entry.name] = entry.data }
        }
        guard let reportData = files["report.json"] else { throw HardwareTestBundleError.notABundle("report.json is missing") }
        let report: HardwareTestReport
        do { report = try JSONDecoder().decode(HardwareTestReport.self, from: reportData) } catch {
            throw HardwareTestBundleError.notABundle("report.json cannot be read (\(error.localizedDescription))")
        }
        return LoadedHardwareTestBundle(
            report: report,
            summary: files["summary.txt"].map { String(decoding: $0, as: UTF8.self) } ?? "",
            engineLog: files["engine-log.txt"].map { String(decoding: $0, as: UTF8.self) } ?? "",
            photoNames: files.keys.filter { $0.hasPrefix("photos/") }.sorted())
    }
}

/// Writes the bundle folder. After every step the whole of `report.json`, `summary.txt` and `engine-log.txt` is replaced
/// atomically, so a crash or a pulled plug leaves everything up to the last finished step on disk.
/// `@unchecked Sendable`: `photoCount` is only touched while holding `lock`; everything else is immutable.
public final class HardwareTestBundleWriter: @unchecked Sendable {
    public let directory: URL
    private let redactor: HardwareTestRedactor
    private let lock = NSLock()
    private var photoCount = 0

    public init(directory: URL, redactor: HardwareTestRedactor = HardwareTestRedactor()) throws {
        self.directory = directory
        self.redactor = redactor
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Replaces the three text files with the state so far.
    public func write(report: HardwareTestReport, log: String) throws {
        let json = redactor.scrub(String(decoding: try HardwareTestReport.encoder.encode(report), as: UTF8.self))
        try put(json, "report.json")
        try put(redactor.scrub(HardwareTestSummary.render(report)), "summary.txt")
        try put(redactor.scrub(log), "engine-log.txt")
    }

    /// Copies a photo into `photos/` under a neutral name and returns that name. The original name and path are not kept.
    public func attachPhoto(from url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url) else { throw HardwareTestBundleError.photoUnreadable(url.lastPathComponent) }
        let ext = String(url.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber })
        let number = lock.withLock { () -> Int in photoCount += 1; return photoCount }
        let name = "photos/photo-\(number)" + (ext.isEmpty ? "" : ".\(ext)")
        let target = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return name
    }

    /// Writes the final state and zips the folder to `zipTo`.
    public func finish(report: HardwareTestReport, log: String, zipTo: URL) throws {
        try write(report: report, log: log)
        var entries: [(name: String, data: Data)] = []
        for name in ["report.json", "summary.txt", "engine-log.txt"] {
            entries.append((name, try Data(contentsOf: directory.appendingPathComponent(name))))
        }
        let photos = directory.appendingPathComponent("photos")
        if let names = try? FileManager.default.contentsOfDirectory(atPath: photos.path) {
            for name in names.sorted() { entries.append(("photos/" + name, try Data(contentsOf: photos.appendingPathComponent(name)))) }
        }
        try FileManager.default.createDirectory(at: zipTo.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HardwareTestZip.write(entries, to: zipTo)
    }

    private func put(_ text: String, _ name: String) throws {
        try Data(text.utf8).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
