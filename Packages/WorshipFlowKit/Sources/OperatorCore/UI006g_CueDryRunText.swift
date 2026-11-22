// UI-006g (CU-22): the words of a macro's dry run. Foundation and CueEngine only. The run itself is `CueExecutor.dryRun`; this names each
// step as the action list does (`CueActionEditing.describe`) and says when it would be delivered.
import Foundation
import CueEngine

public struct CueDryRunLine: Sendable, Equatable, Identifiable {
    public var id: Int { number }
    /// 1-based, in the order a run delivers them (not always the order written).
    public var number: Int
    public var title: String
    public var detail: String
    public var screens: [CueScreen]
    public var isBroken: Bool
}

public struct CueDryRunGroup: Sendable, Equatable, Identifiable {
    public var id: Int
    /// "Right away" or "After 2 s".
    public var when: String
    public var lines: [CueDryRunLine]
}

public struct CueDryRunSummary: Sendable, Equatable {
    public var headline: String
    public var groups: [CueDryRunGroup]
    /// What the run would skip or could not do, in the engine's words.
    public var issues: [String]
    /// The screens its steps can change, in the order Audience, Stage, Broadcast.
    public var screens: [CueScreen]
    /// Steps that point at something that is gone.
    public var brokenCount: Int
    public var isEmpty: Bool { groups.isEmpty && issues.isEmpty }
}

public enum CueDryRunText {
    public static func summary(_ run: CueDryRun, choices: CueChoices) -> CueDryRunSummary {
        var number = 0
        var screens = Set<CueScreen>()
        var broken = 0
        var groups: [CueDryRunGroup] = []
        for (index, stage) in run.stages.enumerated() {
            var lines: [CueDryRunLine] = []
            for action in stage.actions {
                number += 1
                let row = CueActionEditing.describe(action, choices: choices)
                screens.formUnion(row.screens)
                if row.isBroken { broken += 1 }
                lines.append(CueDryRunLine(number: number, title: row.title, detail: row.detail, screens: row.screens, isBroken: row.isBroken))
            }
            groups.append(CueDryRunGroup(id: index, when: when(stage.delay), lines: lines))
        }
        let ordered = [CueScreen.audience, .stage, .broadcast].filter(screens.contains)
        return CueDryRunSummary(headline: headline(count: run.actionCount, duration: run.totalDuration), groups: groups,
                                issues: run.issues.map(\.message), screens: ordered, brokenCount: broken)
    }

    static func when(_ delay: TimeInterval) -> String { delay == 0 ? "Right away" : "After \(seconds(delay))" }

    static func headline(count: Int, duration: TimeInterval) -> String {
        guard count > 0 else { return "Nothing would run" }
        let noun = "\(count) action\(count == 1 ? "" : "s")"
        return duration == 0 ? "\(noun), all at once" : "\(noun) over \(seconds(duration))"
    }

    private static func seconds(_ s: TimeInterval) -> String { "\(String(format: "%g", (s * 10).rounded() / 10)) s" }
}

extension CueModel {
    /// What Run would do for this macro, read from the same plan the executor makes. Delivers nothing, queues nothing, logs nothing, and
    /// never touches a screen. Nil when the macro is gone.
    public func dryRun(of macroID: UUID, choices: CueChoices) -> CueDryRunSummary? {
        guard library.macro(id: macroID) != nil else { return nil }
        return CueDryRunText.summary(executor.dryRun([.runMacro(macroID)], origin: .operatorTrigger), choices: choices)
    }
}
