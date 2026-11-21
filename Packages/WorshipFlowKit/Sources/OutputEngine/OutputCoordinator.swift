// OUT-002: starts, stops and re-plans outputs from the routing plan, and reports each screen's status to the operator.
// Displays and output construction are injected so tests can use fakes. Never moves a screen to another display.
import Foundation
import Domain
import RenderEngine

/// What the coordinator needs to know about the attached displays.
public struct DisplaySnapshot: Sendable, Equatable {
    public var available: [UInt32]
    public var operatorDisplay: UInt32?

    public init(available: [UInt32], operatorDisplay: UInt32?) {
        self.available = available
        self.operatorDisplay = operatorDisplay
    }
}

public enum ScreenState: Sendable, Equatable {
    case stopped
    case running
    /// The output runs but its window is covered, so no frames are presented (KI-008).
    case hidden
    case faulted(String)
}

public struct ScreenReadout: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var role: ScreenRole
    public var destination: OutputDestination
    public var isEnabled: Bool
    public var state: ScreenState
    public var refreshRate: Double
    public var presented: Int
    public var dropped: Int
    public var late: Int
    public var maxIntervalMs: Double
    public var renderError: String?
    /// Image files this screen could not draw (OUT-003).
    public var unavailableImagePaths: [String] = []
    /// Layers this screen skipped because they could not be drawn (R2). Empty when the last frame had none.
    public var renderProblems: [String] = []
}

@MainActor
public final class OutputCoordinator {
    public typealias DisplayProvider = @MainActor () -> DisplaySnapshot
    public typealias TargetFactory = @MainActor (ScreenProfile, OutputDestination) throws -> any OutputTarget

    public static let hiddenMessage = "Hidden: another window or a full-screen app is covering this output. Nothing is being presented until it is visible again."

    public private(set) var profiles: [ScreenProfile]
    /// True from `start()` (or a single-screen restart) until `stop()`.
    public private(set) var isActive = false
    /// Called after any change in what is running or faulted.
    public var onChange: (@MainActor () -> Void)?

    private struct Running {
        let target: any OutputTarget
        let destination: OutputDestination
    }

    private let displays: DisplayProvider
    private let makeTarget: TargetFactory
    private let sleepGuard: SleepGuard?
    private var running: [UUID: Running] = [:]
    private var faults: [UUID: String] = [:]
    /// Screens whose display disappeared. They resume only when that same display returns.
    private var resumeOnReturn: Set<UUID> = []

    public init(profiles: [ScreenProfile] = [], displays: @escaping DisplayProvider, makeTarget: @escaping TargetFactory,
                sleepGuard: SleepGuard? = nil) {
        self.profiles = profiles
        self.displays = displays
        self.makeTarget = makeTarget
        self.sleepGuard = sleepGuard
    }

    public var runningCount: Int { running.count }

    /// Compiles the shaders and builds the render pipeline ahead of time, on a background thread (R16). Call it once
    /// at launch: starting screens then never compiles on the main thread, however many open. Returns at once.
    public nonisolated static func warmUp() {
        Task.detached(priority: .utility) { Compositor.warmUp() }
    }

    private func currentPlan() -> RoutingPlan {
        let d = displays()
        return OutputRouter.plan(profiles: profiles, availableDisplays: d.available, operatorDisplay: d.operatorDisplay)
    }

    // MARK: Operator actions

    /// Starts every enabled screen the plan allows. Faulted screens report why.
    public func start() {
        isActive = true
        let plan = currentPlan()
        for profile in profiles where profile.isEnabled && running[profile.id] == nil {
            begin(profile, plan: plan)
        }
        finishChange()
    }

    /// Stops every output and clears faults.
    public func stop() {
        isActive = false
        for id in Array(running.keys) { stopTarget(id) }
        faults.removeAll()
        resumeOnReturn.removeAll()
        finishChange()
    }

    /// Operator restart of one screen, the way out of a fault.
    public func restart(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        isActive = true
        stopTarget(id)
        faults[id] = nil
        resumeOnReturn.remove(id)
        if profile.isEnabled { begin(profile, plan: currentPlan()) }
        finishChange()
    }

    /// Operator stop of one screen.
    public func stop(_ id: UUID) {
        stopTarget(id)
        faults[id] = nil
        resumeOnReturn.remove(id)
        finishChange()
    }

