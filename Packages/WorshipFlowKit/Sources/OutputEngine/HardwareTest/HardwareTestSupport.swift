// HWTEST-001: what the hardware test is given instead of reaching for globals: devices, a clock, a way to ask the
// tester something, and probes for the machine. Everything is injected, so every step runs against the simulator in a
// unit test and against a real card in the field with no change to the steps.
import Foundation
import Darwin
import SDIEngine

// MARK: devices

/// FIX-D S1: the profile each connector pair of a card was in, read before the kit changes anything, so it can be put back.
/// `identifier` is whatever the provider needs to restore the pair (for a DeckLink card the profile id); the kit never
/// interprets it.
public struct HardwareProfileRecord: Equatable, Sendable {
    public struct Pair: Equatable, Sendable {
        public var firstConnector: Int
        public var name: String?
        public var identifier: UInt32?
        public init(firstConnector: Int, name: String?, identifier: UInt32?) {
            self.firstConnector = firstConnector
            self.name = name
            self.identifier = identifier
        }
    }
    public var pairs: [Pair]
    public init(pairs: [Pair]) { self.pairs = pairs }

    /// "connectors 1 and 2: one sub-device, full duplex; connectors 3 and 4: ..."
    public var text: String {
        pairs.map { "connectors \($0.firstConnector) and \($0.firstConnector + 1): \($0.name ?? "profile not reported")" }.joined(separator: "; ")
    }
}

/// A cable between two connectors of the card, output to input.
public struct HardwareCable: Equatable, Sendable, Codable {
    public var output: Int
    public var input: Int
    public init(output: Int, input: Int) {
        self.output = output
        self.input = input
    }
    public var text: String { "SDI \(output) to SDI \(input)" }
}

/// One card, as the kit sees it. A value built from closures so the real provider can fill it in without the kit
/// knowing which SDK is behind it (for the simulator: `init(id:device:)`).
public struct HardwareTestDevice: Sendable {
    public var id: String
    public var info: SDIDeviceInfo
    /// The modes the provider says the card supports at all.
    public var supportedModes: [SDIVideoMode]
    /// The profile or duplex state, in words, or nil when the provider cannot say.
    public var profile: String?
    public var isConnected: @Sendable () -> Bool
    public var openOutput: @Sendable (Int) throws -> any SDIOutputPort
    public var openInput: @Sendable (Int) throws -> any SDIInputPort
    /// Switches the connector pair that starts at the given connector to a profile that can send fill and key (KI-054).
    /// Nil when the provider cannot. The kit only calls it after the tester said yes.
    public var activateKeyingProfile: (@Sendable (Int) async throws -> Void)?
    /// FIX-D S1: reads the profile of every connector pair now, so the kit can put it back. Nil when the provider cannot.
    public var captureProfiles: (@Sendable () -> HardwareProfileRecord?)?
    /// FIX-D S1: puts every pair back to a record taken earlier and waits until the card says it is active. Nil when the
    /// provider cannot. Restoring is always wanted, so the kit calls it without asking.
    public var restoreProfiles: (@Sendable (HardwareProfileRecord) async throws -> Void)?

    public init(id: String, info: SDIDeviceInfo, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown, profile: String? = nil,
                isConnected: @escaping @Sendable () -> Bool,
                openOutput: @escaping @Sendable (Int) throws -> any SDIOutputPort,
                openInput: @escaping @Sendable (Int) throws -> any SDIInputPort,
                activateKeyingProfile: (@Sendable (Int) async throws -> Void)? = nil,
                captureProfiles: (@Sendable () -> HardwareProfileRecord?)? = nil,
                restoreProfiles: (@Sendable (HardwareProfileRecord) async throws -> Void)? = nil) {
        self.captureProfiles = captureProfiles
        self.restoreProfiles = restoreProfiles
        self.id = id
        self.info = info
        self.supportedModes = supportedModes
        self.profile = profile
        self.isConnected = isConnected
        self.openOutput = openOutput
        self.openInput = openInput
        self.activateKeyingProfile = activateKeyingProfile
    }

    /// A card as a provider hands it out (HW-004): the simulated card or a DeckLink card.
    public init(_ device: SDIProvidedDevice) {
        self.init(id: device.id, info: device.info, supportedModes: device.supportedModes, profile: device.profileDescription,
                  isConnected: device.isConnected, openOutput: device.openOutput, openInput: device.openInput,
                  activateKeyingProfile: device.activateKeyingProfile)
    }

    public init<D: SDIDevice>(id: String, device: D, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown, profile: String? = nil) {
        self.init(id: id, info: device.info, supportedModes: supportedModes, profile: profile,
                  isConnected: { device.isConnected },
                  openOutput: { try device.openOutput(connector: $0) },
                  openInput: { try device.openInput(connector: $0) })
    }
}

