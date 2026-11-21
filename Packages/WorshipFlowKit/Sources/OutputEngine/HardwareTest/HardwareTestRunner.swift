// HWTEST-001: runs the hardware test steps one after another and never stops at the first failure. Each step has a
// timeout, a step that throws becomes a failed step, a step that hangs is abandoned, and the bundle is rewritten after
// every step so a crash loses nothing that was already measured.
import Foundation
import SDIEngine

public struct HardwareStepOutput: Sendable {
    public var outcome: HardwareTestOutcome
    public var summary: String
    public var passCriteria: String
    public var measurements: [HardwareMeasurement]
    public var findings: [String]
    public var events: [String]
    public var samples: [String: [Double]]
    public var sampleIntervalSeconds: Double?

    public init(outcome: HardwareTestOutcome, summary: String, passCriteria: String = "", measurements: [HardwareMeasurement] = [],
                findings: [String] = [], events: [String] = [], samples: [String: [Double]] = [:], sampleIntervalSeconds: Double? = nil) {
        self.outcome = outcome
        self.summary = summary
        self.passCriteria = passCriteria
        self.measurements = measurements
        self.findings = findings
        self.events = events
        self.samples = samples
        self.sampleIntervalSeconds = sampleIntervalSeconds
    }
}

public struct HardwareTestStep: Sendable {
    public var id: HardwareTestStepID
    public var number: Int
    public var title: String
    /// Wall-clock seconds the step may run, not counting time spent waiting for the tester to answer.
    public var timeoutSeconds: Double
    /// True when the step cannot run without a device; the runner skips it with a plain reason when none was found.
    public var needsDevice: Bool
    /// A reason to skip the step, or nil to run it.
    public var skipReason: @Sendable (HardwareTestContext) -> String?
    public var run: @Sendable (HardwareTestContext) async throws -> HardwareStepOutput

    public init(id: HardwareTestStepID, number: Int, title: String, timeoutSeconds: Double, needsDevice: Bool = false,
                skipReason: @escaping @Sendable (HardwareTestContext) -> String? = { _ in nil },
                run: @escaping @Sendable (HardwareTestContext) async throws -> HardwareStepOutput) {
        self.id = id
        self.number = number
        self.title = title
        self.timeoutSeconds = timeoutSeconds
        self.needsDevice = needsDevice
        self.skipReason = skipReason
        self.run = run
    }
}

public enum HardwareTestEvent: Sendable {
    case stepStarted(number: Int, total: Int, title: String)
    case stepFinished(HardwareStepResult)
    /// Seconds into a timed step and its length, for a progress bar.
    case progress(step: String, elapsed: Double, total: Double)
    case log(String)
}

public struct HardwareTestBundleTarget: Sendable {
    public var writer: HardwareTestBundleWriter
    /// Where to put the zip when the run ends, or nil to leave the folder only.
    public var zipURL: URL?
    public init(writer: HardwareTestBundleWriter, zipURL: URL?) {
        self.writer = writer
        self.zipURL = zipURL
    }
}

public struct HardwareTestRunResult: Sendable {
    public var report: HardwareTestReport
    /// The zip, when one was asked for and written.
    public var bundleURL: URL?
    /// Set when writing the bundle failed: the report is still returned.
    public var bundleError: String?
}

/// What a step can see and do. One per run.
/// `@unchecked Sendable`: the mutable parts (`humanWait`, `waitingSince`, `outputStartFailed`, `environmentInfo`) are
/// only touched while holding `lock`.
public final class HardwareTestContext: @unchecked Sendable {
    public let configuration: HardwareTestConfiguration
    public let provider: HardwareTestProvider
    public let allDevices: [HardwareTestDevice]
    public let device: HardwareTestDevice?
    public let clock: any HardwareTestClock
    public let interaction: any HardwareTestInteraction
    public let environment: HardwareEnvironmentSource
    public let resources: HardwareResourceProbe
    public let responsiveness: HardwareResponsivenessProbe
    public let log: HardwareTestLog
    let emit: @Sendable (HardwareTestEvent) -> Void
    let attach: @Sendable (URL) -> String?