    /// Replaces the profiles. Only screens whose role, destination or enabled flag changed are touched;
    /// a rename restarts nothing.
    public func setProfiles(_ new: [ScreenProfile]) {
        let old = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        profiles = new
        let ids = Set(new.map(\.id))
        for id in old.keys where !ids.contains(id) {
            stopTarget(id); faults[id] = nil; resumeOnReturn.remove(id)
        }
        var changed: [ScreenProfile] = []
        for profile in new {
            guard let before = old[profile.id] else { changed.append(profile); continue }
            if before.role != profile.role || before.destination != profile.destination || before.isEnabled != profile.isEnabled {
                changed.append(profile)
            }
        }
        for profile in changed {
            stopTarget(profile.id)
            faults[profile.id] = nil
            resumeOnReturn.remove(profile.id)
        }
        if isActive {
            let plan = currentPlan()
            for profile in changed where profile.isEnabled { begin(profile, plan: plan) }
        }
        finishChange()
    }

    /// Call when displays were added or removed. Stops only the outputs whose assignment changed; a screen whose
    /// display returns resumes on that same display, and is never redirected to another.
    public func displaysChanged() {
        guard isActive else { return }
        let plan = currentPlan()
        for profile in profiles where profile.isEnabled {
            let id = profile.id
            if let r = running[id] {
                if plan.assignments[id] != r.destination {
                    stopTarget(id)
                    if let fault = plan.faults[id] {
                        faults[id] = fault.operatorMessage
                        if fault == .displayMissing { resumeOnReturn.insert(id) }
                    }
                }
            } else if let destination = plan.assignments[id] {
                if resumeOnReturn.contains(id) {
                    resumeOnReturn.remove(id)
                    faults[id] = nil
                    startTarget(profile, destination: destination)
                }
            } else if faults[id] != nil, let fault = plan.faults[id] {
                // Already faulted: refresh the message. A screen the operator stopped (no fault) is left alone.
                faults[id] = fault.operatorMessage
            }
        }
        finishChange()
    }

    // MARK: Status

    public func readouts() -> [ScreenReadout] {
        profiles.map { profile in
            let id = profile.id
            var readout = ScreenReadout(id: id, name: profile.name, role: profile.role, destination: profile.destination,
                                        isEnabled: profile.isEnabled, state: .stopped, refreshRate: 0, presented: 0,
                                        dropped: 0, late: 0, maxIntervalMs: 0, renderError: nil)
            if let r = running[id] {
                let s = r.target.statistics
                readout.state = r.target.isOccluded ? .hidden : .running
                readout.refreshRate = r.target.refreshRate
                readout.presented = s.presentedFrames
                readout.dropped = s.droppedFrames
                readout.late = s.lateFrames
                readout.maxIntervalMs = s.maxInterval * 1000
                readout.renderError = r.target.lastRenderError
                readout.unavailableImagePaths = r.target.unavailableImagePaths
                readout.renderProblems = r.target.renderProblems
            } else if let message = faults[id] {
                readout.state = .faulted(message)
            }
            return readout
        }
    }

    public func diagnostics(for id: UUID) -> String? { running[id]?.target.diagnostics }

    // MARK: Internals

    private func begin(_ profile: ScreenProfile, plan: RoutingPlan) {
        if let destination = plan.assignments[profile.id] {
            faults[profile.id] = nil
            startTarget(profile, destination: destination)
        } else if let fault = plan.faults[profile.id] {
            faults[profile.id] = fault.operatorMessage
            if fault == .displayMissing { resumeOnReturn.insert(profile.id) }
        }
    }

    private func startTarget(_ profile: ScreenProfile, destination: OutputDestination) {
        do {
            let target = try makeTarget(profile, destination)
            let id = profile.id
            target.onStatusChange = { [weak self] status in self?.targetChanged(id, status) }
            running[id] = Running(target: target, destination: destination)
            do {
                try target.start()
            } catch {
                target.onStatusChange = nil
                running[id] = nil
                faults[id] = "Could not start this screen: \(error.localizedDescription)"
            }
        } catch {
            faults[profile.id] = "Could not start this screen: \(error.localizedDescription)"
        }
    }

    private func stopTarget(_ id: UUID) {
        guard let r = running.removeValue(forKey: id) else { return }
        r.target.onStatusChange = nil
        r.target.stop()
    }

    /// A target stopped on its own (window closed, display unplugged).
    private func targetChanged(_ id: UUID, _ status: OutputStatus) {
        guard case .stopped(let reason) = status, let r = running[id], case .stopped = r.target.status else { return }
        running[id] = nil
        r.target.onStatusChange = nil
        if let reason {
            faults[id] = reason
            if case .display(let displayID) = r.destination, !displays().available.contains(displayID) {
                resumeOnReturn.insert(id)
            }
        }
        finishChange()
    }

    private func finishChange() {
        sleepGuard?.update(runningCount: running.count)
        onChange?()
    }
}
