// HWTEST-001: the one-page text a person reads. It starts with who was tested and what the report is not, then the
// table of steps and outcomes, then the details. The coordinator can render any loaded report with the same function.
import Foundation

public enum HardwareTestSummary {
    public enum Detail: Sendable {
        /// What is written to `summary.txt`: every failed or unanswered step in full, and the first few measurements of the others.
        case brief
        /// Every measurement of every step. `report.json` always holds all of them; this renders them as text.
        case full
    }

    /// Passed and skipped steps show this many measurements in a brief summary.
    static let briefMeasurementLimit = 6

    /// The steps that send video. The mode sweep asks the device without sending any, so it does not count.
    static let videoSteps: Set<HardwareTestStepID> = [.outputRun, .loopback, .fillKeyLoopback, .fourOutputs, .unplugReplug, .humanChecks]

    /// True when at least one step that sends video ran far enough to measure something (S14).
    public static func videoWasTested(_ report: HardwareTestReport) -> Bool {
        report.steps.contains { videoSteps.contains($0.id) && [.passed, .failed, .partial].contains($0.outcome) }
    }

    /// The first line of the summary: what kind of report this is and what its numbers can be taken to mean.
    public static func headline(_ report: HardwareTestReport) -> String {
        var line: String
        if report.simulated {
            line = "SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware."
        } else if let name = report.deviceName {
            // A report with no step at all is the one written before the first step: it has no numbers to describe.
            line = videoWasTested(report) || report.steps.isEmpty
                ? "REAL DEVICE TESTED: \(name). The numbers below were measured on this card."
                : "DEVICE INFORMATION ONLY: no video test was run. \(name) was listed and asked what it can do; nothing was measured on it."
        } else {
            line = "NO REAL DEVICE WAS TESTED: no DeckLink card was found, so nothing in this report says anything about real hardware."
        }
        // S1: a card left in the keying profile is said in the headline, because every later step's layout depends on it.
        if let restore = report.profileRestore, restore.leftInKeyingProfile {
            let from = report.steps.first { $0.profileNote != nil }?.number
            line += " THE CARD'S PROFILE WAS NOT RESTORED after the fill and key step (\(restore.state == .failed ? "it failed" : "it could not be checked")), so "
                + (from.map { "step \($0) and the steps after it" } ?? "any later step") + " ran in the keying profile."
        }
        if !report.complete {
            line += " THE TEST DID NOT FINISH" + (report.runningStep.map { " (it stopped during step \($0)" + (report.runningStepTitle.map { ", \($0)" } ?? "") + ")" } ?? "") + "."
        }
        return line
    }

    public static func render(_ report: HardwareTestReport, detail: Detail = .brief) -> String {
        var lines: [String] = []
        // The first line says whether a real device was tested, so nobody has to read on to find out. It also says when the
        // test did not finish (S6).
        lines.append(headline(report))
        if report.deviceName != nil {
            let kind = report.simulated ? "SIMULATED, no real card" : "real hardware"
            lines.append((videoWasTested(report) || report.simulated ? "Device tested: " : "Device listed, not tested: ") + "\(report.deviceName ?? "") (\(kind))")
        } else {
            lines.append("Device tested: none found")
        }
        if let start = report.profileAtStart { lines.append("The card's profile before the test: \(start)") }
        lines.append(HardwareTestReport.disclaimer)
        if !report.complete {
            let where_ = report.runningStep.map { n in "It stopped during step \(n)" + (report.runningStepTitle.map { ", \($0)" } ?? "") + "." } ?? "It stopped between steps."
            lines.append("INCOMPLETE: the test did not finish. \(where_) Only the steps listed below were recorded.")
        }
        lines.append("Started \(report.startedAt) UTC" + (report.finishedAt.map { ", finished \($0) UTC" } ?? "")
                     + ". Length chosen: \(report.preset).")
        lines.append("Totals: " + totals(report))
        lines.append("")
        lines.append("STEPS AND OUTCOMES")
        for step in report.steps {
            let name = "\(step.number). \(step.title)"
            lines.append(name.padding(toLength: max(34, name.count + 2), withPad: " ", startingAt: 0) + step.outcome.label)
        }
        // The driver facts are what a reader looks for first when no card was found, so a brief summary shows them
        // whatever else it trims: the driver state, its API version, the entitlement check and the device-reported key route.
        let driverFacts = report.steps.first { $0.id == .environment }?.measurements.filter { m in
            ["Blackmagic driver", "Driver API version", "Driver version", "Framework can be loaded", "Key route reported by the device"].contains { m.name.hasPrefix($0) }
        } ?? []
        if !driverFacts.isEmpty {
            lines.append("")
            lines.append("THE DRIVER AND THE CARD")
            for m in driverFacts { lines.append("  - \(m.name): \(m.value)") }
        }
        lines.append("")
        lines.append("DETAILS")
        for step in report.steps {
            lines.append("")
            lines.append("\(step.number). \(step.title): \(step.outcome.label)")
            lines.append("  \(step.summary)")
            if !step.passCriteria.isEmpty { lines.append("  Pass criteria: \(step.passCriteria)") }
            if let note = step.profileNote { lines.append("  \(note)") }
            let everything = detail == .full || step.outcome == .failed || step.outcome == .needsHuman || step.outcome == .partial
            let shown = everything ? step.measurements : Array(step.measurements.prefix(briefMeasurementLimit))
            for m in shown { lines.append("  - \(m.name): \(m.value)" + (m.unit.map { " \($0)" } ?? "")) }
            if shown.count < step.measurements.count { lines.append("  (\(step.measurements.count - shown.count) more measurements are in report.json)") }
            for e in step.events { lines.append("  * \(e)") }
        }
        let findings = report.steps.flatMap(\.findings)
        if !findings.isEmpty {
            lines.append("")
            lines.append("FINDINGS ON THE UNVERIFIED FACTS")
            for f in findings { lines.append("  - \(f)") }
        }
        if let env = report.environment {
            lines.append("")
            lines.append("MACHINE")
            lines.append("  WorshipFlow \(env.appVersion) (\(env.appBuild))\(env.appBuildDetail.map { ", \($0)" } ?? ""), macOS \(env.osVersion) (\(env.osBuild)), \(env.macModel), \(env.chip), \(String(format: "%.0f", env.memoryGB)) GB")
            if let font = env.outputFont { lines.append("  Output font: \(font)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func totals(_ report: HardwareTestReport) -> String {
        func n(_ o: HardwareTestOutcome) -> Int { report.steps.filter { $0.outcome == o }.count }
        let base = "\(n(.passed)) passed, \(n(.failed)) failed, \(n(.skipped)) skipped, \(n(.needsHuman)) needs a person"
        return n(.partial) > 0 ? base + ", \(n(.partial)) partly measured" : base
    }
}
