// FIX-J item 6 (UI-005h): the hardware-test environment section records which font the output looks were drawn in.
import Testing
import Foundation
@testable import OutputEngine

@Suite struct FIXJ_EnvironmentFontTests {
    private func environment(font: String?) -> HardwareEnvironmentInfo {
        HardwareEnvironmentInfo(appVersion: "0.0.1", appBuild: "41", osVersion: "27", osBuild: "x", macModel: "Mac16,10", chip: "M4", memoryGB: 16,
                                processorCount: 10, displays: [], driver: HardwareDriverStatus(isInstalled: false, message: "none"),
                                collectedAt: "2026-11-21T00:00:00Z", outputFont: font)
    }

    @Test func theSummaryNamesTheOutputFont() {
        var report = HardwareTestReport(simulated: false, deviceName: "DeckLink Duo 2", deviceID: "abcd1234", preset: "quick", startedAt: "2027-01-15T08:00:00Z")
        report.environment = environment(font: "system font (Helvetica): the bundled font could not be loaded")
        let text = HardwareTestSummary.render(report)
        #expect(text.contains("Output font: system font (Helvetica): the bundled font could not be loaded"))
    }

    @Test func aReportWithoutTheFontStillReadsAndRendersWithoutTheLine() throws {
        var report = HardwareTestReport(simulated: false, deviceName: "DeckLink Duo 2", deviceID: "abcd1234", preset: "quick", startedAt: "2027-01-15T08:00:00Z")
        report.environment = environment(font: nil)
        let data = try JSONEncoder().encode(report)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(!(try #require(json["environment"] as? [String: Any])).keys.contains("outputFont"))
        let back = try JSONDecoder().decode(HardwareTestReport.self, from: data)
        #expect(back.environment?.outputFont == nil)
        #expect(!HardwareTestSummary.render(back).contains("Output font"))
    }

    @Test func theEnvironmentStepRecordsTheFontItWasGiven() async throws {
        let source = HardwareEnvironmentSource(appVersion: "0.0.1", appBuild: "41", displays: { [] },
                                               system: { HardwareSystemInfo(osVersion: "27", osBuild: "x", macModel: "m", chip: "c", memoryBytes: 1 << 30, processorCount: 4) },
                                               outputFont: "Inter (bundled)")
        #expect(source.outputFont == "Inter (bundled)")
    }
}
