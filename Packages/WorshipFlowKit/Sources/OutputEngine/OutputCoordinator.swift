// OUT-002: starts, stops and re-plans outputs from the routing plan, and reports each screen's status to the operator.
// Displays and output construction are injected so tests can use fakes. Never moves a screen to another display.
import Foundation
import Domain
import RenderEngine
import SDIEngine

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

/// The status of one mirror of a screen (OUT-005). A mirror is routed, faulted and counted on its own.
public struct MirrorReadout: Sendable, Equatable, Identifiable {
    public var id: String
    public var index: Int
    public var destination: OutputDestination
    public var state: ScreenState
    public var refreshRate: Double
    public var presented: Int
    public var dropped: Int
    public var late: Int
    public var maxIntervalMs: Double
    public var renderError: String?
    /// Health, repeated frames and warnings of an SDI mirror; nil for a display or window.
    public var sdi: SDIOutputReport?
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
    /// Health, repeated frames and warnings when the primary destination is SDI (HW-002); nil otherwise.
    public var sdi: SDIOutputReport?
    /// One entry per mirror, in the order of `ScreenProfile.mirrors` (OUT-005).
    public var mirrors: [MirrorReadout] = []
}

@MainActor
public final class OutputCoordinator {
    public typealias DisplayProvider = @MainActor () -> DisplaySnapshot
    public typealias TargetFactory = @MainActor (ScreenProfile, OutputDestination) throws -> any OutputTarget
    /// Like `TargetFactory`, and also told which slot (the primary or a mirror) the output is for.
    public typealias SlotTargetFactory = @MainActor (ScreenProfile, OutputSlot, OutputDestination) throws -> any OutputTarget

    public static let hiddenMessage = "Hidden: another window or a full-screen app is covering this output. Nothing is being presented until it is visible again."

    public private(set) var profiles: [ScreenProfile]
    /// True from `start()` (or a single-screen restart) until `stop()`.
    public private(set) var isActive = false
    /// Called after any change in what is running or faulted.
    public var onChange: (@MainActor () -> Void)?

    private struct Running {
        let target: any OutputTarget
        let destination: PlannedDestination
    }

    private let displays: DisplayProvider
    private let makeTarget: SlotTargetFactory
    private let sdi: SDIEnvironment?
    private let sleepGuard: SleepGuard?
    private var running: [OutputSlot: Running] = [:]
    private var faults: [OutputSlot: String] = [:]
    /// Outputs whose display or SDI card disappeared. They resume only when that same display or card returns.
    private var resumeOnReturn: Set<OutputSlot> = []

    public init(profiles: [ScreenProfile] = [], displays: @escaping DisplayProvider, makeTarget: @escaping TargetFactory,
                sleepGuard: SleepGuard? = nil, sdi: SDIEnvironment? = nil) {
        self.profiles = profiles
        self.displays = displays
        self.makeTarget = { profile, _, destination in try makeTarget(profile, destination) }
        self.sleepGuard = sleepGuard
        self.sdi = sdi
    }

    public init(profiles: [ScreenProfile] = [], displays: @escaping DisplayProvider, makeSlotTarget: @escaping SlotTargetFactory,
                sleepGuard: SleepGuard? = nil, sdi: SDIEnvironment? = nil) {
        self.profiles = profiles
        self.displays = displays
        self.makeTarget = makeSlotTarget
        self.sleepGuard = sleepGuard
        self.sdi = sdi
    }

    /// Outputs running now: every screen and every mirror.
    public var runningCount: Int { running.count }

    /// Stopped outputs still held because their teardown has not finished (FIX-V item 4). Tests.
    var retiredCount: Int { retiring.count }

    /// Compiles the shaders and builds the render pipeline ahead of time, on a background thread (R16). Call it once
    /// at launch: starting screens then never compiles on the main thread, however many open. Returns at once.
    public nonisolated static func warmUp() {
        Task.detached(priority: .utility) { Compositor.warmUp() }
    }

    // MARK: Planning

    private func handles() -> [SDIDeviceHandle] { sdi?.devices() ?? [] }

    private func currentPlan() -> OutputPlan {
        let d = displays()
        return OutputPlanner.plan(profiles: profiles, availableDisplays: d.available, operatorDisplay: d.operatorDisplay,
                                  sdiDevices: handles().map(\.status))
    }

    /// The SDI cards the coordinator can see now, connected or not.
    public func sdiDevices() -> [SDIDeviceStatus] { handles().map(\.status) }

    /// What each connector of each card carries according to the screens' settings (the plan, not what is running).
    public func connectorMaps() -> [String: SDIConnectorMap] { currentPlan().connectorMaps }