    private let lock = NSLock()
    private var humanWait = 0.0
    private var waitingSince: UInt64?
    private var startFailed = false
    private var env: HardwareEnvironmentInfo?
    // FIX-D S1: the card as it was before any step, whether this kit changed its profile, and how putting it back went.
    private var startInfo: SDIDeviceInfo?
    private var startRecord: HardwareProfileRecord?
    private var switchedByKit = false
    private var restoreResult: HardwareProfileRestore?
    private var consent = false

    init(configuration: HardwareTestConfiguration, provider: HardwareTestProvider, allDevices: [HardwareTestDevice], device: HardwareTestDevice?,
         clock: any HardwareTestClock, interaction: any HardwareTestInteraction, environment: HardwareEnvironmentSource,
         resources: HardwareResourceProbe, responsiveness: HardwareResponsivenessProbe, log: HardwareTestLog,
         emit: @escaping @Sendable (HardwareTestEvent) -> Void, attach: @escaping @Sendable (URL) -> String?) {
        self.configuration = configuration
        self.provider = provider
        self.allDevices = allDevices
        self.device = device
        self.clock = clock
        self.interaction = interaction
        self.environment = environment
        self.resources = resources
        self.responsiveness = responsiveness
        self.log = log
        self.emit = emit
        self.attach = attach
    }

    /// Set by the output run when the card refused to start: the steps that need an output then say so.
    public var outputStartFailed: Bool {
        get { lock.withLock { startFailed } }
        set { lock.withLock { startFailed = newValue } }
    }

    public var environmentInfo: HardwareEnvironmentInfo? {
        get { lock.withLock { env } }
        set { lock.withLock { env = newValue } }
    }

