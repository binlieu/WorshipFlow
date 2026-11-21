// HWTEST-001: the data a hardware test produces. Plain Codable values: the report on disk is the product, so the
// coordinator can read a bundle later without this code running a test.
import Foundation
import SDIEngine

public enum HardwareTestOutcome: String, Codable, Sendable, CaseIterable {
    case passed, failed, skipped
    /// The step ran as far as it can on its own; a person has to look at something or answer something.
    case needsHuman
    /// Part of what the step claims was measured and part was not (for example the unplug was measured and the replug
    /// was skipped). FIX-D S3: a step is PASSED only when everything it claims was measured.
    case partial

    public var label: String {
        switch self {
        case .passed: return "PASSED"
        case .failed: return "FAILED"
        case .skipped: return "SKIPPED"
        case .needsHuman: return "NEEDS A PERSON"
        case .partial: return "PARTLY MEASURED"
        }
    }
}

public enum HardwareTestStepID: String, Codable, Sendable, CaseIterable {
    case environment, devices, outputRun, loopback, fillKeyLoopback, modeSweep, fourOutputs, unplugReplug, humanChecks
}

public struct HardwareMeasurement: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var unit: String?
    public init(name: String, value: String, unit: String? = nil) {
        self.name = name
        self.value = value
        self.unit = unit
    }
}

public struct HardwareStepResult: Codable, Equatable, Sendable {
    public var id: HardwareTestStepID
    public var number: Int
    public var title: String
    public var outcome: HardwareTestOutcome
    /// Plain language: what happened and, when it failed, what to look at.
    public var summary: String
    /// The thresholds, stated in the result and never hidden.
    public var passCriteria: String
    public var measurements: [HardwareMeasurement]
    /// What the step says about the unverified facts (UNV-02, UNV-03, UNV-04), only where it measured something.
    public var findings: [String]
    /// Things that happened at a moment, in order, for example "12 s: 2 frames late".
    public var events: [String]
    /// Raw per-sample values by name, one per `sampleIntervalSeconds`.
    public var samples: [String: [Double]]
    public var sampleIntervalSeconds: Double?
    /// UTC, no zone name.
    public var startedAt: String
    public var durationSeconds: Double
    /// FIX-D S1: set when the step ran while the card was still in the keying profile (the original profile could not be put
    /// back), so a reader knows which connector layout the step's numbers belong to.
    public var profileNote: String?

    public init(id: HardwareTestStepID, number: Int, title: String, outcome: HardwareTestOutcome, summary: String,
                passCriteria: String = "", measurements: [HardwareMeasurement] = [], findings: [String] = [], events: [String] = [],
                samples: [String: [Double]] = [:], sampleIntervalSeconds: Double? = nil, startedAt: String = "", durationSeconds: Double = 0,
                profileNote: String? = nil) {
        self.profileNote = profileNote
        self.id = id
        self.number = number
        self.title = title
        self.outcome = outcome
        self.summary = summary
        self.passCriteria = passCriteria
        self.measurements = measurements
        self.findings = findings
        self.events = events
        self.samples = samples
        self.sampleIntervalSeconds = sampleIntervalSeconds
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
    }
}

/// FIX-D S1: the outcome of putting the card's profile back after the kit changed it for the fill and key step.
public struct HardwareProfileRestore: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        /// The profile was put back and a second reading of the card agrees with the one taken at the start.
        case restoredAndVerified
        /// The card refused, or the call failed.
        case failed
        /// The call returned, but the card's layout could not be shown to match the one at the start.
        case notVerified
    }
    public var state: State
    public var detail: String
    public init(state: State, detail: String) {
        self.state = state
        self.detail = detail
    }
    /// True when later steps ran in the keying profile.
    public var leftInKeyingProfile: Bool { state != .restoredAndVerified }
}

public struct HardwareDisplayInfo: Codable, Equatable, Sendable {
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var scale: Double
    public var refreshRateHz: Double?
    public init(name: String, pixelWidth: Int, pixelHeight: Int, scale: Double, refreshRateHz: Double?) {
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.scale = scale
        self.refreshRateHz = refreshRateHz
    }
}

