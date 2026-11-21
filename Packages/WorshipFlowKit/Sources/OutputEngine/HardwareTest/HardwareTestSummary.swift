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

    public static func render(_ report: HardwareTestReport, detail: Detail = .brief) -> String {
        var lines: [String] = []
        if report.simulated {
            lines.append("SIMULATED RUN: no real card was used, so none of these numbers say anything about real hardware.")
        } else {
            lines.append("WORSHIPFLOW hardware test report")
        }
        let device = report.deviceName ?? "none found"
        lines.append("Device tested: \(device) (\(report.simulated ? "SIMULATED, no real card" : "real hardware"))")
        lines.append(HardwareTestReport.disclaimer)
        if !report.complete {
            lines.append("INCOMPLETE: the test did not finish. Only the steps listed below were recorded.")
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
        lines.append("")
        lines.append("DETAILS")
        for step in report.steps {
            lines.append("")
            lines.append("\(step.number). \(step.title): \(step.outcome.label)")
            lines.append("  \(step.summary)")
            if !step.passCriteria.isEmpty { lines.append("  Pass criteria: \(step.passCriteria)") }
            let everything = detail == .full || step.outcome == .failed || step.outcome == .needsHuman
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
            lines.append("  WORSHIPFLOW \(env.appVersion) (\(env.appBuild)), macOS \(env.osVersion) (\(env.osBuild)), \(env.macModel), \(env.chip), \(String(format: "%.0f", env.memoryGB)) GB")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func totals(_ report: HardwareTestReport) -> String {
        func n(_ o: HardwareTestOutcome) -> Int { report.steps.filter { $0.outcome == o }.count }
        return "\(n(.passed)) passed, \(n(.failed)) failed, \(n(.skipped)) skipped, \(n(.needsHuman)) needs a person"
    }
}
