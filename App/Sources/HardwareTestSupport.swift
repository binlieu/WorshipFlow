// HWTEST-001: what the Hardware Test window and the headless run need from the app: the machine's displays, the
// state of the Blackmagic driver, and the card provider. The real provider is not connected yet: the real card bridge is
// built separately (HW-003) and the coordinator wires it in here. Until then the window can find no real card and says so.
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
    /// False until the real DeckLink provider is wired into `realProvider()`. While false, the window tells the tester that
    /// this build cannot reach a card, so a report never suggests that a plugged-in card was looked for and not found.
    static let realProviderIsConnected = false

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

    static func realProvider() -> HardwareTestProvider {
        HardwareTestProvider(isSimulated: false, devices: { [] }, driver: { driverStatus() })
    }

    /// A best-effort look for Blackmagic Desktop Video's files. The real provider will report the driver's own version.
    static func driverStatus() -> HardwareDriverStatus {
        let paths = ["/Applications/Blackmagic Desktop Video", "/Library/Application Support/Blackmagic Design/Desktop Video",
                     "/Library/Frameworks/DeckLinkAPI.framework"]
        let found = paths.first { FileManager.default.fileExists(atPath: $0) }
        guard realProviderIsConnected else {
            return HardwareDriverStatus(
                isInstalled: found != nil,
                message: "This build of WORSHIPFLOW cannot talk to a card yet, so it cannot find one even if one is plugged in. "
                    + (found != nil ? "Blackmagic Desktop Video files were found on this Mac." : "Blackmagic Desktop Video was not found on this Mac either."))
        }
        guard found != nil else {
            return HardwareDriverStatus(
                isInstalled: false,
                message: "Blackmagic Desktop Video does not appear to be installed (its files were not found). Install it from Blackmagic's support site, restart the Mac, then open this window again.")
        }
        return HardwareDriverStatus(isInstalled: true, message: "Blackmagic Desktop Video is installed, but no DeckLink card was found. Check the Thunderbolt cable and that the enclosure is switched on, then press Check again.")
    }
}
