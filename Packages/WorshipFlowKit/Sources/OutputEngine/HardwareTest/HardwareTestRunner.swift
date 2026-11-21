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
        log.add("Answer: \(answer)")
        return answer
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
        let all = provider.devices()
        let device = all.first { $0.id == configuration.deviceID && $0.isConnected() } ?? (configuration.deviceID == nil ? all.first { $0.isConnected() } : nil)
        let writer = bundle?.writer
        let context = HardwareTestContext(
            configuration: configuration, provider: provider, allDevices: all, device: device, clock: clock, interaction: interaction,
            environment: environment, resources: resources, responsiveness: responsiveness, log: log, emit: onEvent,
            attach: { url in
                do { return try writer?.attachPhoto(from: url) } catch { log.add("Could not attach the photo: \(error.localizedDescription)"); return nil }
            })

        var report = HardwareTestReport(simulated: device?.info.isSimulated ?? provider.isSimulated, deviceName: device?.info.displayName,
                                        deviceID: device?.id, preset: configuration.preset.rawValue, startedAt: HardwareTestClockText.iso(now()))
        log.add("Hardware test started (\(configuration.preset.rawValue)). Device: \(device?.info.displayName ?? "none found")"
                + (report.simulated ? " (SIMULATED)" : ""))
        persist(report, log)

        for (position, step) in steps.enumerated() {
            onEvent(.stepStarted(number: position + 1, total: steps.count, title: step.title))
            log.add("Step \(step.number): \(step.title)")
            let started = now()
            let began = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let output = await execute(step, context)
            let seconds = Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - began) / 1e9
            let result = HardwareStepResult(
                id: step.id, number: step.number, title: step.title, outcome: output.outcome, summary: output.summary,
                passCriteria: output.passCriteria, measurements: output.measurements, findings: output.findings, events: output.events,
                samples: output.samples, sampleIntervalSeconds: output.sampleIntervalSeconds,
                startedAt: HardwareTestClockText.iso(started), durationSeconds: (seconds * 100).rounded() / 100)
            report.steps.append(result)
            report.environment = context.environmentInfo
            log.add("Step \(step.number) \(step.title): \(result.outcome.label). \(result.summary)")
            persist(report, log)
            onEvent(.stepFinished(result))
        }

        report.complete = true
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
