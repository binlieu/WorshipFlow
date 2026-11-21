// HWTEST-001: the bundle the tester sends back. A folder written step by step while the test runs, zipped at the end:
// report.json (every step's structured result and raw samples), summary.txt (one page a person can read),
// engine-log.txt, and any photos the tester attached.
import Foundation
import CryptoKit
import ImageIO
import CoreGraphics

/// FIX-D S5: the card's persistent id identifies one card (and so one church), so the report carries a short hash of it: enough
/// to tell two runs on the same card from runs on two cards, not enough to look the card up.
public enum HardwareTestHash {
    public static func short(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}

/// Takes personal details out of anything written to a bundle: the home folder path becomes `~`, any other
/// `/Users/<name>` path is anonymised, and the user's name is replaced wherever it appears. FIX-D S5: so are the other names
/// that identify a person or a machine (the user's full name, the Mac's name, its host name), because a display's name or a
/// device's name can carry them ("Pastor Dave's iMac"). Display and device names are kept, since the report needs them, but
/// are checked against this list.
public struct HardwareTestRedactor: Sendable {
    private let homePath: String
    private let userName: String
    private let extraTerms: [String]

    public init(homePath: String = NSHomeDirectory(), userName: String = NSUserName(), extraTerms: [String] = HardwareTestRedactor.systemTerms()) {
        self.homePath = homePath
        self.userName = userName
        // Short strings are not scrubbed: they would damage ordinary words, and a name that short identifies no one.
        self.extraTerms = extraTerms.filter { $0.count >= 4 && $0.contains { $0.isLetter } }
            .sorted { $0.count > $1.count }           // the longer name first, so "Dave's iMac" goes before "Dave"
    }

    /// The names of this person and this Mac: the full user name, the Mac's name as shown in Sharing, and the host name.
    public static func systemTerms() -> [String] {
        var terms: [String] = [NSFullUserName()]
        if let name = Host.current().localizedName { terms.append(name) }
        var buffer = [CChar](repeating: 0, count: 256)
        if gethostname(&buffer, buffer.count) == 0 {
            let host = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            terms.append(host)
            if let first = host.split(separator: ".").first { terms.append(String(first)) }
        }
        return terms
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
        for term in extraTerms {
            let escaped = NSRegularExpression.escapedPattern(for: term)
            s = s.replacingOccurrences(of: "(?<![A-Za-z0-9])" + escaped + "(?![A-Za-z0-9])", with: "<name>", options: [.regularExpression, .caseInsensitive])
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
        case .photoUnreadable(let what): return "The photo could not be read: \(what) is not a picture this app can open."
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

    /// Attaches a photo as `photos/photo-N.jpg`. FIX-D S5: the photo is decoded and written again as a plain JPEG, so nothing
    /// that was in the file besides the picture survives (location, camera, date, thumbnail, orientation tags: the picture
    /// is turned upright first). The original name and path are not kept, and the error never names them. A file that cannot
    /// be read as a picture is refused rather than copied, because its contents could not be checked.
    public func attachPhoto(from url: URL) throws -> String {
        guard let jpeg = Self.cleanedJPEG(from: url) else { throw HardwareTestBundleError.photoUnreadable("the chosen file") }
        let number = lock.withLock { () -> Int in photoCount += 1; return photoCount }
        let name = "photos/photo-\(number).jpg"
        let target = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: target, options: .atomic)
        return name
    }

    /// The picture alone, upright, at most 4096 pixels on its long side, as JPEG data with no metadata; nil if it cannot be read.
    static func cleanedJPEG(from url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,          // applies the orientation tag, then the tag is gone
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCache: false,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        // Only the compression quality is passed: no metadata dictionary, so none is written.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
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
