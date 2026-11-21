// CUE-001 (AUTO-01, AUTO-02): runs lists of actions against a target. Foundation only.
//
// The executor is a plain state machine with no timers of its own. `run` delivers the first stage at once and
// remembers the stages that follow a `wait`; the app calls `tick()` from its own timer (at `nextDueTime`) and the
// executor delivers whatever has become due. The clock is injected, so tests need no real waiting.
import Foundation

public protocol CueClock: Sendable {
    /// Seconds on a monotonic scale. Only differences matter.
    func now() -> TimeInterval
}

/// Monotonic system time. It keeps counting while the Mac sleeps, so a waited stage that came due during sleep is
/// delivered on wake. (Whether the hardware clock behaves so on every Mac has not been checked; see the feature doc.)
public struct SystemCueClock: CueClock {
    public init() {}
    public func now() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}

/// Where a run came from. A slide run may not move the show; a new slide run replaces pending stages of the last one.
public enum CueOrigin: Sendable, Equatable, Hashable {
    case slide
    /// A button, a MIDI binding, the remote API.
    case operatorTrigger
    case schedule
    case marker
}

/// What the app implements. A stage is delivered as `beginBatch`, one `perform` per action, `endBatch`, so the app can
/// publish one snapshot for the whole stage. `perform` throws to report a failure; the executor carries on with the
/// remaining actions.
@MainActor
public protocol CueTarget: AnyObject {
    func beginBatch()
    func perform(_ action: CueAction) throws
    func endBatch()
    /// FIX-E: true when a Blackout toggle would now switch Blackout ON (it then cancels waiting steps, like Blackout on).
    func blackoutWillTurnOn() -> Bool
}

public extension CueTarget {
    func blackoutWillTurnOn() -> Bool { false }
}

/// An error whose text is shown to the operator as is.
public struct CueTargetError: Error, Sendable, Equatable {
    public var message: String
    public init(_ message: String) { self.message = message }
}

public struct CueIssue: Sendable, Equatable {
    public var action: CueAction?
    /// Operator-readable.
    public var message: String
    public init(action: CueAction?, message: String) {
        self.action = action
        self.message = message
    }
}

/// What happened during one call of `run` or `tick`, including queued runs that were delivered during it.
public struct CueReport: Sendable, Equatable {
    public var batchesDelivered: Int
    public var actionsDelivered: Int
    public var issues: [CueIssue]
    /// True for a `run` that arrived while another batch was running; its work is in the outer call's report.
    public var wasQueued: Bool

    public init(batchesDelivered: Int = 0, actionsDelivered: Int = 0, issues: [CueIssue] = [], wasQueued: Bool = false) {
        self.batchesDelivered = batchesDelivered
        self.actionsDelivered = actionsDelivered
        self.issues = issues
        self.wasQueued = wasQueued
    }
}

@MainActor
public final class CueExecutor {
    public var macros: MacroLibrary

    /// FIX-E: when true, a delivered Clear, Clear all or Blackout on also drops the other runs' waited stages, as Stop always
    /// does. Off by default (the engine's own rule, pinned by its tests); the app turns it on.
    public var cancelsWaitingStepsOnClear = false

    private let target: any CueTarget
    private let clock: any CueClock

    private struct PendingStage {
        var runID: Int
        var origin: CueOrigin
        var due: TimeInterval
        var sequence: Int
        var actions: [CueAction]
    }
    private struct Job { var actions: [CueAction]; var origin: CueOrigin }

    private var pending: [PendingStage] = []
    private var inbox: [Job] = []
    private var executing = false
    private var nextRunID = 0
    private var nextSequence = 0

    public init(target: any CueTarget, clock: any CueClock, macros: MacroLibrary = MacroLibrary()) {
        self.target = target
        self.clock = clock
        self.macros = macros
    }

    public var pendingStageCount: Int { pending.count }

    /// When the next waited stage comes due, on the clock's scale. The app sets a timer for this.
    public var nextDueTime: TimeInterval? { pending.map(\.due).min() }

    /// Cancels every waited stage. The app calls this when the show stops by other means than a stop action.
    public func stop() { cancelWaiting() }

    /// FIX-E: how many waited steps were dropped since the last `takeCancelledStepCount()`. The app reads it to say so.
    public private(set) var cancelledStepCount = 0

    public func takeCancelledStepCount() -> Int {
        defer { cancelledStepCount = 0 }
        return cancelledStepCount
    }

    /// Drops every waited stage (except those of the run `runID`, which is the run that is doing the cancelling) and
    /// returns how many steps that was. Stop, Clear, Clear all and Blackout on do this, from any source.
    @discardableResult
    public func cancelWaiting(except runID: Int? = nil) -> Int {
        let dropped = pending.filter { $0.runID != runID }.reduce(0) { $0 + $1.actions.count }
        pending.removeAll { $0.runID != runID }
        cancelledStepCount += dropped
        return dropped
    }

    /// Runs a list. The first stage is delivered before this returns, unless another batch is running: then the run is
    /// queued and delivered right after that batch, in arrival order.
    @discardableResult
    public func run(_ actions: [CueAction], origin: CueOrigin) -> CueReport {
        inbox.append(Job(actions: actions, origin: origin))
        if executing { return CueReport(wasQueued: true) }
        executing = true
        defer { executing = false }
        var report = CueReport()
        drain(&report)
        return report
    }

    /// Delivers every waited stage that has come due, oldest first, each in its own batch.
    @discardableResult
    public func tick() -> CueReport {
        if executing { return CueReport(wasQueued: true) }
        executing = true
        defer { executing = false }
        var report = CueReport()
        let now = clock.now()
        while let i = nextDueIndex(by: now) {
            let stage = pending.remove(at: i)
            deliver(stage.actions, runID: stage.runID, into: &report)
            drain(&report)
        }
        return report
    }

