// UI-004: the name the operator and a tester see is "WorshipFlow". Reports and unfinished folders written by an older build,
// which spelled it "WORSHIPFLOW", must still be recognised.
import Testing
import Foundation
@testable import OutputEngine

@Suite struct UI004_RenameTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-ui004-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func newNamesUseTheNewSpelling() {
        #expect(HardwareTestUnfinished.folderSuffix == "WorshipFlow-hardware-test-unfinished")
        #expect(HardwareTestBundle.fileName(simulated: false, date: Date(timeIntervalSince1970: 1_800_000_000), calendar: utc).hasSuffix("-WorshipFlow-hardware-test.zip"))
        #expect(HardwareTestBundle.fileName(simulated: true, date: Date(timeIntervalSince1970: 1_800_000_000), calendar: utc).hasSuffix("-SIMULATED-WorshipFlow-hardware-test.zip"))
    }

    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func anUnfinishedFolderFromAnOlderBuildIsStillFoundAndNamedInTheNewSpelling() throws {
        let parent = try scratch()
        defer { try? FileManager.default.removeItem(at: parent) }
        let old = parent.appendingPathComponent("2026-11-20-0905-WORSHIPFLOW-hardware-test-unfinished", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        let found = HardwareTestUnfinished.find(in: parent)
        #expect(found.count == 1)
        #expect(HardwareTestUnfinished.zipName(for: old) == "2026-11-20-0905-WorshipFlow-hardware-test-UNFINISHED.zip")
    }

    @Test func aNewSpellingFolderIsFoundToo() throws {
        let parent = try scratch()
        defer { try? FileManager.default.removeItem(at: parent) }
        let folder = HardwareTestUnfinished.newFolder(in: parent)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(HardwareTestUnfinished.find(in: parent).count == 1)
        #expect(HardwareTestUnfinished.zipName(for: folder).hasSuffix("-WorshipFlow-hardware-test-UNFINISHED.zip"))
    }
}

@Suite struct UI004_ReportBuildLineTests {
    private func environment(detail: String?) -> HardwareEnvironmentInfo {
        HardwareEnvironmentInfo(appVersion: "0.0.1", appBuild: "41", osVersion: "27", osBuild: "x", macModel: "Mac16,10", chip: "M4", memoryGB: 16,
                                processorCount: 10, displays: [], driver: HardwareDriverStatus(isInstalled: false, message: "none"), collectedAt: "2026-11-21T00:00:00Z",
                                appBuildDetail: detail)
    }

    @Test func theSummaryNamesTheBuildThatMadeIt() throws {
        var report = HardwareTestReport(simulated: false, deviceName: "DeckLink Duo 2", deviceID: "abcd1234", preset: "quick", startedAt: "2027-01-15T08:00:00Z")
        report.environment = environment(detail: "commit 71d344d, built 2026-11-21")
        let text = HardwareTestSummary.render(report)
        #expect(text.contains("WorshipFlow 0.0.1 (41), commit 71d344d, built 2026-11-21, macOS 27"))
    }

    @Test func aReportFromAnOlderBuildStillReadsAndRenders() throws {
        var report = HardwareTestReport(simulated: false, deviceName: "DeckLink Duo 2", deviceID: "abcd1234", preset: "quick", startedAt: "2027-01-15T08:00:00Z")
        report.environment = environment(detail: nil)
        let data = try JSONEncoder().encode(report)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var env = try #require(json["environment"] as? [String: Any])
        env.removeValue(forKey: "appBuildDetail")
        json["environment"] = env
        let old = try JSONSerialization.data(withJSONObject: json)
        let back = try JSONDecoder().decode(HardwareTestReport.self, from: old)
        #expect(back.environment?.appBuildDetail == nil)
        #expect(HardwareTestSummary.render(back).contains("WorshipFlow 0.0.1 (41), macOS 27"))
    }
}