public struct HardwareTestProvider: Sendable {
    /// True when the provider has no real card behind it. A report from such a provider is marked SIMULATED.
    public var isSimulated: Bool
    public var devices: @Sendable () -> [HardwareTestDevice]
    public var driver: @Sendable () -> HardwareDriverStatus
    /// Looks for cards again; may take a moment, so it is called off the main thread. Nil when there is nothing to scan.
    public var rescan: (@Sendable () -> Void)?

    public init(isSimulated: Bool, devices: @escaping @Sendable () -> [HardwareTestDevice], driver: @escaping @Sendable () -> HardwareDriverStatus,
                rescan: (@Sendable () -> Void)? = nil) {
        self.isSimulated = isSimulated
        self.devices = devices
        self.driver = driver
        self.rescan = rescan
    }

    /// The kit's view of an `SDIDeviceProviding` provider (HW-004): the real DeckLink provider in the app, or the
    /// simulated card. It is marked simulated when the provider says it is not hardware at all.
    public init(provider: any SDIDeviceProviding) {
        self.init(isSimulated: provider.environmentStatus().state == .simulated,
                  devices: { provider.currentDevices().map { HardwareTestDevice($0) } },
                  driver: { HardwareDriverStatus(provider.environmentStatus()) },
                  rescan: { provider.rescan() })
    }
}

// MARK: clock

/// Test time. A real clock waits; the simulated one moves the simulated card along instead, so a 30-second run takes
/// seconds. Every step waits through the clock and never sleeps on its own.
public protocol HardwareTestClock: Sendable {
    /// Seconds of test time since the clock was made.
    func now() -> Double
    /// Lets this much test time pass. Throws if the task is cancelled.
    func wait(seconds: Double) async throws
}

public struct RealHardwareTestClock: HardwareTestClock {
    private let origin = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    public init() {}
    public func now() -> Double { Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - origin) / 1_000_000_000 }
    public func wait(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}

/// Virtual time for the simulated card: `wait` plays that many frame periods on every simulated device, as fast as the
/// machine can, and returns. Simulated: it proves the kit's logic, not the timing of a real card.
/// `@unchecked Sendable`: `elapsed` and `framesPlayed` are only touched while holding `lock`.
public final class SimulatedHardwareTestClock: HardwareTestClock, @unchecked Sendable {
    private let devices: [SimulatedSDIDevice]
    private let framesPerSecond: Double
    private let lock = NSLock()
    private var elapsed = 0.0
    private var framesPlayed = 0

    public init(devices: [SimulatedSDIDevice], mode: SDIVideoMode = HardwareTestConfiguration.testMode) {
        self.devices = devices
        self.framesPerSecond = mode.framesPerSecond
    }

    public func now() -> Double { lock.withLock { elapsed } }

    public func wait(seconds: Double) async throws {
        try Task.checkCancellation()
        guard seconds > 0 else { return }
        let frames: Int = lock.withLock {
            elapsed += seconds
            let target = Int((elapsed * framesPerSecond).rounded(.down))
            let due = target - framesPlayed
            framesPlayed = target
            return max(0, due)
        }
        var left = frames
        while left > 0 {
            let chunk = min(left, 30)
            for d in devices { d.advance(frames: chunk) }
            left -= chunk
            try Task.checkCancellation()
            await Task.yield()          // never hold a thread of the shared pool for long: other tasks (and timers) need it
        }
        await Task.yield()
    }
}

// MARK: asking the tester

public enum HardwarePromptKind: String, Codable, Sendable {
    case connectLoopbackCable, connectKeyCables, changeProfile, unplugDevice, replugDevice, humanBars, humanKeyEdges, photo
    /// FIX-D S4: "move the cables to these connectors".
    case moveCables
    /// FIX-D S4: "take the cables off".
    case removeCables
    /// FIX-D S7: "fill and key came out the other way round: are the cables exactly as shown?"
    case confirmCables
}

public struct HardwarePrompt: Equatable, Sendable {
    public var kind: HardwarePromptKind
    public var title: String
    public var message: String
    /// The labels for the buttons, so the window can show what each one means.
    public var primaryLabel: String
    public var secondaryLabel: String?
    public var canSkip: Bool
    /// The cables the prompt asks for, so a simulated tester can place them and a window can show them. Empty for a prompt
    /// about something else.
    public var cables: [HardwareCable]

    public init(kind: HardwarePromptKind, title: String, message: String, primaryLabel: String, secondaryLabel: String? = nil, canSkip: Bool = true,
                cables: [HardwareCable] = []) {
        self.cables = cables
        self.kind = kind
        self.title = title
        self.message = message
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.canSkip = canSkip
    }
}

public enum HardwareAnswer: Equatable, Sendable {
    /// "Continue" or "Done".
    case proceed
    case skip
    case yes
    case no
    /// A photo the tester chose: its file path.
    case attachment(String)
    /// Nobody can answer (a run with no person at the keyboard).
    case unavailable
}