    /// Asks the tester, and remembers how long they took so the step's timeout does not count it.
    public func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        log.add("Asked the tester: \(prompt.title)")
        lock.withLock { waitingSince = clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
        let answer = await interaction.ask(prompt)
        lock.withLock {
            if let since = waitingSince { humanWait += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - since) / 1e9 }
            waitingSince = nil
        }
        // FIX-D S5: the log says what was answered, never the path or name of a file the tester chose.
        log.add("Answer: \(Self.describe(answer))")
        return answer
    }

    // MARK: the card's profile (FIX-D S1)

    /// The card with the layout it has now: read again from the provider, because a profile change alters which connectors
    /// can do what. Falls back to the card found at the start when the provider no longer lists it.
    public func currentDevice() -> HardwareTestDevice? {
        guard let device else { return nil }
        return provider.devices().first { $0.id == device.id && $0.isConnected() } ?? device
    }

    /// The card's layout now (see `currentDevice`).
    var currentInfo: SDIDeviceInfo? { currentDevice()?.info }

    /// Reads the profile and layout before any step runs.
    func recordStart() {
        guard let device else { return }
        lock.withLock {
            startInfo = device.info
            startRecord = device.captureProfiles?()
        }
    }

    /// "connectors 1 and 2: half duplex; connectors 3 and 4: half duplex. Layout: SDI 1: out/in; ..." or nil.
    var startDescription: String? {
        let (info, record) = lock.withLock { (startInfo, startRecord) }
        let profile = record?.text ?? device?.profile
        let layout = info.flatMap { HardwareTestLayout.describe($0) }
        switch (profile, layout) {
        case let (p?, l?): return "\(p). Layout: \(l)"
        case let (p?, nil): return p
        case let (nil, l?): return "Layout: \(l)"
        default: return nil
        }
    }

    /// The tester agreed to a change of profile for the fill and key tests of this run.
    var keyingConsent: Bool {
        get { lock.withLock { consent } }
        set { lock.withLock { consent = newValue } }
    }

    /// The kit changed the card's profile (for the fill and key step); it will be put back after the step.
    func noteProfileSwitched() { lock.withLock { switchedByKit = true } }

    public var profileRestore: HardwareProfileRestore? { lock.withLock { restoreResult } }

    /// True while the card is in the keying profile because it could not be put back.
    var leftInKeyingProfile: Bool { profileRestore?.leftInKeyingProfile == true }

    /// The words that label a step run in the keying profile, with the layout its connectors were chosen from.
    func keyingProfileNote() -> String? {
        guard leftInKeyingProfile else { return nil }
        let layout = currentInfo.flatMap { HardwareTestLayout.describe($0) }.map { " Connectors for this step came from the layout the card had then: \($0)." } ?? ""
        return "Run in the keying profile: the card's earlier profile could not be put back (\(profileRestore?.detail ?? "unknown reason")).\(layout)"
    }

    /// Puts the profile back if this kit changed it, without asking (restoring is always wanted), then checks that the card
    /// reports the profile and layout it had at the start. Retries a few times: ports of an abandoned step may still be closing.
    func restoreProfileIfNeeded() async {
        let (needed, record, startLayout) = lock.withLock { (switchedByKit, startRecord, startInfo) }
        guard needed, device != nil else { return }
        let fresh = currentDevice()
        guard let record, let restore = fresh?.restoreProfiles ?? device?.restoreProfiles else {
            let why = record == nil ? "the card's profile could not be read before it was changed, so there is nothing to put back"
                                    : "this card cannot change its profile back from WORSHIPFLOW; set it in Blackmagic Desktop Video Setup"
            finishRestore(.init(state: .notVerified, detail: why))
            return
        }
        var failure: String?
        for attempt in 1...3 {
            do { try await restore(record); failure = nil; break } catch {
                failure = HardwareTestSteps.describe(error)
                log.add("Putting the profile back failed (attempt \(attempt) of 3): \(failure ?? "")")
                if attempt < 3 { try? await clock.wait(seconds: 1) }
            }
        }
        if let failure {
            finishRestore(.init(state: .failed, detail: failure))
            return
        }
        let again = currentDevice()
        let recordMatches = again?.captureProfiles?().map { $0.pairs.map { [$0.firstConnector: $0.identifier] } == record.pairs.map { [$0.firstConnector: $0.identifier] } }
        let layoutMatches = startLayout.map { start in again.map { $0.info.connectors == start.connectors && $0.info.profiles.map(\.activeName) == start.profiles.map(\.activeName) } ?? false }
        if recordMatches == true || (recordMatches == nil && layoutMatches == true), layoutMatches != false {
            lock.withLock { switchedByKit = false }
            finishRestore(.init(state: .restoredAndVerified, detail: "The card is back in its earlier profile (\(record.text)) and reports the same layout."))
        } else {
            finishRestore(.init(state: .notVerified, detail: "The card was asked to go back to (\(record.text)), but its report afterwards does not match the one taken before the test."))
        }
    }

    private func finishRestore(_ result: HardwareProfileRestore) {
        lock.withLock {
            // A restore that failed once stays failed: a later success does not undo the steps that ran in the keying profile.
            if restoreResult?.leftInKeyingProfile != true { restoreResult = result }
        }
        log.add("Profile restore: \(result.state.rawValue). \(result.detail)")
    }

    static func describe(_ answer: HardwareAnswer) -> String {
        switch answer {
        case .proceed: return "proceed"
        case .skip: return "skip"
        case .yes: return "yes"
        case .no: return "no"
        case .attachment: return "a photo was chosen"
        case .unavailable: return "unavailable"
        }
    }

    func resetHumanWait() { lock.withLock { humanWait = 0; waitingSince = nil } }

    /// Seconds the tester has taken to answer during this step, including an answer still pending.
    func humanWaitSeconds() -> Double {
        lock.withLock {
            var total = humanWait
            if let since = waitingSince { total += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - since) / 1e9 }
            return total
        }
    }

    public func progress(step: String, elapsed: Double, total: Double) { emit(.progress(step: step, elapsed: elapsed, total: total)) }
}

public final class HardwareTestRunner: Sendable {
    private let provider: HardwareTestProvider
    private let configuration: HardwareTestConfiguration
    private let clock: any HardwareTestClock
    private let interaction: any HardwareTestInteraction
    private let environment: HardwareEnvironmentSource
    private let resources: HardwareResourceProbe
    private let responsiveness: HardwareResponsivenessProbe
    private let bundle: HardwareTestBundleTarget?
    private let onEvent: @Sendable (HardwareTestEvent) -> Void
    private let steps: [HardwareTestStep]

