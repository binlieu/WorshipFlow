// UI-006g (CU-22): what a run would do, worked out without doing it. Foundation only.
import Foundation

/// The plan of a run: stages in the order the executor delivers them, with the seconds after the start each is due.
/// Nothing is delivered, queued or timed; it is a read of the same plan `run` makes.
public struct CueDryRun: Sendable, Equatable {
    public struct Stage: Sendable, Equatable {
        /// Seconds after the run starts.
        public var delay: TimeInterval
        /// In delivery order (a step that moves the show first, then the Look, props, media, sound, timers, MIDI).
        public var actions: [CueAction]
    }

    public var stages: [Stage]
    /// What the executor would report as skipped or wrong (a missing macro, a cycle, an unknown action, a transport step in a slide run).
    public var issues: [CueIssue]

    public var actionCount: Int { stages.reduce(0) { $0 + $1.actions.count } }
    /// Seconds until the last stage is due; 0 when nothing waits.
    public var totalDuration: TimeInterval { stages.map(\.delay).max() ?? 0 }
}

extension CueExecutor {
    /// The plan `run(actions, origin:)` would make now, with this executor's macro library. Changes nothing.
    public func dryRun(_ actions: [CueAction], origin: CueOrigin) -> CueDryRun {
        let plan = makePlan(actions, origin: origin)
        return CueDryRun(stages: plan.stages.map { CueDryRun.Stage(delay: $0.delay, actions: $0.actions) }, issues: plan.issues)
    }
}
