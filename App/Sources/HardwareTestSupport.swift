// HWTEST-001 / HW-004: what the Hardware Test window and the headless run need from the app: the machine's displays and
// the card provider. Since HW-004 the provider is the real DeckLink bridge (`AppSDI.deckLink`); on this development Mac,
// which has no card and no Desktop Video driver, it reports "driver not installed". Nothing here is Hardware Verified.
import AppKit
import CoreGraphics
import DeckLinkSDI
import OutputEngine
import SDIEngine

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
    /// FIX-D S1: each card also carries what the kit needs to put its profile back after the fill and key step: it reads the
    /// active profile of every connector pair and switches the pairs back, through the bridge's own profile call.
    /// Nothing here has run against a real card.
    static func realProvider() -> HardwareTestProvider {
        var provider = HardwareTestProvider(provider: AppSDI.deckLink)
        let base = provider.devices
        provider.devices = {
            let cards = AppSDI.deckLink.devices()
            return base().map { device in
                guard let card = cards.first(where: { $0.identifier.description == device.id }) else { return device }
                var d = device
                d.captureProfiles = { Self.captureProfiles(of: card) }
                d.restoreProfiles = { record in try await Self.restoreProfiles(record, on: card) }
                return d
            }
        }
        return provider
    }

    /// The active profile of each connector pair (a pair is sub-device 0 for connectors 1 and 2, sub-device 1 for 3 and 4).
    static func captureProfiles(of card: DeckLinkDevice) -> HardwareProfileRecord? {
        let pairCount = max(1, card.layout.connectorCount / 2)
        let subs = card.subDevices
        let pairs = (0..<pairCount).map { pair -> HardwareProfileRecord.Pair in
            let active = subs.first { $0.subDeviceIndex == pair }?.activeProfile
            return HardwareProfileRecord.Pair(firstConnector: 2 * pair + 1, name: active.map { DeckLinkProfile.name($0) }, identifier: active)
        }
        return pairs.contains { $0.identifier != nil } ? HardwareProfileRecord(pairs: pairs) : nil
    }

    /// Switches every pair that is not in its recorded profile back to it, one at a time, each waiting for the card to say it is active.
    static func restoreProfiles(_ record: HardwareProfileRecord, on card: DeckLinkDevice) async throws {
        for pair in record.pairs {
            guard let wanted = pair.identifier else { continue }
            let index = (pair.firstConnector - 1) / 2
            let now = card.subDevices.first { $0.subDeviceIndex == index }?.activeProfile
            if now != wanted { try await card.activateProfile(wanted, forPair: index) }
        }
    }

    /// Where a real test run writes its visible "unfinished" folder: the Desktop, or the folder named by `--unfinished-folder`
    /// (used by tests and by the coordinator, so nothing lands on a real Desktop).
    static func unfinishedParent() -> URL? {
        HardwareTestUnfinished.parent(arguments: CommandLine.arguments, desktop: HardwareTestUnfinished.desktop())
    }
}