    private func slots(of profile: ScreenProfile) -> [OutputSlot] {
        [OutputSlot(screenID: profile.id)] + profile.mirrors.indices.map { OutputSlot(screenID: profile.id, mirror: $0) }
    }

    private func slotsOfScreen(_ id: UUID) -> [OutputSlot] {
        profiles.first { $0.id == id }.map(slots(of:)) ?? []
    }

    // MARK: Operator actions

    /// Starts every enabled screen, and its mirrors, that the plan allows. Faulted ones report why.
    public func start() {
        isActive = true
        let plan = currentPlan()
        for profile in profiles where profile.isEnabled {
            for slot in slots(of: profile) where running[slot] == nil { begin(slot, profile, plan: plan) }
        }
        finishChange()
    }

    /// Stops every output and clears faults. With `waitForPorts` (the default) it returns when every SDI port is closed again, so the
    /// connectors are free at once. The app passes false (FIX-T item 6, M6): an SDI output then closes its port on its own queue, the main
    /// actor is not held for it, and the next SDI output waits for it before it opens a port.
    public func stop(waitForPorts: Bool = true) {
        isActive = false
        for slot in Array(running.keys) { stopTarget(slot) }
        faults.removeAll()
        resumeOnReturn.removeAll()
        if waitForPorts { awaitRetiredTargets() }
        finishChange()
    }

    /// Operator restart of one screen (and its mirrors), the way out of a fault.
    public func restart(_ id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        isActive = true
        let own = slots(of: profile)
        for slot in own { forget(slot) }
        if profile.isEnabled {
            let plan = currentPlan()
            for slot in own { begin(slot, profile, plan: plan) }
        }
        finishChange()
    }

    /// FIX-H item 4: Operator restart of one output only: the screen itself, or one of its mirrors. The screen's other outputs keep
    /// running untouched.
    public func restart(slot: OutputSlot) {
        guard let profile = profiles.first(where: { $0.id == slot.screenID }), slots(of: profile).contains(slot) else { return }
        isActive = true
        forget(slot)
        if profile.isEnabled { begin(slot, profile, plan: currentPlan()) }
        finishChange()
    }

    /// Operator stop of one screen and its mirrors. `waitForPorts` as for `stop(waitForPorts:)`.
    public func stop(_ id: UUID, waitForPorts: Bool = true) {
        for slot in slotsOfScreen(id) { forget(slot) }
        if waitForPorts { awaitRetiredTargets() }
        finishChange()
    }

    private func forget(_ slot: OutputSlot) {
        stopTarget(slot)
        faults[slot] = nil
        resumeOnReturn.remove(slot)
    }

    private struct SlotSignature: Equatable {
        var role: ScreenRole
        var destination: OutputDestination
        /// Only SDI destinations depend on the mode.
        var mode: VideoModeDescription?
    }

    private func signatures(_ list: [ScreenProfile]) -> [OutputSlot: SlotSignature] {
        var result: [OutputSlot: SlotSignature] = [:]
        for profile in list where profile.isEnabled {
            let all = [profile.destination] + profile.mirrors
            for (i, destination) in all.enumerated() {
                let slot = OutputSlot(screenID: profile.id, mirror: i == 0 ? nil : i - 1)
                result[slot] = SlotSignature(role: profile.role, destination: destination, mode: destination.isSDI ? profile.videoMode : nil)
            }
        }
        return result
    }

    /// Replaces the profiles. Only the outputs whose role, destination, mode or enabled state changed are touched; a
    /// rename restarts nothing, and a change to one mirror leaves the primary and the other mirrors running.
    public func setProfiles(_ new: [ScreenProfile]) {
        let before = signatures(profiles)
        profiles = new
        let after = signatures(new)
        var changed: [OutputSlot] = []
        for (slot, signature) in before where after[slot] != signature { forget(slot) }
        for (slot, signature) in after where before[slot] != signature { changed.append(slot) }
        // Faults and stopped outputs of slots that no longer exist (a removed screen or mirror) go too.
        let valid = Set(new.flatMap { slots(of: $0) })
        for slot in Array(faults.keys) where !valid.contains(slot) { faults[slot] = nil }
        for slot in Array(resumeOnReturn) where !valid.contains(slot) { resumeOnReturn.remove(slot) }
        for slot in Array(running.keys) where !valid.contains(slot) { forget(slot) }
        for slot in changed { faults[slot] = nil; resumeOnReturn.remove(slot) }
        if isActive {
            let plan = currentPlan()
            for slot in changed {
                if let profile = new.first(where: { $0.id == slot.screenID }) { begin(slot, profile, plan: plan) }
            }
        }
        finishChange()
    }

