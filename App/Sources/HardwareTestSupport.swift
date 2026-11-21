// HWTEST-001 / HW-004: what the Hardware Test window and the headless run need from the app: the machine's displays and
// the card provider. Since HW-004 the provider is the real DeckLink bridge (`AppSDI.deckLink`); on this development Mac,
// which has no card and no Desktop Video driver, it reports "driver not installed". Nothing here is Hardware Verified.
import AppKit
import CoreGraphics
import OutputEngine

enum HardwareTestLaunchMode {
    static let launch = HardwareTestLaunch.parse(CommandLine.arguments)
    /// `--hardware-test` was given: open the Hardware Test window instead of the workspace.
    static var opensHardwareTest: Bool { launch != nil }
    /// `--hardware-test --output <path>`: no window at all.
    static var isHeadless: Bool { launch?.isHeadless == true }
}

enum AppHardwareTest {
    static func environment() -> HardwareEnvironmentSource {
        let info = Bundle.main.infoDictionary
        return .system(appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
                       appBuild: info?["CFBundleVersion"] as? String ?? "unknown",
                       displays: { displays() })
    }

    /// AppKit's screen list belongs to the main thread; the test runs elsewhere, so this asks the main thread.
    static func displays() -> [HardwareDisplayInfo] {
        if Thread.isMainThread { return MainActor.assumeIsolated { readDisplays() } }
        return DispatchQueue.main.sync { MainActor.assumeIsolated { readDisplays() } }
    }

    @MainActor
    private static func readDisplays() -> [HardwareDisplayInfo] {
        NSScreen.screens.map { screen in
            let scale = screen.backingScaleFactor
            var rate: Double?
            if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(number.uint32Value)), mode.refreshRate > 0 {
                rate = mode.refreshRate
            } else if screen.maximumFramesPerSecond > 0 {
                rate = Double(screen.maximumFramesPerSecond)
            }
            return HardwareDisplayInfo(name: screen.localizedName, pixelWidth: Int(screen.frame.width * scale),
                                       pixelHeight: Int(screen.frame.height * scale), scale: scale, refreshRateHz: rate)
        }
    }

    /// The real DeckLink provider, as the kit sees it (HW-004). With no driver it reports no devices and says why.
    static func realProvider() -> HardwareTestProvider {
        HardwareTestProvider(provider: AppSDI.deckLink)
    }
}
