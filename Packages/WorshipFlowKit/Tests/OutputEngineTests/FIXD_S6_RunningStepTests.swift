// FIX-D S6: the files of a run say which step is running before the step starts, so a crash inside it leaves a report that
// says where it stopped. Uses only the JSON on disk, so it runs against the earlier kit too.
import Testing
import Foundation
@testable import OutputEngine

extension HWTEST_Heavy {
@Suite struct FIXD_S6_RunningStepTests {
    @Test func theFileNamesTheRunningStepBeforeTheStepStartsAndNothingAfterTheEnd() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wf-fixd-run-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try HardwareTestBundleWriter(directory: dir)
        final class Seen: @unchecked Sendable { let lock = NSLock(); var rows: [(Int?, String?, Int)] = []
            func add(_ r: (Int?, String?, Int)) { lock.lock(); rows.append(r); lock.unlock() } }
        let seen = Seen()
        let steps = [1, 2].map { n in
            HardwareTestStep(id: HardwareTestStepID.allCases[n - 1], number: n, title: "Step \(n)", timeoutSeconds: 5) { _ in
                // what the file on disk says while this step runs: the running step, and how many steps are finished
                let data = try Data(contentsOf: dir.appendingPathComponent("report.json"))
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                seen.add((json?["runningStep"] as? Int, json?["runningStepTitle"] as? String, (json?["steps"] as? [Any])?.count ?? -1))
                return HardwareStepOutput(outcome: .passed, summary: "ok")
            }
        }
        let rig = HardwareTestRig.simulated()
        let runner = HardwareTestRunner(provider: rig.provider, configuration: .tiny, clock: rig.clock, interaction: rig.interaction,
                                        environment: .fixed, resources: FixedResources.probe,
                                        bundle: HardwareTestBundleTarget(writer: writer, zipURL: nil), steps: steps)
        _ = await runner.run()
        #expect(seen.rows.map { $0.0 } == [1, 2], "\(seen.rows)")
        #expect(seen.rows.map { $0.1 } == ["Step 1", "Step 2"])
        #expect(seen.rows.map { $0.2 } == [0, 1])
        let end = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("report.json"))) as? [String: Any]
        #expect(end?["runningStep"] == nil && end?["complete"] as? Bool == true)
    }
}
}
