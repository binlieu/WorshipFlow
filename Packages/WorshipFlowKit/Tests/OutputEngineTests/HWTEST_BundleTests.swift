// HWTEST-001: the report, its summary, the zip bundle and reading a bundle back. Pure file work, no device.
import Testing
import Foundation
@testable import OutputEngine

enum HWTestSamples {
    static func step(_ number: Int, _ id: HardwareTestStepID, _ title: String, _ outcome: HardwareTestOutcome,
                     summary: String = "Something happened.", measurements: [HardwareMeasurement] = []) -> HardwareStepResult {
        HardwareStepResult(id: id, number: number, title: title, outcome: outcome, summary: summary,
                           passCriteria: "Pass criteria for \(title).", measurements: measurements)
    }

    static func report(simulated: Bool = false, complete: Bool = true) -> HardwareTestReport {
        var r = HardwareTestReport(simulated: simulated, deviceName: simulated ? "Simulated SDI card (4 connectors)" : "DeckLink Duo 2",
                                   deviceID: "dev-1", preset: "quick", startedAt: "2026-11-20T10:00:00Z")
        r.steps = [
            step(1, .environment, "Environment", .passed, measurements: [HardwareMeasurement(name: "macOS", value: "27.2")]),
            step(2, .devices, "Devices", .passed),
            step(3, .outputRun, "Output run", .failed, summary: "2 frames were dropped.",
                 measurements: [HardwareMeasurement(name: "Dropped frames", value: "2", unit: "frames")]),
            step(4, .loopback, "Loopback", .skipped),
            step(5, .humanChecks, "Human checks", .needsHuman),
        ]
        r.steps[2].samples = ["dropped": [0, 0, 1, 2]]
        r.steps[2].sampleIntervalSeconds = 1
        r.steps[2].findings = ["UNV-04: nothing to say yet."]
        r.complete = complete
        r.finishedAt = complete ? "2026-11-20T10:03:00Z" : nil
        return r
    }
}

