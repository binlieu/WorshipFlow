// HWTEST-001: everything the Hardware Test window shows and does, without any view code, so it can be tested.
// It runs the kit off the main thread, publishes progress and the tester's questions to the main actor, refuses to start
// while the screens are open, and saves the bundle where the tester chooses.
import Foundation
import Observation
import SDIEngine

@MainActor
@Observable
public final class HardwareTestController {
    public enum Phase: Equatable { case idle, running, finished }

    public var preset: HardwareTestPreset = .quick
    public var includeUnplugTest = false
    public var includeHumanChecks = false
    /// For tests: ask the controller's own tester the questions during a simulated run, as a real run does.
    public var useInteractiveTesterForSimulation = false

    public private(set) var phase: Phase = .idle
    public private(set) var realDevices: [HardwareTestDevice] = []
    public private(set) var driverStatus = HardwareDriverStatus(isInstalled: false, message: "")
    public private(set) var currentStepTitle: String?
    public private(set) var stepPosition = 0
    public private(set) var stepTotal = 0
    public private(set) var stepProgress = 0.0
    public private(set) var logLines: [String] = []
    public private(set) var results: [HardwareStepResult] = []
    public private(set) var pendingPrompt: HardwarePrompt?
    public private(set) var bundleURL: URL?
    public private(set) var summaryText: String?
    public private(set) var errorMessage: String?
    public private(set) var runWasSimulated = false

    @ObservationIgnored private let realProvider: @Sendable () -> HardwareTestProvider
    @ObservationIgnored private let environment: HardwareEnvironmentSource
    @ObservationIgnored private let screensOpen: @MainActor () -> Bool
    @ObservationIgnored private let responsiveness: HardwareResponsivenessProbe
    @ObservationIgnored private let durationsOverride: HardwareTestDurations?
    @ObservationIgnored private let workingFolder: URL
    @ObservationIgnored private let stepsOverride: [HardwareTestStep]?
    @ObservationIgnored private var promptContinuation: CheckedContinuation<HardwareAnswer, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var runFileName = HardwareTestBundle.fileName(simulated: false)

    public init(realProvider: @escaping @Sendable () -> HardwareTestProvider, environment: HardwareEnvironmentSource,
                screensOpen: @escaping @MainActor () -> Bool, responsiveness: HardwareResponsivenessProbe? = nil,
                durationsOverride: HardwareTestDurations? = nil, stepsOverride: [HardwareTestStep]? = nil, workingFolder: URL? = nil) {
        self.stepsOverride = stepsOverride
        self.realProvider = realProvider
        self.environment = environment
        self.screensOpen = screensOpen
        self.responsiveness = responsiveness ?? HardwareResponsivenessProbe {
            let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            await MainActor.run {}
            return Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1_000_000
        }
        self.durationsOverride = durationsOverride
        self.workingFolder = workingFolder ?? FileManager.default.temporaryDirectory.appendingPathComponent("WORSHIPFLOW-hardware-test", isDirectory: true)
        refresh()
    }

    // MARK: what the window shows before a run

    /// Looks again for cards and the driver (the tester may have just installed it or plugged the card in).
    public func refresh() {
        let provider = realProvider()
        realDevices = provider.devices().filter { $0.isConnected() }
        driverStatus = provider.driver()
    }

    public var driverMessage: String { driverStatus.message }
    public var hasRealDevice: Bool { !realDevices.isEmpty }

    /// Why a run cannot start now, in plain words, or nil.
    public var refusal: String? {
        if screensOpen() {
            return "The screens are open, so the audience may be looking at them. The hardware test would take over the card and could disturb the service. Close the screens first (Show menu, then Close Screens), then come back."
        }
        if phase == .running { return "A test is already running." }
        return nil
    }

    public var canStartSimulated: Bool { refusal == nil }
    /// A run with no card is still allowed: it produces a report that says no device was found, which is useful evidence.
    public var canStartReal: Bool { refusal == nil }
    public var canSaveEvidenceWithoutDevice: Bool { true }
    public var realRunTitle: String { hasRealDevice ? "Start the test" : "Create a report anyway" }

    // MARK: running

