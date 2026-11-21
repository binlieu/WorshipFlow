// HW-003 / DIST-06: is the Blackmagic Desktop Video driver here, and what should the operator be told?
import DeckLinkC
import Foundation

public struct DeckLinkEnvironment: Equatable, Sendable {
    /// The driver loaded and answered. False on every Mac without Desktop Video, including this development Mac.
    public var driverPresent: Bool
    /// The API version the driver reports, for example "16.0". Nil when absent or not reported.
    public var apiVersion: String?
    /// The version of the SDK headers this app was built against.
    public var compiledAPIVersion: String
    /// Plain language for the operator. Always set.
    public var message: String
    /// The vendor framework's files exist on this Mac. With `driverPresent` false this means loading them was refused
    /// (KI-055, the hardened-runtime entitlement), which is a different problem from the driver not being installed.
    public var frameworkOnDisk: Bool

    public init(driverPresent: Bool, apiVersion: String?, compiledAPIVersion: String, message: String, frameworkOnDisk: Bool = false) {
        self.driverPresent = driverPresent
        self.apiVersion = apiVersion
        self.compiledAPIVersion = compiledAPIVersion
        self.message = message
        self.frameworkOnDisk = frameworkOnDisk
    }

    public static let driverMissingMessage = "Blackmagic Desktop Video is not installed on this Mac. SDI outputs need it. Install Blackmagic Desktop Video from the Blackmagic Design support site, restart the Mac, then open WORSHIPFLOW again. Screens on displays and windows still work."

    /// Where the vendor framework lives. The SDK loads it from here at run time.
    public static let frameworkPath = "/Library/Frameworks/DeckLinkAPI.framework"

    /// Builds the environment from facts. Separate from `current` so the wording can be tested.
    public static func make(driverPresent: Bool, apiVersion: String?, compiledAPIVersion: String, frameworkOnDisk: Bool = false) -> DeckLinkEnvironment {
        if !driverPresent {
            return DeckLinkEnvironment(driverPresent: false, apiVersion: nil, compiledAPIVersion: compiledAPIVersion, message: driverMissingMessage,
                                       frameworkOnDisk: frameworkOnDisk)
        }
        let version = apiVersion.map { "version \($0)" } ?? "an unknown version"
        let message = "Blackmagic Desktop Video is installed (driver API \(version); this app was built for \(compiledAPIVersion))."
        return DeckLinkEnvironment(driverPresent: true, apiVersion: apiVersion, compiledAPIVersion: compiledAPIVersion, message: message, frameworkOnDisk: true)
    }

    /// Asks the driver now. Safe on a Mac without the driver. The SDK loads its framework once per process, so a
    /// driver installed while the app runs is not noticed until the app is restarted.
    public static var current: DeckLinkEnvironment {
        let info = DLBDriverInfo.current()
        return make(driverPresent: info.present, apiVersion: info.apiVersionString, compiledAPIVersion: DLBDriverInfo.compiledAPIVersionString,
                    frameworkOnDisk: FileManager.default.fileExists(atPath: frameworkPath))
    }
}

/// Why a DeckLink operation could not start, in words for the operator.
public enum DeckLinkError: Error, Equatable, Sendable, LocalizedError {
    case driverNotInstalled
    case profileUnavailable(String)
    case profileChangeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .driverNotInstalled: return DeckLinkEnvironment.driverMissingMessage
        case .profileUnavailable(let detail): return "This card does not offer that profile. \(detail)"
        case .profileChangeFailed(let detail): return "The card did not switch profile. \(detail)"
        }
    }
}