    public init(provider: HardwareTestProvider, configuration: HardwareTestConfiguration, clock: any HardwareTestClock,
                interaction: any HardwareTestInteraction, environment: HardwareEnvironmentSource,
                resources: HardwareResourceProbe = .system, responsiveness: HardwareResponsivenessProbe = .unavailable,
                bundle: HardwareTestBundleTarget? = nil, onEvent: @escaping @Sendable (HardwareTestEvent) -> Void = { _ in },
                steps: [HardwareTestStep]? = nil) {
        self.provider = provider
        self.configuration = configuration
        self.clock = clock
        self.interaction = interaction
        self.environment = environment
        self.resources = resources
        self.responsiveness = responsiveness
        self.bundle = bundle
        self.onEvent = onEvent
        self.steps = steps ?? HardwareTestSteps.standard(configuration)
    }

    public func run() async -> HardwareTestRunResult {
        let now = environment.now
        let log = HardwareTestLog(now: now, onLine: { [onEvent] in onEvent(.log($0)) })
        provider.rescan?()          // the run is off the main thread, so a real scan may take its time here
        let all = provider.devices()
        let device = all.first { $0.id == configuration.deviceID && $0.isConnected() } ?? (configuration.deviceID == nil ? all.first { $0.isConnected() } : nil)
        let writer = bundle?.writer
        let context = HardwareTestContext(
            configuration: configuration, provider: provider, allDevices: all, device: device, clock: clock, interaction: interaction,
            environment: environment, resources: resources, responsiveness: responsiveness, log: log, emit: onEvent,
            attach: { url in
                do { return try writer?.attachPhoto(from: url) } catch { log.add("A photo could not be attached: it could not be read as a picture."); return nil }
            })

        context.recordStart()
        var report = HardwareTestReport(simulated: device?.info.isSimulated ?? provider.isSimulated, deviceName: device?.info.displayName,
                                        deviceID: device.map { HardwareTestHash.short($0.id) }, preset: configuration.preset.rawValue, startedAt: HardwareTestClockText.iso(now()))
        report.profileAtStart = context.startDescription
        if let text = report.profileAtStart { log.add("The card's profile and layout before any step: \(text)") }
        log.add("Hardware test started (\(configuration.preset.rawValue)). Device: \(device?.info.displayName ?? "none found")"
                + (report.simulated ? " (SIMULATED)" : ""))
        persist(report, log)

        for (position, step) in steps.enumerated() {
            onEvent(.stepStarted(number: position + 1, total: steps.count, title: step.title))
            log.add("Step \(step.number): \(step.title)")
            // FIX-D S6: the file says which step is running before it starts, so a crash inside the step is a report that says where.
            report.runningStep = step.number
            report.runningStepTitle = step.title
            persist(report, log)
            let note = context.keyingProfileNote()          // taken before the step: it is what the step ran in
            let started = now()
            let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            var output = await execute(step, context)
            let seconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1e9
            await context.restoreProfileIfNeeded()
            report.profileRestore = context.profileRestore
            if step.id == .fillKeyLoopback || step.id == .humanChecks, let restore = context.profileRestore {
                output.events.append("Putting the card's profile back: \(restore.state == .restoredAndVerified ? "done and checked" : "NOT done or NOT checked") (\(restore.detail))")
            }
            let result = HardwareStepResult(
                id: step.id, number: step.number, title: step.title, outcome: output.outcome, summary: output.summary,
                passCriteria: output.passCriteria, measurements: output.measurements, findings: output.findings, events: output.events,
                samples: output.samples, sampleIntervalSeconds: output.sampleIntervalSeconds,
                startedAt: HardwareTestClockText.iso(started), durationSeconds: (seconds * 100).rounded() / 100,
                profileNote: step.needsDevice ? note : nil)
            report.steps.append(result)
            report.environment = context.environmentInfo
            log.add("Step \(step.number) \(step.title): \(result.outcome.label). \(result.summary)")
            persist(report, log)
            onEvent(.stepFinished(result))
        }

        report.complete = true
        report.runningStep = nil
        report.runningStepTitle = nil
        report.finishedAt = HardwareTestClockText.iso(now())
        log.add("Hardware test finished.")
        var url: URL?
        var problem: String?
        if let bundle {
            do {
                if let zip = bundle.zipURL {
                    try bundle.writer.finish(report: report, log: log.text, zipTo: zip)
                    url = zip
                } else {
                    try bundle.writer.write(report: report, log: log.text)
                }
            } catch {
                problem = error.localizedDescription
                log.add("The bundle could not be written: \(error.localizedDescription)")
            }
        }
        return HardwareTestRunResult(report: report, bundleURL: url, bundleError: problem)
    }

