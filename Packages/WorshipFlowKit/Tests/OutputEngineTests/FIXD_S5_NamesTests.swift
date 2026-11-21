// FIX-D S5: names that identify a person or a Mac are scrubbed from display and device names, and the card's id is a short hash.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_S5_NamesTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theSameCardAlwaysGivesTheSameShortIdAndTwoCardsDiffer() async {
        let report = await runSteps([.environment])
        #expect(report.deviceID == HardwareTestHash.short(HardwareTestRig.simulatedDeviceID))
        #expect(HardwareTestHash.short("a") != HardwareTestHash.short("b"))
    }

    @Test func theNamesOfAPersonAndAMacAreScrubbedFromDisplayAndDeviceNames() throws {
        let dir = try scratch(); defer { try? FileManager.default.removeItem(at: dir) }
        let redactor = HardwareTestRedactor(homePath: "/Users/jane", userName: "jane", extraTerms: ["Jane Q. Pastor", "Pastor Dave's iMac", "stjohns-mac-mini"])
        let writer = try HardwareTestBundleWriter(directory: dir.appendingPathComponent("work"), redactor: redactor)
        var report = HWTestSamples.report()
        report.environment = HardwareEnvironmentInfo(
            appVersion: "1", appBuild: "1", osVersion: "27", osBuild: "x", macModel: "Mac16,10", chip: "M4", memoryGB: 16, processorCount: 10,
            displays: [HardwareDisplayInfo(name: "Pastor Dave's iMac", pixelWidth: 4480, pixelHeight: 2520, scale: 2, refreshRateHz: 60)],
            driver: HardwareDriverStatus(isInstalled: true, message: "ok"), collectedAt: "2026-11-21T10:00:00Z")
        report.deviceName = "DeckLink Duo 2 (stjohns-mac-mini)"
        let zip = dir.appendingPathComponent("o.zip")
        try writer.finish(report: report, log: "owner Jane Q. Pastor on stjohns-mac-mini\n", zipTo: zip)
        for entry in try (try HardwareTestZip.read(from: zip)) {
            let text = String(decoding: entry.data, as: UTF8.self)
            for leak in ["Pastor Dave", "Jane Q", "stjohns"] { #expect(!text.contains(leak), "\(leak) in \(entry.name)") }
        }
        // ordinary display names are kept
        let loaded = try HardwareTestBundle.load(from: zip)
        #expect(loaded.report.environment?.displays.first?.name == "<name>")
        let plain = HardwareTestRedactor(homePath: "/Users/jane", userName: "jane", extraTerms: ["Pastor Dave's iMac"])
        #expect(plain.scrub("Built-in Retina Display, LG UltraFine") == "Built-in Retina Display, LG UltraFine")
    }
}
}
