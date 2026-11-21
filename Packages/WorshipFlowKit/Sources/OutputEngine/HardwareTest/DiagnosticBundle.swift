// UI-002 Part 2: the app's diagnostic bundle for the Screens mode ("Export log bundle…"). It is the hardware test's own
// bundle, written by the same kit, holding only the environment and device steps: no output is started and no video is
// sent, so it can be exported at any time, mid-service included.
import Foundation

public enum DiagnosticBundle {
    public static func steps() -> [HardwareTestStep] {
        HardwareTestSteps.standard(HardwareTestConfiguration(preset: .quick)).filter { $0.id == .environment || $0.id == .devices }
    }

    /// 0 when the bundle was written to `zip`.
    public static func export(to zip: URL, environment: HardwareEnvironmentSource, provider: HardwareTestProvider,
                              log: @escaping @Sendable (String) -> Void = { _ in }) async -> Int32 {
        let launch = HardwareTestLaunch(simulated: false, preset: .quick, outputPath: zip.path)
        return await HardwareTestHeadless.run(launch, environment: environment, realProvider: provider, steps: steps(), log: log)
    }
}
