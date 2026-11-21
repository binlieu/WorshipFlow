// HWTEST-001: the launch arguments, and the run with nobody at the keyboard (for the coordinator).
//   --hardware-test                         open the Hardware Test window
//   --hardware-test --simulated --quick --output <path>
//                                           run against the simulated card without a window; write the bundle; exit
//   --inject-fault swapped-connectors | profile-not-restored | crossed-cables
//                                           (with --simulated, repeatable) make the simulated card get one thing wrong, so the
//                                           report can be seen to catch it
//   --unfinished-folder <dir>               where a real run's visible "unfinished" folder goes instead of the Desktop
// `--output` takes a `.zip` file name, or a folder in which the bundle is named by date.
import Foundation
import SDIEngine

public struct HardwareTestLaunch: Equatable, Sendable {
    public var simulated: Bool
    public var preset: HardwareTestPreset
    public var outputPath: String?
    /// `--inject-faults`: the simulated cables lose every 7th frame and swap fill and key, so the coordinator can see
    /// the report catch them.
    public var faults: SimulatedFaults
    /// `--inject-fault <name>` (FIX-D): faults of the profiled simulated card.
    public var injections: Set<HardwareTestInjection>

    public init(simulated: Bool, preset: HardwareTestPreset, outputPath: String?, faults: SimulatedFaults = .none,
                injections: Set<HardwareTestInjection> = []) {
        self.faults = faults
        self.injections = injections
        self.simulated = simulated
        self.preset = preset
        self.outputPath = outputPath
    }

    /// Run without a window and exit when the bundle is written.
    public var isHeadless: Bool { outputPath != nil }

    /// Nil when `--hardware-test` is absent.
    public static func parse(_ args: [String]) -> HardwareTestLaunch? {
        guard args.contains("--hardware-test") else { return nil }
        var path: String?
        if let i = args.firstIndex(of: "--output"), i + 1 < args.count, !args[i + 1].hasPrefix("--") { path = args[i + 1] }
        let preset: HardwareTestPreset = args.contains("--long") ? .long : args.contains("--standard") ? .standard : .quick
        var injections: Set<HardwareTestInjection> = []
        for (i, arg) in args.enumerated() where arg == "--inject-fault" && i + 1 < args.count {
            if let fault = HardwareTestInjection(rawValue: args[i + 1]) { injections.insert(fault) }
        }
        return HardwareTestLaunch(simulated: args.contains("--simulated"), preset: preset, outputPath: path,
                                  faults: args.contains("--inject-faults") ? SimulatedFaults(dropEveryNthFrame: 7, swapFillAndKey: true) : .none,
                                  injections: injections)
    }
}

public enum HardwareTestHeadless {
    /// 0 when the bundle was written, whatever the steps found; non-zero only when the kit itself failed.
    /// - Parameters:
    ///   - durations: replaces the preset's lengths (tests use short ones).
    ///   - steps: replaces the standard nine steps (tests use a few cheap ones).
    ///   - realProvider: the provider for a run that is not simulated; nil means no card is available to this build.
    public static func run(_ launch: HardwareTestLaunch, durations: HardwareTestDurations? = nil, environment: HardwareEnvironmentSource,
                           realProvider: HardwareTestProvider? = nil, steps: [HardwareTestStep]? = nil, log: @escaping @Sendable (String) -> Void = { _ in }) async -> Int32 {
        guard let path = launch.outputPath, !path.isEmpty else {
            log("--output <path> is needed for a run without a window.")
            return 2
        }
        let target = URL(fileURLWithPath: path)
        let zip = target.pathExtension.lowercased() == "zip"
            ? target : target.appendingPathComponent(HardwareTestBundle.fileName(simulated: launch.simulated))
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("WORSHIPFLOW-hardware-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            let writer = try HardwareTestBundleWriter(directory: work.appendingPathComponent("bundle"))
            let configuration = HardwareTestConfiguration(preset: launch.preset, durations: durations)
            let provider: HardwareTestProvider, clock: any HardwareTestClock, interaction: any HardwareTestInteraction
            if launch.simulated {
                let rig = HardwareTestRig.simulatedCard(faults: launch.faults, injecting: launch.injections)
                (provider, clock, interaction) = (rig.provider, rig.clock, rig.interaction)
            } else {
                provider = realProvider ?? HardwareTestProvider(
                    isSimulated: false, devices: { [] },
                    driver: { HardwareDriverStatus(isInstalled: false, message: "No card provider is available to this build.") })
                (clock, interaction) = (RealHardwareTestClock(), AutomaticInteraction())
            }
            let runner = HardwareTestRunner(
                provider: provider, configuration: configuration, clock: clock, interaction: interaction, environment: environment,
                bundle: HardwareTestBundleTarget(writer: writer, zipURL: zip),
                onEvent: { if case .log(let line) = $0 { log(line) } }, steps: steps)
            let result = await runner.run()
            if let problem = result.bundleError { log("The bundle could not be written: \(problem)") }
            return result.bundleURL == nil ? 1 : 0
        } catch {
            log("The hardware test kit failed: \(error.localizedDescription)")
            return 1
        }
    }
}
