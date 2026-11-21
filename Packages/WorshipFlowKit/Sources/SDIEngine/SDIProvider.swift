// HW-004 / KI-056: how the app and the hardware test reach SDI cards without knowing which kind. A provider lists the cards
// it knows, reports arrivals and removals as a stream, and says in plain words what state its environment is in. The
// simulated card and the DeckLink bridge both provide, and `CompositeSDIProvider` merges several.
import Foundation

/// One card as a provider hands it out: a value built from closures, so a provider can fill it in freely.
public struct SDIProvidedDevice: Sendable {
    public var id: String
    public var info: SDIDeviceInfo
    /// The modes the provider says the card supports at all.
    public var supportedModes: [SDIVideoMode]
    /// The profile or duplex state in words, or nil when the provider cannot say.
    public var profileDescription: String?
    public var isConnected: @Sendable () -> Bool
    public var openOutput: @Sendable (Int) throws -> any SDIOutputPort
    public var openInput: @Sendable (Int) throws -> any SDIInputPort
    /// Switches the connector pair that starts at the given connector to a profile that can key, and waits until the card
    /// says it is active. Nil when the provider cannot do it.
    public var activateKeyingProfile: (@Sendable (Int) async throws -> Void)?

    public init(id: String, info: SDIDeviceInfo, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown, profileDescription: String? = nil,
                isConnected: @escaping @Sendable () -> Bool,
                openOutput: @escaping @Sendable (Int) throws -> any SDIOutputPort,
                openInput: @escaping @Sendable (Int) throws -> any SDIInputPort,
                activateKeyingProfile: (@Sendable (Int) async throws -> Void)? = nil) {
        self.id = id
        self.info = info
        self.supportedModes = supportedModes
        self.profileDescription = profileDescription
        self.isConnected = isConnected
        self.openOutput = openOutput
        self.openInput = openInput
        self.activateKeyingProfile = activateKeyingProfile
    }

    public init<D: SDIDevice>(id: String, device: D, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown, profileDescription: String? = nil,
                              activateKeyingProfile: (@Sendable (Int) async throws -> Void)? = nil) {
        self.init(id: id, info: device.info, supportedModes: supportedModes, profileDescription: profileDescription,
                  isConnected: { device.isConnected },
                  openOutput: { try device.openOutput(connector: $0) },
                  openInput: { try device.openInput(connector: $0) },
                  activateKeyingProfile: activateKeyingProfile)
    }
}

public enum SDIDeviceEvent: Hashable, Sendable {
    case arrived(id: String)
    case removed(id: String)
    /// A card gained or lost a part of itself while staying present (for example a profile change by another program).
    case changed(id: String)
}

/// The state of what a provider stands on: the driver, and whether any card is there.
public struct SDIEnvironmentStatus: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        /// The vendor driver is not installed, or its framework is not there.
        case driverNotInstalled
        /// The driver answers, but no card is found.
        case noCardFound
        case cardFound
        /// Not hardware at all.
        case simulated
    }

    public var state: State
    public var driverInstalled: Bool
    public var apiVersion: String?
    /// Whether this app can load the vendor framework: nil when it cannot tell, false when the files are on the Mac and
    /// loading them was refused (a hardened-runtime entitlement problem, KI-055).
    public var frameworkLoadable: Bool?
    public var deviceCount: Int
    /// Plain language for the operator. Always set.
    public var message: String

    public init(state: State, driverInstalled: Bool, apiVersion: String?, frameworkLoadable: Bool?, deviceCount: Int, message: String) {
        self.state = state
        self.driverInstalled = driverInstalled
        self.apiVersion = apiVersion
        self.frameworkLoadable = frameworkLoadable
        self.deviceCount = deviceCount
        self.message = message
    }
}

public protocol SDIDeviceProviding: Sendable {
    /// The cards known now. Never scans: safe on the main thread. Call `rescan()` to look again.
    func currentDevices() -> [SDIProvidedDevice]
    /// Looks for cards again. May take a moment with a real driver: call it off the main thread.
    func rescan()
    /// Arrivals, removals and changes from now on. Every call makes a new stream; it ends when the provider cannot monitor.
    func events() -> AsyncStream<SDIDeviceEvent>
    func environmentStatus() -> SDIEnvironmentStatus
}

// MARK: simulated

/// Provides the simulated card. Its unplug and replug are events, as a real card's would be.
public final class SimulatedSDIProvider: SDIDeviceProviding, Sendable {
    private let device: SimulatedSDIDevice
    private let id: String

    public init(device: SimulatedSDIDevice, id: String = "simulated-sdi-duo2") {
        self.device = device
        self.id = id
    }

    public func currentDevices() -> [SDIProvidedDevice] {
        [SDIProvidedDevice(id: id, device: device, profileDescription: "Simulated card: no profiles or duplex modes")]
    }

    public func rescan() {}

    public func events() -> AsyncStream<SDIDeviceEvent> {
        let id = self.id
        let source = device.connectionEvents()      // subscribed now, so nothing between this call and the first read is lost
        let (stream, continuation) = AsyncStream<SDIDeviceEvent>.makeStream()
        let task = Task {
            for await connected in source { continuation.yield(connected ? .arrived(id: id) : .removed(id: id)) }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func environmentStatus() -> SDIEnvironmentStatus {
        SDIEnvironmentStatus(state: .simulated, driverInstalled: false, apiVersion: nil, frameworkLoadable: nil, deviceCount: 1,
                             message: "Simulated card: no Blackmagic driver is involved.")
    }
}

// MARK: composite

/// Several providers as one. Devices come in provider order; events are merged; `rescan` reaches every provider.
/// The environment is the first provider that is not simulated, because the operator's question is "is my real card
/// there"; a simulated card beside it must not hide a missing driver. With only simulated providers, the first of those.
public final class CompositeSDIProvider: SDIDeviceProviding, Sendable {
    private let providers: [any SDIDeviceProviding]

    public init(_ providers: [any SDIDeviceProviding]) { self.providers = providers }

    public func currentDevices() -> [SDIProvidedDevice] { providers.flatMap { $0.currentDevices() } }

    public func rescan() { providers.forEach { $0.rescan() } }

    public func events() -> AsyncStream<SDIDeviceEvent> {
        let (stream, continuation) = AsyncStream<SDIDeviceEvent>.makeStream()
        let streams = providers.map { $0.events() }
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                for s in streams { group.addTask { for await e in s { continuation.yield(e) } } }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func environmentStatus() -> SDIEnvironmentStatus {
        let all = providers.map { $0.environmentStatus() }
        return all.first { $0.state != .simulated } ?? all.first
            ?? SDIEnvironmentStatus(state: .noCardFound, driverInstalled: false, apiVersion: nil, frameworkLoadable: nil, deviceCount: 0, message: "No SDI provider is available.")
    }
}