    /// Call when displays were added or removed. Stops only the outputs whose assignment changed; an output whose display
    /// returns resumes on that same display, and is never redirected to another.
    public func displaysChanged() {
        guard isActive else { return }
        let plan = currentPlan()
        for slot in plan.slots {
            guard let profile = profiles.first(where: { $0.id == slot.screenID }) else { continue }
            if let r = running[slot] {
                if plan.assignments[slot] != r.destination {
                    stopTarget(slot)
                    if let fault = plan.faults[slot] {
                        faults[slot] = fault.operatorMessage
                        if fault.resumesWhenItReturns { resumeOnReturn.insert(slot) }
                    } else if let now = plan.assignments[slot] {
                        // FIX-C S16: the plan now puts this output somewhere else (for example the card reports fill and
                        // key the other way round). Never stop it silently, and never move it without the operator: say what
                        // changed. It does not resume by itself; restarting it uses the new assignment.
                        faults[slot] = Self.assignmentChangedMessage(was: r.destination, now: now)
                    }
                }
            } else if let planned = plan.assignments[slot] {
                if resumeOnReturn.contains(slot) {
                    resumeOnReturn.remove(slot)
                    faults[slot] = nil
                    startTarget(slot, profile, planned: planned)
                }
            } else if faults[slot] != nil, let fault = plan.faults[slot] {
                // Already faulted: refresh the message. An output the operator stopped (no fault) is left alone.
                faults[slot] = fault.operatorMessage
            }
        }
        finishChange()
    }

    /// What the operator reads when a running output's destination changed under it.
    static func assignmentChangedMessage(was: PlannedDestination, now: PlannedDestination) -> String {
        "The destination of this screen changed while it was running: it was \(describe(was)); the settings now put it on \(describe(now)). "
            + "It was stopped so it does not send a picture to the wrong place. Restart this screen to use the new destination."
    }

    private static func describe(_ destination: PlannedDestination) -> String {
        switch destination {
        case .display(let id): return "display \(id)"
        case .window: return "a window"
        case .sdi(let o):
            if o.keyConnector != nil {
                let key = o.keyConnector.map(String.init) ?? "?"
                return "SDI fill on connector \(o.fillConnector) and key on connector \(key) of card \(o.deviceID), \(o.mode.name)"
            }
            return "SDI connector \(o.connector) of card \(o.deviceID), \(o.mode.name)"
        }
    }

    /// Call when an SDI card appeared, disappeared or came back. Same rules as for displays.
    public func devicesChanged() { displaysChanged() }

    // MARK: Status

    public func readouts() -> [ScreenReadout] {
        profiles.map { profile in
            let primary = slotReadout(OutputSlot(screenID: profile.id), destination: profile.destination)
            var readout = ScreenReadout(id: profile.id, name: profile.name, role: profile.role, destination: profile.destination,
                                        isEnabled: profile.isEnabled, state: primary.state, refreshRate: primary.refreshRate,
                                        presented: primary.presented, dropped: primary.dropped, late: primary.late,
                                        maxIntervalMs: primary.maxIntervalMs, renderError: primary.renderError)
            readout.unavailableImagePaths = primary.unavailableImagePaths
            readout.renderProblems = primary.renderProblems
            readout.sdi = primary.sdi
            readout.mirrors = profile.mirrors.enumerated().map { i, destination in
                let m = slotReadout(OutputSlot(screenID: profile.id, mirror: i), destination: destination)
                return MirrorReadout(id: "\(profile.id.uuidString)-mirror-\(i)", index: i, destination: destination, state: m.state,
                                     refreshRate: m.refreshRate, presented: m.presented, dropped: m.dropped, late: m.late,
                                     maxIntervalMs: m.maxIntervalMs, renderError: m.renderError, sdi: m.sdi)
            }
            return readout
        }
    }

    private struct SlotReadout {
        var state: ScreenState = .stopped
        var refreshRate = 0.0
        var presented = 0, dropped = 0, late = 0
        var maxIntervalMs = 0.0
        var renderError: String?
        var unavailableImagePaths: [String] = []
        var renderProblems: [String] = []
        var sdi: SDIOutputReport?
    }

    private func slotReadout(_ slot: OutputSlot, destination: OutputDestination) -> SlotReadout {
        var readout = SlotReadout()
        if let r = running[slot] {
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
            readout.sdi = r.target.sdiReport
        } else if let message = faults[slot] {
            readout.state = .faulted(message)
        }
        return readout
    }

    public func diagnostics(for id: UUID) -> String? { running[OutputSlot(screenID: id)]?.target.diagnostics }

    // MARK: Internals

