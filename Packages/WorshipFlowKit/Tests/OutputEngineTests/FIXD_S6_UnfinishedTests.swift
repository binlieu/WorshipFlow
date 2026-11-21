// FIX-D S6: a real run writes its files to a visible folder as it goes and removes the folder after the report is saved; a run
// that did not finish is offered the next time the Hardware Test window opens, with a first line that says so.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@MainActor
@Suite struct FIXD_S6_UnfinishedTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-unf-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func controller(parent: URL, steps: [HardwareTestStep]? = HardwareTestSteps.standard(.tiny).filter { [.environment, .devices].contains($0.id) },
                            onRunning: (@MainActor (Bool) -> Void)? = nil) -> HardwareTestController {
        let driver = HardwareDriverStatus(isInstalled: false, message: "Blackmagic Desktop Video is not installed.")
        let real = HardwareTestProvider(isSimulated: false, devices: { [] }, driver: { driver })
        return HardwareTestController(realProvider: { real }, environment: .fixed, screensOpen: { false },
                                      durationsOverride: HardwareTestConfiguration.tiny.durations, stepsOverride: steps,
                                      workingFolder: parent.appendingPathComponent("work"), unfinishedParent: parent, onRunningChange: onRunning)
    }

    private func finish(_ c: HardwareTestController) async {
        for _ in 0..<2400 where c.phase == .running { try? await Task.sleep(for: .milliseconds(25)) }
    }

    private func unfinishedFolders(in parent: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0.hasSuffix(HardwareTestUnfinished.folderSuffix) || $0.contains(HardwareTestUnfinished.folderSuffix) }
    }

    // MARK: names and arguments

    @Test func theFolderNameCarriesTheDateAndTheWordsTheGuideUses() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let name = HardwareTestUnfinished.folderName(date: Date(timeIntervalSince1970: 1_800_000_000), calendar: cal)
        #expect(name == "2027-01-15-0800-WorshipFlow-hardware-test-unfinished")
        #expect(HardwareTestUnfinished.zipName(for: URL(fileURLWithPath: "/x/" + name)) == "2027-01-15-0800-WorshipFlow-hardware-test-UNFINISHED.zip")
    }

    @Test func aLaunchArgumentMovesTheFolderOffTheDesktop() {
        let desktop = URL(fileURLWithPath: "/Users/someone/Desktop")
        #expect(HardwareTestUnfinished.parent(arguments: ["app", "--unfinished-folder", "/tmp/x"], desktop: desktop)?.path == "/tmp/x")
        #expect(HardwareTestUnfinished.parent(arguments: ["app"], desktop: desktop) == desktop)
        #expect(HardwareTestUnfinished.parent(arguments: ["app", "--unfinished-folder"], desktop: desktop) == desktop)
        #expect(HardwareTestUnfinished.parent(arguments: ["app", "--unfinished-folder", "--other"], desktop: desktop) == desktop)
    }

    // MARK: while a run goes

    @Test func aRealRunWritesItsFilesToAVisibleFolderAsItGoesAndRemovesItAfterTheReportIsSaved() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        final class Gate: @unchecked Sendable { let lock = NSLock(); var open = false; var seenFolder: [String] = []; var seenStep: Int?
            func release() { lock.lock(); open = true; lock.unlock() }
            var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open } }
        let gate = Gate()
        let step = HardwareTestStep(id: .environment, number: 1, title: "Slow step", timeoutSeconds: 60) { _ in
            while !gate.isOpen { try await Task.sleep(for: .milliseconds(10)) }
            return HardwareStepOutput(outcome: .passed, summary: "ok")
        }
        let c = controller(parent: parent, steps: [step])
        c.start(simulated: false)
        // while the step runs, the folder exists and says which step is running
        var folders: [String] = []
        for _ in 0..<400 where folders.isEmpty { try? await Task.sleep(for: .milliseconds(10)); folders = unfinishedFolders(in: parent) }
        #expect(folders.count == 1, "\(folders)")
        let folder = parent.appendingPathComponent(try #require(folders.first))
        #expect(folder.lastPathComponent.hasSuffix("-WorshipFlow-hardware-test-unfinished"))
        var running: Int?
        for _ in 0..<400 where running == nil {
            try? await Task.sleep(for: .milliseconds(10))
            running = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("report.json"))) as? [String: Any])?["runningStep"] as? Int
        }
        #expect(running == 1)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("summary.txt").path))
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("engine-log.txt").path))
        #expect(c.unfinishedRun == nil, "the run going on now is not offered as an earlier one")
        gate.release()
        await finish(c)
        #expect(FileManager.default.fileExists(atPath: folder.path), "the folder stays until the report is saved")
        let dest = parent.appendingPathComponent("saved.zip")
        try c.save(to: dest)
        #expect(!FileManager.default.fileExists(atPath: folder.path), "removed after a successful save")
        #expect(try HardwareTestBundle.load(from: dest).report.complete)
    }

    @Test func aDemonstrationWithTheSimulatedCardLeavesNothingOnTheDesktop() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let c = controller(parent: parent)
        c.start(simulated: true)
        await finish(c)
        #expect(unfinishedFolders(in: parent).isEmpty)
    }

    @Test func theControllerTellsTheAppWhenARunStartsAndEnds() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        final class Calls: @unchecked Sendable { var list: [Bool] = [] }
        let calls = Calls()
        let c = controller(parent: parent, onRunning: { calls.list.append($0) })
        c.start(simulated: false)
        await finish(c)
        #expect(calls.list == [true, false])
    }

    // MARK: the next launch

    /// Leaves what a crash during step 5 would leave: the loose files, the report naming the running step, no zip.
    private func leaveACrashedRun(in parent: URL, runningStep: Int? = 5, title: String? = "Fill and key loopback", complete: Bool = false) throws -> URL {
        let folder = HardwareTestUnfinished.newFolder(in: parent, date: Date(timeIntervalSince1970: 1_800_000_000))
        let writer = try HardwareTestBundleWriter(directory: folder, redactor: HardwareTestRedactor(homePath: "/Users/jane", userName: "jane", extraTerms: []))
        var report = HardwareTestReport(simulated: false, deviceName: "DeckLink Duo 2", deviceID: "abcd1234", preset: "quick", startedAt: "2027-01-15T08:00:00Z")
        report.steps = (1...4).map { HardwareStepResult(id: HardwareTestStepID.allCases[$0 - 1], number: $0, title: "S\($0)", outcome: .passed, summary: "ok") }
        report.runningStep = runningStep
        report.runningStepTitle = title
        report.complete = complete
        try writer.write(report: report, log: "2027-01-15T08:00:01Z  Step 5: Fill and key loopback\n")
        return folder
    }

    @Test func aFolderLeftByACrashIsOfferedWhenTheWindowOpensAndSavedWithAFirstLineThatSaysSo() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try leaveACrashedRun(in: parent)
        let c = controller(parent: parent)
        let run = try #require(c.unfinishedRun)
        #expect(run.folder.lastPathComponent == folder.lastPathComponent)
        #expect(run.description.contains("stopped during step 5") && run.description.contains("Fill and key loopback"), "\(run.description)")
        #expect(!run.reachedTheEnd)
        #expect(c.suggestedUnfinishedFileName.hasSuffix("WorshipFlow-hardware-test-UNFINISHED.zip"))
        let dest = parent.appendingPathComponent("out/report.zip")
        try c.saveUnfinishedReport(to: dest)
        let loaded = try HardwareTestBundle.load(from: dest)
        let first = loaded.summary.components(separatedBy: "\n")[0]
        #expect(first.hasPrefix("THIS TEST DID NOT FINISH"), "\(first)")
        #expect(first.contains("step 5") && first.contains("Fill and key loopback"), "\(first)")
        #expect(loaded.report.runningStep == 5 && !loaded.report.complete)
        #expect(loaded.engineLog.contains("Step 5"))
        #expect(!FileManager.default.fileExists(atPath: folder.path), "removed after the save")
        #expect(c.unfinishedRun == nil)
    }

    @Test func aRunThatReachedItsEndButWasNeverSavedIsOfferedWithTheRightWords() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        _ = try leaveACrashedRun(in: parent, runningStep: nil, title: nil, complete: true)
        let c = controller(parent: parent)
        #expect(c.unfinishedRun?.reachedTheEnd == true)
        let dest = parent.appendingPathComponent("o.zip")
        try c.saveUnfinishedReport(to: dest)
        #expect(try HardwareTestBundle.load(from: dest).summary.hasPrefix("THIS TEST FINISHED, but its report was not saved"))
    }

    @Test func aFolderWithNoReportAtAllStillMakesAReportThatSaysNothingWasRecorded() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let folder = HardwareTestUnfinished.newFolder(in: parent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("2027-01-15T08:00:00Z  Hardware test started\n".utf8).write(to: folder.appendingPathComponent("engine-log.txt"))
        let c = controller(parent: parent)
        #expect(c.unfinishedRun?.description.contains("no finished step") == true)
        let dest = parent.appendingPathComponent("o.zip")
        try c.saveUnfinishedReport(to: dest)
        let entries = try HardwareTestZip.read(from: dest)
        #expect(String(decoding: try #require(entries.first { $0.name == "summary.txt" }).data, as: UTF8.self).hasPrefix("THIS TEST DID NOT FINISH"))
        #expect(entries.contains { $0.name == "engine-log.txt" })
    }

    @Test func nothingIsOfferedWhenThereIsNothingLeft() throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        #expect(controller(parent: parent).unfinishedRun == nil)
    }

    @Test func theSavedUnfinishedReportCarriesNoNameOfAPerson() async throws {
        let parent = try scratch(); defer { try? FileManager.default.removeItem(at: parent) }
        let folder = try leaveACrashedRun(in: parent)
        // a name that got into the folder some other way is still scrubbed when the report is zipped
        try Data("owner /Users/\(NSUserName())/Desktop/x\n".utf8).write(to: folder.appendingPathComponent("engine-log.txt"))
        let zip = parent.appendingPathComponent("o.zip")
        try HardwareTestUnfinished.makeZip(from: folder, to: zip, redactor: HardwareTestRedactor(homePath: NSHomeDirectory(), userName: NSUserName(), extraTerms: []))
        let summary = String(decoding: try #require(try HardwareTestZip.read(from: zip).first { $0.name == "summary.txt" }).data, as: UTF8.self)
        #expect(!summary.contains("/Users/\(NSUserName())"))
    }

    // MARK: S15's refusal during a run

    @Test func screensCannotBeOpenedWhileATestIsRunningAndTheMessageSaysWhy() {
        #expect(HardwareTestGuard.screensRefusal(testIsRunning: false) == nil)
        let why = HardwareTestGuard.screensRefusal(testIsRunning: true)
        #expect(why?.contains("Hardware Test is running") == true && why?.contains("screens cannot be opened") == true, "\(String(describing: why))")
    }
}
}
