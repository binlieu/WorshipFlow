// HWTEST-001 / FIX-D S6: a run that did not finish. While a real run goes, its files are written to a visible folder on the
// Desktop ("<date>-WORSHIPFLOW-hardware-test-unfinished"); the folder is removed after the report is saved. If the app crashes on
// first contact with the card, the folder is still there, and the next time the Hardware Test window opens it offers to
// save what is in it, with a first line that says the run did not finish and which step it stopped in.
import Foundation

public struct UnfinishedHardwareTestRun: Equatable, Sendable {
    public var folder: URL
    /// One sentence for the window: what the folder holds.
    public var description: String
    /// True when the run reached its end but its report was never saved.
    public var reachedTheEnd: Bool
}

public enum HardwareTestUnfinished {
    public static let folderSuffix = "WORSHIPFLOW-hardware-test-unfinished"

    /// `2026-11-21-1423-WORSHIPFLOW-hardware-test-unfinished`.
    public static func folderName(date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02d-%02d%02d-", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0) + folderSuffix
    }

    /// The folder to make for a run that starts now inside `parent`, never one that exists already.
    public static func newFolder(in parent: URL, date: Date = Date(), calendar: Calendar = .current) -> URL {
        let base = folderName(date: date, calendar: calendar)
        var candidate = parent.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent(base + "-\(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }

    /// `--unfinished-folder <dir>` names where unfinished runs go instead of the Desktop (for tests and for the coordinator, so
    /// nothing lands on a real Desktop). Without it, `desktop` is used.
    public static func parent(arguments: [String], desktop: URL?) -> URL? {
        if let i = arguments.firstIndex(of: "--unfinished-folder"), i + 1 < arguments.count, !arguments[i + 1].hasPrefix("--") {
            return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
        }
        return desktop
    }

    /// The Desktop folder of this user, or nil.
    public static func desktop() -> URL? { FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first }

    /// Unfinished runs in `parent`, newest first. `excluding` is the folder of a run that is going on now.
    public static func find(in parent: URL, excluding: URL? = nil) -> [UnfinishedHardwareTestRun] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return [] }
        let skip = excluding?.standardizedFileURL.path
        return names.filter { $0.contains(folderSuffix) }.sorted(by: >).compactMap { name in
            let folder = parent.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue, folder.standardizedFileURL.path != skip else { return nil }
            let report = loadReport(in: folder)
            return UnfinishedHardwareTestRun(folder: folder, description: describe(report), reachedTheEnd: report?.complete == true)
        }
    }

    static func loadReport(in folder: URL) -> HardwareTestReport? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("report.json")) else { return nil }
        return try? JSONDecoder().decode(HardwareTestReport.self, from: data)
    }

    /// "It stopped during step 5 (Fill and key loopback). Steps 1 to 4 were recorded."
    static func describe(_ report: HardwareTestReport?) -> String {
        guard let report else { return "It holds no finished step: the test stopped before it could record anything." }
        if report.complete { return "The test reached its end but its report was never saved." }
        var text = report.runningStep.map { "It stopped during step \($0)" + (report.runningStepTitle.map { " (\($0))" } ?? "") + "." } ?? "It stopped between two steps."
        let done = report.steps.map(\.number)
        if let last = done.max() { text += done.count == 1 ? " Step \(last) was recorded." : " \(done.count) steps were recorded, up to step \(last)." } else { text += " No step was recorded." }
        return text
    }

    /// The first line of the saved report of an unfinished run.
    public static func firstLine(for report: HardwareTestReport?) -> String {
        guard let report else { return "THIS TEST DID NOT FINISH: it stopped before any step was recorded, so this report holds only what the app wrote at the start." }
        if report.complete { return "THIS TEST FINISHED, but its report was not saved when it ended. This is the report as the test left it." }
        let where_ = report.runningStep.map { "it stopped during step \($0)" + (report.runningStepTitle.map { ", \($0)" } ?? "") } ?? "it stopped between two steps"
        return "THIS TEST DID NOT FINISH: \(where_). Only the steps before it are recorded, and nothing was measured by the step it stopped in."
    }

    /// Zips what the unfinished folder holds: the report as written, a summary whose first line says the run did not finish
    /// and where it stopped, the log, and any photos. Nothing is removed here.
    public static func makeZip(from folder: URL, to zip: URL, redactor: HardwareTestRedactor = HardwareTestRedactor()) throws {
        let report = loadReport(in: folder)
        var entries: [(name: String, data: Data)] = []
        let fm = FileManager.default
        if let data = try? Data(contentsOf: folder.appendingPathComponent("report.json")) { entries.append(("report.json", data)) }
        let summary = firstLine(for: report) + "\n\n"
            + (report.map { HardwareTestSummary.render($0) } ?? (try? String(contentsOf: folder.appendingPathComponent("summary.txt"), encoding: .utf8)) ?? "")
        entries.append(("summary.txt", Data(redactor.scrub(summary).utf8)))
        if let data = try? Data(contentsOf: folder.appendingPathComponent("engine-log.txt")) { entries.append(("engine-log.txt", data)) }
        let photos = folder.appendingPathComponent("photos")
        if let names = try? fm.contentsOfDirectory(atPath: photos.path) {
            for name in names.sorted() { if let data = try? Data(contentsOf: photos.appendingPathComponent(name)) { entries.append(("photos/" + name, data)) } }
        }
        try fm.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
        try HardwareTestZip.write(entries, to: zip)
    }

    /// `2026-11-21-1423-WORSHIPFLOW-hardware-test-UNFINISHED.zip`, from the folder's own date.
    public static func zipName(for folder: URL) -> String {
        let name = folder.lastPathComponent
        let stamp = name.components(separatedBy: "-" + folderSuffix).first ?? name
        return stamp + "-WORSHIPFLOW-hardware-test-UNFINISHED.zip"
    }
}

/// Decisions about what may happen while the Hardware Test is going on (FIX-D S15), kept apart from the windows so they can be tested.
public enum HardwareTestGuard {
    /// Why the screens may not be opened now, or nil. The Hardware Test takes over the card, so opening a screen during a run
    /// could start output on the card under test.
    public static func screensRefusal(testIsRunning: Bool) -> String? {
        testIsRunning ? "The Hardware Test is running and is using the card, so the screens cannot be opened now. Finish or stop the test first (Hardware Test window, Stop after this step), then open the screens." : nil
    }
}