    private func nextDueIndex(by now: TimeInterval) -> Int? {
        var best: Int?
        for i in pending.indices where pending[i].due <= now {
            if let b = best {
                let (p, q) = (pending[i], pending[b])
                if (p.due, p.sequence) < (q.due, q.sequence) { best = i }
            } else {
                best = i
            }
        }
        return best
    }

    private func drain(_ report: inout CueReport) {
        while !inbox.isEmpty {
            let job = inbox.removeFirst()
            start(job, into: &report)
        }
    }

    private func start(_ job: Job, into report: inout CueReport) {
        if job.origin == .slide { pending.removeAll { $0.origin == .slide } }
        let plan = makePlan(job.actions, origin: job.origin)
        report.issues.append(contentsOf: plan.issues)

        let runID = nextRunID
        nextRunID += 1
        let now = clock.now()
        var immediate: [[CueAction]] = []
        for stage in plan.stages {
            if stage.delay == 0 {
                immediate.append(stage.actions)
            } else {
                pending.append(PendingStage(runID: runID, origin: job.origin, due: now + stage.delay, sequence: nextSequence, actions: stage.actions))
                nextSequence += 1
            }
        }
        for actions in immediate { deliver(actions, runID: runID, into: &report) }
    }

    private func deliver(_ actions: [CueAction], runID: Int, into report: inout CueReport) {
        if cancelsWaitingSteps(actions) { cancelWaiting(except: runID) }
        target.beginBatch()
        for a in actions {
            do { try target.perform(a) }
            catch {
                let text = (error as? CueTargetError)?.message ?? error.localizedDescription
                report.issues.append(CueIssue(action: a, message: "\(a.summary) failed: \(text)"))
            }
        }
        target.endBatch()
        report.batchesDelivered += 1
        report.actionsDelivered += actions.count
    }

    private func cancelsWaitingSteps(_ actions: [CueAction]) -> Bool {
        actions.contains { action in
            switch action {
            case .transport(.stop): return true
            case .transport(.clear), .transport(.clearAll), .transport(.blackout(.on)): return cancelsWaitingStepsOnClear
            case .transport(.blackout(.toggle)): return cancelsWaitingStepsOnClear && target.blackoutWillTurnOn()
            default: return false
            }
        }
    }

    // MARK: Planning

    private struct Plan {
        var stages: [(delay: TimeInterval, actions: [CueAction])] = []
        var issues: [CueIssue] = []
    }

    /// Order inside one stage. Transport first (a slide or Look change should come before what it decorates), then the
    /// order the brief gives: Look, props and messages, media, audio, timers, MIDI out.
    private static func rank(_ a: CueAction) -> Int {
        switch a {
        case .transport: return 0
        case .selectLook: return 1
        case .prop, .showMessage, .hideMessage: return 2
        case .playForeground, .setBackground, .stopForeground: return 3
        case .playAudio, .stopAudio: return 4
        case .startTimer, .pauseTimer, .resetTimer: return 5
        case .midiOut: return 6
        case .runMacro, .wait, .unknown: return 7        // never reach a stage; kept total for safety
        }
    }

    private func makePlan(_ actions: [CueAction], origin: CueOrigin) -> Plan {
        var plan = Plan()
        var current: [CueAction] = []
        var stageDelay: TimeInterval = 0
        var elapsed: TimeInterval = 0

        func flush() {
            guard !current.isEmpty else { return }
            let ordered = current.enumerated().sorted { l, r in
                let (a, b) = (Self.rank(l.element), Self.rank(r.element))
                return a != b ? a < b : l.offset < r.offset
            }.map(\.element)
            plan.stages.append((stageDelay, ordered))
            current = []
        }

        func handle(_ action: CueAction, stack: [Macro]) {
            switch action {
            case .wait(let s):
                var d = s
                if !s.isFinite || s < 0 {
                    plan.issues.append(CueIssue(action: action, message: "Wait of \(String(format: "%g", s)) s is not valid; treated as 0 s."))
                    d = 0
                }
                flush()
                elapsed += d
                stageDelay = elapsed

            case .runMacro(let id):
                guard let m = macros.macro(id: id) else {
                    plan.issues.append(CueIssue(action: action, message: "Macro not found (\(id.uuidString)); skipped."))
                    return
                }
                if stack.contains(where: { $0.id == id }) {
                    if stack.last?.id == id {
                        plan.issues.append(CueIssue(action: action, message: "Macro \u{201C}\(m.name)\u{201D} calls itself; the repeat was skipped."))
                    } else {
                        let path = (stack.drop { $0.id != id } + [m]).map(\.name).joined(separator: " \u{2192} ")
                        plan.issues.append(CueIssue(action: action, message: "Macro cycle: \(path); the repeat was skipped."))
                    }
                    return
                }
                if stack.count + 1 > MacroLibrary.maxDepth {
                    plan.issues.append(CueIssue(action: action, message: "Macro \u{201C}\(m.name)\u{201D} was skipped: macros nest at most \(MacroLibrary.maxDepth) levels deep."))
                    return
                }
                for step in m.steps { handle(step, stack: stack + [m]) }

            case .transport where origin == .slide:
                plan.issues.append(CueIssue(action: action, message: "\(action.summary) was skipped: slide actions cannot move the show."))

            case .unknown:
                plan.issues.append(CueIssue(action: action, message: "\(action.summary) was skipped (it may have been written by a newer version)."))

            case .midiOut(let m) where !m.isValid:
                plan.issues.append(CueIssue(action: action, message: "\(action.summary) was skipped: the message is not valid."))

            default:
                current.append(action)
            }
        }

        for a in actions { handle(a, stack: []) }
        flush()
        return plan
    }
}