/// Whether the Blackmagic driver is there, as the device provider can tell.
public struct HardwareDriverStatus: Codable, Equatable, Sendable {
    public var isInstalled: Bool
    public var apiVersion: String?
    public var driverVersion: String?
    /// Whether this app can load Blackmagic's framework (the entitlement check, KI-055). Nil when the provider cannot say;
    /// false when the framework's files are on the Mac and loading them was refused.
    public var frameworkLoadable: Bool?
    /// For the tester, in plain words.
    public var message: String
    public init(isInstalled: Bool, apiVersion: String? = nil, driverVersion: String? = nil, frameworkLoadable: Bool? = nil, message: String) {
        self.isInstalled = isInstalled
        self.apiVersion = apiVersion
        self.driverVersion = driverVersion
        self.frameworkLoadable = frameworkLoadable
        self.message = message
    }

    /// What a provider says about its environment (HW-004).
    public init(_ environment: SDIEnvironmentStatus) {
        self.init(isInstalled: environment.driverInstalled, apiVersion: environment.apiVersion, frameworkLoadable: environment.frameworkLoadable,
                  message: environment.message)
    }
}

/// Which of three situations the tester is in, and the words for it (HW-004): the driver is not installed, the driver is
/// installed but no card is found, or a card is found.
public struct HardwareCardState: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case driverNotInstalled, noCardFound, cardFound }
    public var state: Kind
    public var text: String

    public static func describe(driver: HardwareDriverStatus, cards: [String]) -> HardwareCardState {
        if !cards.isEmpty { return HardwareCardState(state: .cardFound, text: "Card found: " + cards.joined(separator: ", ")) }
        if !driver.isInstalled {
            // Files on the Mac that could not be loaded is a different problem from nothing installed: the provider's words say so.
            if driver.frameworkLoadable == false { return HardwareCardState(state: .driverNotInstalled, text: driver.message) }
            return HardwareCardState(
                state: .driverNotInstalled,
                text: "Blackmagic Desktop Video is not installed on this Mac. Install Blackmagic Desktop Video from the Blackmagic Design support site, restart the Mac, open WORSHIPFLOW again, then press Rescan.")
        }
        let version = driver.apiVersion.map { " (driver API \($0))" } ?? ""
        return HardwareCardState(
            state: .noCardFound,
            text: "Blackmagic Desktop Video is installed\(version), but no DeckLink card was found. Check the Thunderbolt cable and that the enclosure is switched on, then press Rescan.")
    }
}

/// What the vendor's manual says, for the report to compare the hardware with. Not a measurement.
enum HardwareTestManual {
    /// The Duo 2's connector table for the paired profile (SDK manual, "Device Profiles"): fill on the pair's second
    /// connector, key on the first. Nil for any other model: the table covers the Duo 2 only.
    static func keyRoute(modelName: String, firstConnector: Int) -> (fill: Int, key: Int)? {
        guard modelName.lowercased().contains("duo 2") else { return nil }
        return (fill: firstConnector + 1, key: firstConnector)
    }
}

/// No user name, no home-folder path, no serial number, no host name: nothing that identifies a person or one machine.
public struct HardwareEnvironmentInfo: Codable, Equatable, Sendable {
    public var appVersion: String
    public var appBuild: String
    public var osVersion: String
    public var osBuild: String
    public var macModel: String
    public var chip: String
    public var memoryGB: Double
    public var processorCount: Int
    public var displays: [HardwareDisplayInfo]
    public var driver: HardwareDriverStatus
    /// UTC, no zone name.
    public var collectedAt: String

    public init(appVersion: String, appBuild: String, osVersion: String, osBuild: String, macModel: String, chip: String,
                memoryGB: Double, processorCount: Int, displays: [HardwareDisplayInfo], driver: HardwareDriverStatus, collectedAt: String) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.macModel = macModel
        self.chip = chip
        self.memoryGB = memoryGB
        self.processorCount = processorCount
        self.displays = displays
        self.driver = driver
        self.collectedAt = collectedAt
    }
}