@Suite struct HWTEST_BundleTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-hwtest-unit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: report

    @Test func aReportRoundTripsThroughJSON() throws {
        let report = HWTestSamples.report()
        let data = try HardwareTestReport.encoder.encode(report)
        let back = try JSONDecoder().decode(HardwareTestReport.self, from: data)
        #expect(back == report)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"schemaVersion\" : 1"))
        #expect(text.contains("\"needsHuman\""))
        #expect(back.schemaVersion == HardwareTestReport.currentSchemaVersion)
    }

    @Test func aNewerSchemaVersionStillDecodesAndKeepsItsNumber() throws {
        var report = HWTestSamples.report()
        report.schemaVersion = 7
        let back = try JSONDecoder().decode(HardwareTestReport.self, from: HardwareTestReport.encoder.encode(report))
        #expect(back.schemaVersion == 7)
    }

    // MARK: summary

    @Test func theSummaryStartsWithTheStatementThenTheTable() {
        let text = HardwareTestSummary.render(HWTestSamples.report(simulated: false))
        let lines = text.components(separatedBy: "\n")
        #expect(!lines[0].contains("SIMULATED"))
        let head = lines.prefix(8).joined(separator: "\n")
        #expect(head.contains("DeckLink Duo 2"))
        #expect(head.contains("real hardware"))
        #expect(head.contains("This report describes what was measured on this run. It is not a certification."))
        let table = try? #require(text.range(of: "1. Environment"))
        let details = try? #require(text.range(of: "DETAILS"))
        #expect(table != nil && details != nil && table!.lowerBound < details!.lowerBound)
        for word in ["PASSED", "FAILED", "SKIPPED", "NEEDS A PERSON"] { #expect(text.contains(word)) }
        #expect(text.contains("Dropped frames: 2 frames"))
        #expect(text.contains("Pass criteria for Output run."))
    }

    @Test func aSimulatedReportSaysSoOnItsFirstLine() {
        let text = HardwareTestSummary.render(HWTestSamples.report(simulated: true))
        let first = text.components(separatedBy: "\n")[0]
        #expect(first.contains("SIMULATED"))
        #expect(text.contains("no real card"))
    }

    @Test func anUnfinishedReportIsMarkedIncomplete() {
        let text = HardwareTestSummary.render(HWTestSamples.report(complete: false))
        #expect(text.contains("INCOMPLETE"))
        #expect(!HardwareTestSummary.render(HWTestSamples.report(complete: true)).contains("INCOMPLETE"))
    }

    @Test func aBriefSummaryTrimsPassedStepsAndAFullOneKeepsEverything() {
        var report = HWTestSamples.report()
        report.steps[0].measurements = (1...10).map { HardwareMeasurement(name: "M\($0)", value: "v\($0)") }
        report.steps[2].measurements = (1...10).map { HardwareMeasurement(name: "F\($0)", value: "v\($0)") }     // a failed step
        let brief = HardwareTestSummary.render(report)
        #expect(brief.contains("M6: v6") && !brief.contains("M7: v7"))
        #expect(brief.contains("4 more measurements are in report.json"))
        #expect(brief.contains("F10: v10"))                    // a failed step is shown whole
        let full = HardwareTestSummary.render(report, detail: .full)
        #expect(full.contains("M10: v10") && !full.contains("more measurements"))
    }

    @Test func theTotalsAreCounted() {
        let text = HardwareTestSummary.render(HWTestSamples.report())
        #expect(text.contains("2 passed, 1 failed, 1 skipped, 1 needs a person"))
    }

    // MARK: zip

    @Test func aZipIsReadableByUnzipAndByOurReader() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let big = Data((0..<(9 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let entries: [(name: String, data: Data)] = [("report.json", Data("{\"a\":1}".utf8)), ("photos/photo-1.jpg", big), ("empty.txt", Data())]
        let url = dir.appendingPathComponent("t.zip")
        try HardwareTestZip.write(entries, to: url)
        let back = try HardwareTestZip.read(from: url)
        #expect(back.map(\.name) == entries.map(\.name))
        #expect(back.map(\.data) == entries.map(\.data))
        // the system's own unzip accepts it
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-tq", url.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)
    }

    @Test func aCorruptedZipIsRejected() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("t.zip")
        try HardwareTestZip.write([("a.txt", Data("hello world".utf8))], to: url)
        var bytes = try Data(contentsOf: url)
        bytes[40] ^= 0xFF                                    // inside the stored data
        try bytes.write(to: url)
        #expect(throws: (any Error).self) { _ = try HardwareTestZip.read(from: url) }
        try Data("not a zip".utf8).write(to: url)
        #expect(throws: (any Error).self) { _ = try HardwareTestZip.read(from: url) }
    }

    // MARK: bundle

    @Test func theWriterWritesIncrementallyAndTheBundleRoundTrips() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let work = dir.appendingPathComponent("work")
        let writer = try HardwareTestBundleWriter(directory: work)
        var report = HWTestSamples.report(complete: false)
        try writer.write(report: report, log: "line one\n")
        // already on disk before the run ends
        let partial = try Data(contentsOf: work.appendingPathComponent("report.json"))
        #expect(try JSONDecoder().decode(HardwareTestReport.self, from: partial).steps.count == 5)
        #expect(try String(contentsOf: work.appendingPathComponent("summary.txt"), encoding: .utf8).contains("INCOMPLETE"))
        #expect(try String(contentsOf: work.appendingPathComponent("engine-log.txt"), encoding: .utf8) == "line one\n")

        report.complete = true
        report.finishedAt = "2026-11-20T10:03:00Z"
        let zip = dir.appendingPathComponent("out.zip")
        try writer.finish(report: report, log: "line one\nline two\n", zipTo: zip)
        let loaded = try HardwareTestBundle.load(from: zip)
        #expect(loaded.report == report)
        #expect(loaded.engineLog == "line one\nline two\n")
        #expect(loaded.summary == HardwareTestSummary.render(report))
        #expect(!loaded.summary.contains("INCOMPLETE"))
        // a folder reads the same as its zip
        #expect(try HardwareTestBundle.load(from: work).report == report)
    }

    @Test func photosAreCopiedByNameWithoutTheirPath() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("My Holiday.JPG")
        try Data([1, 2, 3, 4]).write(to: photo)
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        let name = try writer.attachPhoto(from: photo)
        #expect(name == "photos/photo-1.jpg")
        #expect(try writer.attachPhoto(from: photo) == "photos/photo-2.jpg")
        let zip = dir.appendingPathComponent("out.zip")
        try writer.finish(report: HWTestSamples.report(), log: "", zipTo: zip)
        let loaded = try HardwareTestBundle.load(from: zip)
        #expect(loaded.photoNames == ["photos/photo-1.jpg", "photos/photo-2.jpg"])
        #expect(try HardwareTestZip.read(from: zip).first { $0.name == "photos/photo-1.jpg" }?.data == Data([1, 2, 3, 4]))
    }

    @Test func aMissingPhotoThrowsAndLeavesNoTrace() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"))
        #expect(throws: (any Error).self) { _ = try writer.attachPhoto(from: dir.appendingPathComponent("nope.jpg")) }
        try writer.finish(report: HWTestSamples.report(), log: "", zipTo: dir.appendingPathComponent("o.zip"))
        #expect(try HardwareTestBundle.load(from: dir.appendingPathComponent("o.zip")).photoNames.isEmpty)
    }

    @Test func theBundleNeverContainsTheUserNameOrHomePath() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let redactor = HardwareTestRedactor(homePath: "/Users/pastor.jane", userName: "pastor.jane")
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"), redactor: redactor)
        var report = HWTestSamples.report()
        report.steps[0].summary = "Saved to /Users/pastor.jane/Desktop/a.zip by pastor.jane"
        report.steps[0].measurements.append(HardwareMeasurement(name: "Folder", value: "/Users/someone.else/Library/x"))
        let zip = dir.appendingPathComponent("o.zip")
        try writer.finish(report: report, log: "opened /Users/pastor.jane/Movies/clip.mov\nuser pastor.jane\n", zipTo: zip)
        for entry in try HardwareTestZip.read(from: zip) {
            let text = String(decoding: entry.data, as: UTF8.self)
            #expect(!text.contains("pastor.jane"), "\(entry.name)")
            #expect(!text.contains("someone.else"), "\(entry.name)")
        }
        let loaded = try HardwareTestBundle.load(from: zip)
        #expect(loaded.engineLog.contains("~/Movies/clip.mov"))
    }

    @Test func theRedactorLeavesOrdinaryTextAlone() {
        let r = HardwareTestRedactor(homePath: "/Users/al", userName: "al")
        #expect(r.scrub("Dropped 2 frames at 12 s, final health OK") == "Dropped 2 frames at 12 s, final health OK")
        #expect(r.scrub("/Users/al/x") == "~/x")
        #expect(r.scrub("a path /Volumes/Storage/thing stays") == "a path /Volumes/Storage/thing stays")
    }

    @Test func theFileNameCarriesTheDateAndSaysSimulated() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9, minute: 5))!
        let real = HardwareTestBundle.fileName(simulated: false, date: date, calendar: cal)
        let sim = HardwareTestBundle.fileName(simulated: true, date: date, calendar: cal)
        #expect(real == "2026-11-20-0905-WORSHIPFLOW-hardware-test.zip")
        #expect(sim == "2026-11-20-0905-SIMULATED-WORSHIPFLOW-hardware-test.zip")
    }
}
