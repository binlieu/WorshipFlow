// CUE-002b: the cue wiring. One model owns the cue executor, the macros, slide actions, schedule and MIDI bindings read from
// `CueStore`, and the ONE serial command path (ARCH-15): every command, whatever its source (a button, a key, a slide action,
// a macro, the schedule, a MIDI pad, the remote server), is queued here and run one at a time, in arrival order, so two
// sources can never interleave. Decisions live here; the views only draw. Foundation, Observation and the engines only.
import Foundation
import Observation
import Domain
import CueEngine
import CueStore
import Persistence
import MIDIIO
import RemoteControl

@MainActor
@Observable
public final class CueModel {
    // MARK: State the interface reads

    public internal(set) var library = MacroLibrary()
    public var macros: [Macro] { library.macros }
    /// Actions of every slide in the library that has any, by slide id.
    public internal(set) var slideActions = SlideActionSet()
    public internal(set) var schedule = ScheduleEngine()
    public internal(set) var bindings = MIDIBindingSet()
    /// Things that could not be loaded cleanly (an unknown action, a row from a newer version).
    public internal(set) var loadIssues: [CueLoadIssue] = []
    public internal(set) var lastError: String?
    public internal(set) var notices: [CueNotice] = []
    public internal(set) var activity: [ActivityLine] = []
    public internal(set) var isLoaded = false
    /// MIDI settings (off by default) and what the router reports now (item 4).
    public internal(set) var midi = MIDISettings()
    public internal(set) var midiStatus = MIDIStatus()
    /// Remote control settings (off by default) and what the server reports now (item 5).
    public internal(set) var remote = RemoteSettings()
    public internal(set) var remoteStatus = RemoteStatus()

    public static let queueLimit = 200
    static let activityLimit = 60

    // MARK: Internals

    @ObservationIgnored let store: CueStore
    @ObservationIgnored let ports: CuePorts
    @ObservationIgnored let target: ShowCueTarget
    @ObservationIgnored let executor: CueExecutor
    @ObservationIgnored let clock: any CueClock
    @ObservationIgnored let wallClock: @MainActor () -> Date
    @ObservationIgnored let calendar: Calendar
    /// Where the MIDI and remote settings are kept (the library's app state). Nil in tests that need none.
    @ObservationIgnored let settingsStore: LibraryStore?
    /// Makes the MIDI ports when the operator turns MIDI on. Nil when this build has none.
    @ObservationIgnored public var midiPortsFactory: (() throws -> any MIDIPorts)?
    @ObservationIgnored var midiPorts: (any MIDIPorts)?
    @ObservationIgnored var midiRouter: MIDIRouter?
    @ObservationIgnored var remoteServer: RemoteServer?
    @ObservationIgnored var remoteTokens: LibraryTokenStore?
    @ObservationIgnored var remoteTarget: CueRemoteTarget?
    @ObservationIgnored var lastRemoteState: RemoteState?
    /// A run may keep to the loopback interface and ask for a free port: the app's launch arguments set these.
    @ObservationIgnored public var remoteLoopbackOnly = false
    @ObservationIgnored public var remotePortOverride: UInt16?
    @ObservationIgnored public var localAddresses: @Sendable () -> [String] = { NetworkAddresses.local() }
    /// Builds what a phone sees from the models; the app sets it. Without it only the macros are listed.
    @ObservationIgnored public var remoteStateSource: (@MainActor () -> RemoteState)?

    private struct Job {
        var command: OperatorCommand
        var source: CommandSource
        var done: CheckedContinuation<String?, Never>?
    }
    /// True while the Hardware Test window is running a test: scheduled events are not run then (item 3).
    @ObservationIgnored public var hardwareTestIsRunning: @MainActor () -> Bool = { false }
    @ObservationIgnored var scheduleSavedAt: Date?
    @ObservationIgnored var scheduleSaveTail: Task<Void, Never>?
    @ObservationIgnored private var queue: [Job] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var jobProblems: [String] = []

    public init(store: CueStore, ports: CuePorts, clock: any CueClock = SystemCueClock(),
                wallClock: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .current,
                settingsStore: LibraryStore? = nil) {
        self.store = store
        self.settingsStore = settingsStore
        self.ports = ports
        self.clock = clock
        self.wallClock = wallClock
        self.calendar = calendar
        let midiOut = ports.midiOut
        var late: (@MainActor () -> (any CueMIDIOutPort)?)?
        let target = ShowCueTarget(transport: ports.transport, looks: ports.looks, stage: ports.stage, media: ports.media,
                                   midiOut: { midiOut() ?? late?() })
        self.target = target
        self.executor = CueExecutor(target: target, clock: clock)
        late = { [weak self] in self?.midiRouter }
    }

    // MARK: Loading

    /// Reads the whole cue library. What the schedule engine remembers in memory (what it fired, when it last looked) is kept:
    /// only its events are replaced, so a reload never makes a past event fire again.
    public func reload() async {
        do {
            let loaded = try await store.loadLibrary()
            library = loaded.macros
            executor.macros = loaded.macros
            slideActions = loaded.slideActions
            schedule = isLoaded ? ScheduleEngine(events: loaded.schedule.events, state: schedule.state) : loaded.schedule
            bindings = loaded.midi
            loadIssues = loaded.issues
            isLoaded = true
            bindingsChanged()
        } catch {
            lastError = Self.message(for: error)
        }
    }

    static func message(for error: Error) -> String {
        (error as? CueStoreError)?.message ?? "Could not use the cue library: \(error.localizedDescription)"
    }