    private func persist(_ report: HardwareTestReport, _ log: HardwareTestLog) {
        guard let writer = bundle?.writer else { return }
        do { try writer.write(report: report, log: log.text) } catch { log.add("Could not update the bundle: \(error.localizedDescription)") }
    }

    /// Runs one step: skipped for a stated reason, failed if it throws or overruns, otherwise whatever it returns.
    private func execute(_ step: HardwareTestStep, _ context: HardwareTestContext) async -> HardwareStepOutput {
        if Task.isCancelled { return HardwareStepOutput(outcome: .skipped, summary: "The test was cancelled before this step.") }
        if step.needsDevice, context.device == nil {
            return HardwareStepOutput(outcome: .skipped, summary: "No device was found, so this step could not run.")
        }
        if let reason = step.skipReason(context) { return HardwareStepOutput(outcome: .skipped, summary: reason) }
        context.resetHumanWait()
        let gate = ResumeOnce<StepEnd>()
        let work = Task { () -> Void in
            do { gate.finish(.finished(.success(try await step.run(context)))) } catch { gate.finish(.finished(.failure(error))) }
        }
        let watchdog = Task { () -> Void in
            let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(min(250, max(10, Int(step.timeoutSeconds * 100)))))
                let active = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1e9 - context.humanWaitSeconds()
                if active > step.timeoutSeconds { gate.finish(.timedOut); return }
            }
        }
        let outcome: StepEnd = await withTaskCancellationHandler {
            await gate.value()
        } onCancel: {
            work.cancel()
            gate.finish(.finished(.failure(CancellationError())))
        }
        watchdog.cancel()
        switch outcome {
        case .finished(.success(let out)): return out
        case .finished(.failure(let error)):
            if error is CancellationError { return HardwareStepOutput(outcome: .failed, summary: "The step was cancelled.") }
            return HardwareStepOutput(outcome: .failed, summary: "The step stopped with an error: \(error.localizedDescription)")
        case .timedOut:
            work.cancel()
            context.log.add("Step \(step.number) overran its \(Int(step.timeoutSeconds)) second limit and was abandoned.")
            return HardwareStepOutput(outcome: .failed, summary: "The step did not finish within \(Int(step.timeoutSeconds.rounded(.up))) seconds, so it was stopped and the test moved on.")
        }
    }
}

private enum StepEnd: Sendable {
    case finished(Result<HardwareStepOutput, Error>)
    case timedOut
}

/// A value that is set once, by whoever gets there first, and awaited by one reader.
/// `@unchecked Sendable`: `stored`, `continuation` and `done` are only touched while holding `lock`.
final class ResumeOnce<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    private var done = false
    private var continuation: CheckedContinuation<Value, Never>?

    func finish(_ value: Value) {
        let waiting: CheckedContinuation<Value, Never>? = lock.withLock {
            guard !done else { return nil }
            done = true
            stored = value
            let c = continuation
            continuation = nil
            return c
        }
        waiting?.resume(returning: value)
    }

    func value() async -> Value {
        await withCheckedContinuation { c in
            let ready: Value? = lock.withLock {
                if done { return stored }
                continuation = c
                return nil
            }
            if let ready { c.resume(returning: ready) }
        }
    }
}