public protocol HardwareTestInteraction: Sendable {
    func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer
}

/// For a run with nobody at the keyboard: cables are assumed to be connected, and anything that needs a person to
/// look or to do something is reported as unanswerable.
public struct AutomaticInteraction: HardwareTestInteraction {
    public init() {}
    public func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        switch prompt.kind {
        case .connectLoopbackCable, .connectKeyCables, .moveCables, .removeCables, .confirmCables: return .proceed
        case .photo: return .skip
        // Nobody is there to say yes, so a card's profile is never changed in a run with no person at the keyboard.
        case .changeProfile, .unplugDevice, .replugDevice, .humanBars, .humanKeyEdges: return .unavailable
        }
    }
}

/// A "tester" for the simulated card: it unplugs and replugs the simulated card when asked, it cannot look at a monitor, and,
/// when the prompt lists cables, it places them (always for a request to move cables or take them off; for the first
/// cables only when `placesCables` is set, because older tests wire the card themselves).
public struct SimulatedInteraction: HardwareTestInteraction {
    /// How the simulated tester wires the fill and key cables (S7).
    public enum Cabling: Sendable {
        case asInstructed
        /// The two key cables are crossed when first placed; the tester fixes them when asked to confirm them.
        case crossedUntilConfirmed
        /// The two key cables are crossed and stay crossed whatever the tester is asked.
        case crossedAndStayingCrossed
    }

    private let device: SimulatedSDIDevice
    private let placesCables: Bool
    private let cabling: Cabling
    private let wireSource: @Sendable (Int) -> Int

    public init(device: SimulatedSDIDevice, placesCables: Bool = false, cabling: Cabling = .asInstructed,
                wireSource: @escaping @Sendable (Int) -> Int = { $0 }) {
        self.device = device
        self.placesCables = placesCables
        self.cabling = cabling
        self.wireSource = wireSource
    }

    /// Plugs the cables in. A cable from connector `o` to input `i` carries what `wireSource(o)` shows (a wrongly wired card
    /// sends another output's picture out of `o`).
    public func place(_ cables: [HardwareCable], replacingOthers: Bool) {
        if replacingOthers { for c in 1...max(1, device.info.connectorCount) { device.disconnect(input: c) } }
        for cable in cables { device.connect(output: wireSource(cable.output), toInput: cable.input) }
    }

    private func crossed(_ cables: [HardwareCable]) -> [HardwareCable] {
        guard cables.count == 2 else { return cables }
        return [HardwareCable(output: cables[0].output, input: cables[1].input), HardwareCable(output: cables[1].output, input: cables[0].input)]
    }

    public func ask(_ prompt: HardwarePrompt) async -> HardwareAnswer {
        switch prompt.kind {
        case .connectLoopbackCable, .changeProfile: if placesCables { place(prompt.cables, replacingOthers: false) }; return .proceed
        case .connectKeyCables:
            if placesCables { place(cabling == .asInstructed ? prompt.cables : crossed(prompt.cables), replacingOthers: false) }
            return .proceed
        case .moveCables: place(prompt.cables, replacingOthers: true); return .proceed
        case .removeCables: for c in prompt.cables { device.disconnect(input: c.input) }; return .proceed
        case .confirmCables:
            if cabling == .crossedUntilConfirmed { place(prompt.cables, replacingOthers: false) }
            return .proceed
        case .unplugDevice: device.simulateUnplug(); return .proceed
        case .replugDevice: device.simulateReplug(); return .proceed
        case .photo: return .skip
        case .humanBars, .humanKeyEdges: return .unavailable
        }
    }
}

// MARK: the simulated set-up

/// The simulated card with its cables, clock and tester, ready to hand to a runner.
public struct HardwareTestRig: Sendable {
    public var provider: HardwareTestProvider
    public var clock: any HardwareTestClock
    public var interaction: any HardwareTestInteraction
    public var device: SimulatedSDIDevice

    public init(provider: HardwareTestProvider, clock: any HardwareTestClock, interaction: any HardwareTestInteraction, device: SimulatedSDIDevice) {
        self.provider = provider
        self.clock = clock
        self.interaction = interaction
        self.device = device
    }

    public static let simulatedDeviceID = "simulated-sdi-duo2"