public struct HardwareTestReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindName = "worshipflow-hardware-test"
    public static let kitVersion = "1.0"
    public static let disclaimer = "This report describes what was measured on this run. It is not a certification."

    public var schemaVersion: Int
    public var kind: String
    public var kitVersion: String
    /// UTC, no zone name.
    public var startedAt: String
    public var finishedAt: String?
    /// False while the run is going, and in a file left behind by a run that did not finish.
    public var complete: Bool
    public var simulated: Bool
    public var deviceName: String?
    public var deviceID: String?
    public var preset: String
    public var environment: HardwareEnvironmentInfo?
    public var steps: [HardwareStepResult]
    public var disclaimer: String
    /// FIX-D S1: the profile and connector layout the card was in before any step ran, in words; nil when the provider cannot say.
    public var profileAtStart: String?
    /// FIX-D S1: what became of a profile change the kit made. Nil: the kit never changed the card's profile.
    public var profileRestore: HardwareProfileRestore?
    /// FIX-D S6: the step that was running when the file was last written, so a report left by a crash says where it stopped.
    public var runningStep: Int?
    public var runningStepTitle: String?

    public init(simulated: Bool, deviceName: String?, deviceID: String?, preset: String, startedAt: String) {
        schemaVersion = Self.currentSchemaVersion
        kind = Self.kindName
        kitVersion = Self.kitVersion
        self.startedAt = startedAt
        finishedAt = nil
        complete = false
        self.simulated = simulated
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.preset = preset
        environment = nil
        steps = []
        disclaimer = Self.disclaimer
    }

    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

// MARK: configuration

/// How long each timed step runs, in seconds of test time.
public struct HardwareTestDurations: Codable, Equatable, Sendable {
    public var outputRunSeconds: Double
    public var loopbackSeconds: Double
    /// For each alpha mode, split between the window and the ramp.
    public var keyedSecondsPerMode: Double
    public var fourOutputSeconds: Double

    public init(outputRunSeconds: Double, loopbackSeconds: Double, keyedSecondsPerMode: Double, fourOutputSeconds: Double) {
        self.outputRunSeconds = outputRunSeconds
        self.loopbackSeconds = loopbackSeconds
        self.keyedSecondsPerMode = keyedSecondsPerMode
        self.fourOutputSeconds = fourOutputSeconds
    }

    public static let quick = HardwareTestDurations(outputRunSeconds: 30, loopbackSeconds: 15, keyedSecondsPerMode: 10, fourOutputSeconds: 30)
    public static let standard = HardwareTestDurations(outputRunSeconds: 600, loopbackSeconds: 60, keyedSecondsPerMode: 30, fourOutputSeconds: 300)
    public static let long = HardwareTestDurations(outputRunSeconds: 3600, loopbackSeconds: 180, keyedSecondsPerMode: 60, fourOutputSeconds: 300)
}

public enum HardwareTestPreset: String, Codable, Sendable, CaseIterable {
    case quick, standard, long

    public var durations: HardwareTestDurations {
        switch self {
        case .quick: return .quick
        case .standard: return .standard
        case .long: return .long
        }
    }

    public var title: String {
        switch self {
        case .quick: return "Quick (about 3 minutes)"
        case .standard: return "Standard (about 20 minutes)"
        case .long: return "Long (about 70 minutes)"
        }
    }
}

public struct HardwareTestConfiguration: Equatable, Sendable {
    public var preset: HardwareTestPreset
    public var durations: HardwareTestDurations
    /// Nil: the first connected device.
    public var deviceID: String?
    public var outputConnector: Int
    /// The loopback cables go from the output connectors to these inputs: 1 to 3 and 2 to 4 on a four-connector card.
    public var loopbackInputConnector: Int
    public var keyInputConnector: Int
    public var includeUnplugTest: Bool
    public var includeHumanChecks: Bool

    public init(preset: HardwareTestPreset = .quick, durations: HardwareTestDurations? = nil, deviceID: String? = nil,
                outputConnector: Int = 1, loopbackInputConnector: Int = 3, keyInputConnector: Int = 4,
                includeUnplugTest: Bool = false, includeHumanChecks: Bool = false) {
        self.preset = preset
        self.durations = durations ?? preset.durations
        self.deviceID = deviceID
        self.outputConnector = outputConnector
        self.loopbackInputConnector = loopbackInputConnector
        self.keyInputConnector = keyInputConnector
        self.includeUnplugTest = includeUnplugTest
        self.includeHumanChecks = includeHumanChecks
    }

    /// The mode every step that runs video uses.
    public static let testMode = SDIVideoMode.hd1080p5994
}