    // MARK: The one command path

    /// Queues a command. It returns at once; the command runs after every earlier one has finished.
    public func submit(_ command: OperatorCommand, from source: CommandSource) {
        enqueue(Job(command: command, source: source, done: nil), atFront: false)
    }

    /// Queues a command and returns when it has finished (the remote server waits on this). Returns the first problem the
    /// command ran into, in words for the operator, or nil.
    @discardableResult
    public func run(_ command: OperatorCommand, from source: CommandSource) async -> String? {
        await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            enqueue(Job(command: command, source: source, done: c), atFront: false)
        }
    }

    /// Waits until nothing is queued or running. For tests and for quitting.
    public func settled() async {
        while draining || !queue.isEmpty { await Task.yield() }
    }

    /// A slide went live while a command was running. Its actions run right after that command, before anything queued behind it.
    public func slideWentLive(_ event: SlideLiveEvent) {
        enqueue(Job(command: .slideLive(event), source: .slideAction, done: nil), atFront: true)
    }

    /// Called from the app's ticker. Queues a tick only when a waited stage has come due.
    public func tick() {
        guard executor.pendingStageCount > 0, let due = executor.nextDueTime, clock.now() >= due else { return }
        submit(.tick, from: .timer)
    }

    private func enqueue(_ job: Job, atFront: Bool) {
        if queue.count >= Self.queueLimit {
            note("Too many commands are waiting (\(Self.queueLimit)). The newest was dropped; the show is still running.")
            job.done?.resume(returning: "Too many commands are waiting; this one was dropped.")
            return
        }
        if atFront { queue.insert(job, at: 0) } else { queue.append(job) }
        guard !draining else { return }
        draining = true
        Task { @MainActor [weak self] in await self?.drain() }
    }

    private func drain() async {
        while !queue.isEmpty {
            let job = queue.removeFirst()
            jobProblems = []
            await execute(job)
            job.done?.resume(returning: jobProblems.first)
        }
        draining = false
    }

    private func execute(_ job: Job) async {
        switch job.command {
        case .goLive:
            await ports.transport.goLive()
            log(job.source, "Go Live")
        case .triggerSlide(let i):
            ports.transport.triggerSlide(i)
            log(job.source, "Go live with slide \(i + 1)")
        case .transport(let t):
            await perform(t, from: job.source)
        case .runMacro(let id):
            let name = library.macro(id: id)?.name ?? "unknown macro"
            let origin: CueOrigin = job.source == .schedule ? .schedule : .operatorTrigger
            log(job.source, "macro \(name)")
            await runActions([.runMacro(id)], origin: origin, source: job.source)
        case .runActions(let actions, let origin):
            await runActions(actions, origin: origin, source: job.source)
        case .slideLive(let event):
            guard let id = ports.transport.liveSlideID(for: event) else { return }
            let actions = slideActions.actions(for: id)
            guard !actions.isEmpty else { return }
            log(.slideAction, "slide \(event.index + 1): \(actions.count) action\(actions.count == 1 ? "" : "s")")
            await runActions(actions, origin: .slide, source: .slideAction)
        case .tick:
            let report = executor.tick()
            await finish(report, source: job.source)
        }
    }

    private func perform(_ t: CueTransport, from source: CommandSource) async {
        do {
            switch t {
            case .next: await ports.transport.next()
            case .previous: await ports.transport.previous()
            case .stop:
                try target.perform(.transport(t))
                executor.stop()
            default: try target.perform(.transport(t))
            }
            log(source, t.summary)
        } catch {
            problem(source, "\(t.summary) failed: \((error as? CueTargetError)?.message ?? error.localizedDescription)")
        }
        await awaitDeferred(source)
    }

    private func runActions(_ actions: [CueAction], origin: CueOrigin, source: CommandSource) async {
        let report = executor.run(actions, origin: origin)
        await finish(report, source: source)
    }

    private func finish(_ report: CueReport, source: CommandSource) async {
        for issue in report.issues { problem(source, issue.message) }
        await awaitDeferred(source)
    }

    /// Steps a macro could not do synchronously (a Next that crosses into another playlist item) are awaited here, still
    /// inside the same command, so nothing else runs in between.
    private func awaitDeferred(_ source: CommandSource) async {
        for t in target.takeDeferred() {
            switch t {
            case .next: await ports.transport.next()
            case .previous: await ports.transport.previous()
            default: break
            }
        }
    }

    // MARK: Activity and notices

    func log(_ source: CommandSource, _ text: String) {
        append(ActivityLine(time: wallClock(), source: source, text: text, isProblem: false))
    }

    func problem(_ source: CommandSource, _ text: String) {
        append(ActivityLine(time: wallClock(), source: source, text: text, isProblem: true))
        jobProblems.append(text)
        notices.append(CueNotice(text: text))
        if notices.count > 20 { notices.removeFirst(notices.count - 20) }
    }

    /// A notice that is not tied to one command.
    func note(_ text: String) {
        notices.append(CueNotice(text: text))
        if notices.count > 20 { notices.removeFirst(notices.count - 20) }
    }

    private func append(_ line: ActivityLine) {
        activity.append(line)
        if activity.count > Self.activityLimit { activity.removeFirst(activity.count - Self.activityLimit) }
    }

    public func dismissNotice(_ id: UUID) { notices.removeAll { $0.id == id } }
    public func dismissError() { lastError = nil }

    /// Bindings changed, so the router must be told.
    func bindingsChanged() { midiRouter?.bindings = bindings }
}
