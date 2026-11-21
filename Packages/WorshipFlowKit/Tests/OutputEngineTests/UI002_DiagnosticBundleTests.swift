// UI-002 Part 2: "Export log bundle…" saves the environment and device steps of the hardware test, with no video run.
import Testing
import Foundation
import SDIEngine
@testable import OutputEngine

@Suite struct UI002_DiagnosticBundleTests {
    @Test func theBundleHoldsTheEnvironmentAndDeviceStepsOnly() {
        #expect(DiagnosticBundle.steps().map(\.id) == [.environment, .devices])
        #expect(DiagnosticBundle.steps().allSatisfy { !$0.needsDevice })
    }

    @Test func exportWritesAReadableBundleWithoutRunningAnyOutput() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ui002-bundle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let out = dir.appendingPathComponent("diag.zip")
        let rig = HardwareTestRig.simulated()
        let code = await DiagnosticBundle.export(to: out, environment: .fixed, provider: rig.provider)
        #expect(code == 0)
        let loaded = try HardwareTestBundle.load(from: out)
        #expect(loaded.report.steps.map(\.id) == [.environment, .devices])
        #expect(loaded.report.steps.allSatisfy { $0.outcome != .failed })
    }
}