    public func start(simulated: Bool) {
        guard refusal == nil else { return }
        reset()
        phase = .running
        runWasSimulated = simulated
        runFileName = HardwareTestBundle.fileName(simulated: simulated)
        let configuration = HardwareTestConfiguration(preset: preset, durations: durationsOverride,
                                                      includeUnplugTest: includeUnplugTest, includeHumanChecks: includeHumanChecks)
        let provider: HardwareTestProvider, clock: any HardwareTestClock, interaction: any HardwareTestInteraction
        let tester = ControllerTester { [weak self] prompt in
            guard let self else { return .unavailable }
            return await self.present(prompt)
        }
        if simulated {
            let rig = HardwareTestRig.simulated()
            (provider, clock, interaction) = (rig.provider, rig.clock, useInteractiveTesterForSimulation ? tester : rig.interaction)
        } else {
            (provider, clock, interaction) = (realProvider(), RealHardwareTestClock(), tester)
        }
        let folder = workingFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let writer: HardwareTestBundleWriter
        do { writer = try HardwareTestBundleWriter(directory: folder.appendingPathComponent("bundle")) } catch {
            errorMessage = "The test could not start: a temporary folder could not be made (\(error.localizedDescription))."
            phase = .finished
            return
        }
        let runner = HardwareTestRunner(
            provider: provider, configuration: configuration, clock: clock, interaction: interaction, environment: environment,
            responsiveness: responsiveness,
            bundle: HardwareTestBundleTarget(writer: writer, zipURL: folder.appendingPathComponent(runFileName)),
            onEvent: { [weak self] event in Task { @MainActor in self?.handle(event) } }, steps: stepsOverride)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = await runner.run()
            await MainActor.run { self?.finished(result) }
        }
    }

    /// Back to the set-up screen after a finished run.
    public func resetToSetup() {
        guard phase == .finished else { return }
        reset()
        phase = .idle
    }

    /// The tester's answer to the question on screen.
    public func answer(_ answer: HardwareAnswer) {
        guard let c = promptContinuation else { return }
        promptContinuation = nil
        pendingPrompt = nil
        c.resume(returning: answer)
    }

    /// Stops after the current step. What was measured so far is kept.
    public func cancel() {
        task?.cancel()
        answer(.skip)
    }

    private func reset() {
        currentStepTitle = nil
        stepPosition = 0
        stepTotal = 0
        stepProgress = 0
        logLines = []
        results = []
        pendingPrompt = nil
        bundleURL = nil
        summaryText = nil
        errorMessage = nil
    }

    private func present(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        await withCheckedContinuation { c in
            pendingPrompt = prompt
            promptContinuation = c
        }
    }

    private func handle(_ event: HardwareTestEvent) {
        switch event {
        case .stepStarted(let n, let total, let title):
            currentStepTitle = title
            stepPosition = n
            stepTotal = total
            stepProgress = 0
        case .stepFinished(let r):
            results.append(r)
            stepProgress = 1
        case .progress(_, let elapsed, let total):
            stepProgress = total > 0 ? min(1, elapsed / total) : 0
        case .log(let line):
            logLines.append(line)
            if logLines.count > 400 { logLines.removeFirst(logLines.count - 400) }
        }
    }

    private func finished(_ result: HardwareTestRunResult) {
        summaryText = HardwareTestSummary.render(result.report)
        bundleURL = result.bundleURL
        if let problem = result.bundleError { errorMessage = "The report could not be written: \(problem)" }
        currentStepTitle = nil
        phase = .finished
    }

    // MARK: saving

    public var suggestedFileName: String { runFileName }

    /// Copies the finished bundle to where the tester chose, replacing a file already there.
    public func save(to destination: URL) throws {
        guard let source = bundleURL else { throw HardwareTestBundleError.notABundle("there is no finished report to save") }
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.copyItem(at: source, to: destination)
    }
}

/// Puts the runner's questions on the window and waits for the tester.
struct ControllerTester: HardwareTestInteraction {
    let handler: @Sendable (HardwarePrompt) async -> HardwareAnswer
    init(_ handler: @escaping @Sendable (HardwarePrompt) async -> HardwareAnswer) { self.handler = handler }
    func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer { await handler(prompt) }
}