    private func begin(_ slot: OutputSlot, _ profile: ScreenProfile, plan: OutputPlan) {
        if let planned = plan.assignments[slot] {
            faults[slot] = nil
            startTarget(slot, profile, planned: planned)
        } else if let fault = plan.faults[slot] {
            faults[slot] = fault.operatorMessage
            if fault.resumesWhenItReturns { resumeOnReturn.insert(slot) }
        }
    }

    private func startTarget(_ slot: OutputSlot, _ profile: ScreenProfile, planned: PlannedDestination) {
        do {
            let target: any OutputTarget
            switch planned {
            case .display(let id): target = try makeTarget(profile, slot, .display(id))
            case .window: target = try makeTarget(profile, slot, .window)
            case .sdi(let output):
                awaitRetiredTargets()
                target = try makeSDITarget(profile, slot, output)
            }
            target.onStatusChange = { [weak self] status in self?.targetChanged(slot, status) }
            running[slot] = Running(target: target, destination: planned)
            do {
                try target.start()
            } catch {
                target.onStatusChange = nil
                running[slot] = nil
                faults[slot] = "Could not start this screen: \(error.localizedDescription)"
            }
        } catch {
            faults[slot] = "Could not start this screen: \(error.localizedDescription)"
        }
    }

    private func makeSDITarget(_ profile: ScreenProfile, _ slot: OutputSlot, _ output: PlannedSDIOutput) throws -> any OutputTarget {
        guard let sdi, let handle = sdi.devices().first(where: { $0.id == output.deviceID }) else { throw OutputSetupFailure.noCard }
        let port = try handle.openOutput(connector: output.connector)
        do {
            return try sdi.makeTarget(profile, SDIOutputSetup(slot: slot, planned: output, port: port, info: handle.info))
        } catch {
            port.close()
            throw error
        }
    }

    private enum OutputSetupFailure: Error, LocalizedError {
        case noCard
        var errorDescription: String? { "The SDI card is not connected." }
    }

    private func stopTarget(_ slot: OutputSlot) {
        guard let r = running.removeValue(forKey: slot) else { return }
        r.target.onStatusChange = nil
        // FIX-T item 6 (M6): an SDI output closes its port on its own queue; the main actor does not wait for it. A new output waits
        // (`awaitRetiredTargets`) before it opens a port, so a restart on the same connector never meets the old claim.
        r.target.stopWithoutWaiting()
        retire(r.target)
    }

    /// Outputs whose stop was begun and may not have finished. A new SDI output (or a waiting stop) empties it through `awaitRetiredTargets`;
    /// FIX-V item 4 (REVIEW-4 M2): each output also leaves it by itself when its own teardown ends, and one whose stop was instant (a window
    /// or a display) is never put in it, so a display-only setup holds nothing for the life of the app.
    private var retiring: [any OutputTarget] = []

    /// Tests: called on the main actor when a retired output has been released after its teardown.
    var onRetiredReleased: (@MainActor () -> Void)?

    private func retire(_ target: any OutputTarget) {
        guard target.isTearingDown else { return }
        retiring.append(target)
        // The output says so on the main actor when its teardown has ended (it is never waited for on a thread of ours).
        target.onTeardownFinished = { [weak self] in self?.releaseFinishedTargets() }
    }

    private func releaseFinishedTargets() {
        let finished = retiring.filter { !$0.isTearingDown }
        guard !finished.isEmpty else { return }
        for target in finished { target.onTeardownFinished = nil }
        retiring.removeAll { !$0.isTearingDown }
        onRetiredReleased?()
    }

    private func awaitRetiredTargets() {
        guard !retiring.isEmpty else { return }
        let waiting = retiring
        retiring = []
        for target in waiting { target.waitUntilStopped() }
    }

    /// A target stopped on its own (window closed, display unplugged, SDI card unplugged).
    private func targetChanged(_ slot: OutputSlot, _ status: OutputStatus) {
        guard case .stopped(let reason) = status, let r = running[slot], case .stopped = r.target.status else { return }
        running[slot] = nil
        r.target.onStatusChange = nil
        retire(r.target)                      // its teardown was queued when it stopped on its own
        var deviceLost = false
        if let reason {
            faults[slot] = reason
            switch r.destination {
            case .display(let displayID):
                if !displays().available.contains(displayID) { resumeOnReturn.insert(slot) }
            case .sdi(let output):
                if r.target.stoppedByDeviceLoss || !(handles().first { $0.id == output.deviceID }?.isConnected ?? false) {
                    resumeOnReturn.insert(slot)
                    deviceLost = true
                }
            case .window: break
            }
        }
        finishChange()
        // The card may already be back by the time the output noticed it was gone: start it again at once.
        if deviceLost, isActive { displaysChanged() }
    }

    private func finishChange() {
        sleepGuard?.update(runningCount: running.count)
        onChange?()
    }
}