    /// `cabled` joins SDI 1 to SDI 3 and SDI 2 to SDI 4, the way the tester is told to.
    public static func simulated(device: SimulatedSDIDevice = SimulatedSDIDevice(), faults: SimulatedFaults = .none, cabled: Bool = true) -> HardwareTestRig {
        device.setFaults(faults)
        if cabled, device.info.connectorCount >= 4 {
            device.connect(output: 1, toInput: 3)
            device.connect(output: 2, toInput: 4)
        }
        let handle = HardwareTestDevice(id: simulatedDeviceID, device: device, profile: "Simulated card: no profiles or duplex modes")
        let driver = HardwareDriverStatus(isInstalled: false, message: "Simulated card: no Blackmagic driver is involved.")
        let provider = HardwareTestProvider(isSimulated: true, devices: { [handle] }, driver: { driver })
        return HardwareTestRig(provider: provider, clock: SimulatedHardwareTestClock(devices: [device]),
                               interaction: SimulatedInteraction(device: device), device: device)
    }
}

// MARK: machine probes

public struct HardwareResourceSample: Sendable, Equatable {
    public var residentBytes: UInt64
    /// CPU time used by this process so far, in seconds.
    public var cpuSeconds: Double
    /// A monotonic wall clock, in seconds.
    public var wallSeconds: Double
    public init(residentBytes: UInt64, cpuSeconds: Double, wallSeconds: Double) {
        self.residentBytes = residentBytes
        self.cpuSeconds = cpuSeconds
        self.wallSeconds = wallSeconds
    }
}

/// Memory and CPU of this process, for the four-output step (UNV-04).
public struct HardwareResourceProbe: Sendable {
    public var sample: @Sendable () -> HardwareResourceSample?
    public init(_ sample: @escaping @Sendable () -> HardwareResourceSample?) { self.sample = sample }

    public static let system = HardwareResourceProbe {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6 + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return HardwareResourceSample(residentBytes: UInt64(info.resident_size), cpuSeconds: cpu,
                                      wallSeconds: Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1e9)
    }
}

/// How long the app takes to answer, in milliseconds (the app measures a round trip to its main thread), or nil if it
/// cannot measure. The unplug step uses it to tell whether the app stayed responsive.
public struct HardwareResponsivenessProbe: Sendable {
    public var measure: @Sendable () async -> Double?
    public init(_ measure: @escaping @Sendable () async -> Double?) { self.measure = measure }
    public static let unavailable = HardwareResponsivenessProbe { nil }
}

public struct HardwareSystemInfo: Sendable, Equatable {
    public var osVersion: String
    public var osBuild: String
    public var macModel: String
    public var chip: String
    public var memoryBytes: UInt64
    public var processorCount: Int
    public init(osVersion: String, osBuild: String, macModel: String, chip: String, memoryBytes: UInt64, processorCount: Int) {
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.macModel = macModel
        self.chip = chip
        self.memoryBytes = memoryBytes
        self.processorCount = processorCount
    }
}

/// Where the environment step gets its facts. No serial number, user name or host name is ever asked for.
public struct HardwareEnvironmentSource: Sendable {
    public var appVersion: String
    public var appBuild: String
    public var displays: @Sendable () -> [HardwareDisplayInfo]
    public var system: @Sendable () -> HardwareSystemInfo
    public var now: @Sendable () -> Date

    public init(appVersion: String, appBuild: String, displays: @escaping @Sendable () -> [HardwareDisplayInfo],
                system: @escaping @Sendable () -> HardwareSystemInfo, now: @escaping @Sendable () -> Date = { Date() }) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.displays = displays
        self.system = system
        self.now = now
    }

    /// The real machine. `displays` comes from the app, because listing screens needs AppKit.
    public static func system(appVersion: String, appBuild: String, displays: @escaping @Sendable () -> [HardwareDisplayInfo]) -> HardwareEnvironmentSource {
        HardwareEnvironmentSource(appVersion: appVersion, appBuild: appBuild, displays: displays, system: { readSystem() })
    }

    static func readSystem() -> HardwareSystemInfo {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        var memory: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memory, &size, nil, 0)
        return HardwareSystemInfo(osVersion: version, osBuild: sysctlString("kern.osversion"), macModel: sysctlString("hw.model"),
                                  chip: sysctlString("machdep.cpu.brand_string"), memoryBytes: memory,
                                  processorCount: ProcessInfo.processInfo.activeProcessorCount)
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

// MARK: log

/// The run's log: one line per event with a UTC time, kept for the bundle and shown live.
/// `@unchecked Sendable`: `entries` is only touched while holding `lock`.
public final class HardwareTestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []
    private let now: @Sendable () -> Date
    private let onLine: (@Sendable (String) -> Void)?

    public init(now: @escaping @Sendable () -> Date = { Date() }, onLine: (@Sendable (String) -> Void)? = nil) {
        self.now = now
        self.onLine = onLine
    }

    public func add(_ message: String) {
        let line = "\(HardwareTestClockText.iso(now()))  \(message)"
        lock.withLock { entries.append(line) }
        onLine?(line)
    }

    public var text: String { lock.withLock { entries.joined(separator: "\n") + (entries.isEmpty ? "" : "\n") } }
    public var lines: [String] { lock.withLock { entries } }
}

enum HardwareTestClockText {
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
