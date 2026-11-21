// HW-002: how the coordinator reaches SDI cards, without knowing which kind. The app injects this: it returns the
// simulated card when the "Show simulated SDI device" developer setting is on and nothing otherwise, because there is
// no real provider yet (no vendor SDK has been used or downloaded).
import Foundation
import Domain
import SDIEngine

/// One card the coordinator can plan against and open ports on. A value, so a provider can build it freely.
public struct SDIDeviceHandle: Sendable {
    public let id: String
    public let info: SDIDeviceInfo
    public let supportedModes: [SDIVideoMode]
    private let connected: @Sendable () -> Bool
    private let open: @Sendable (Int) throws -> any SDIOutputPort

    public init(id: String, info: SDIDeviceInfo, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown,
                isConnected: @escaping @Sendable () -> Bool, openOutput: @escaping @Sendable (Int) throws -> any SDIOutputPort) {
        self.id = id
        self.info = info
        self.supportedModes = supportedModes
        self.connected = isConnected
        self.open = openOutput
    }

    public init<D: SDIDevice>(id: String, device: D, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown) {
        self.init(id: id, info: device.info, supportedModes: supportedModes,
                  isConnected: { device.isConnected }, openOutput: { try device.openOutput(connector: $0) })
    }

    public var isConnected: Bool { connected() }
    public func openOutput(connector: Int) throws -> any SDIOutputPort { try open(connector) }
    public var status: SDIDeviceStatus { SDIDeviceStatus(id: id, info: info, isConnected: isConnected, supportedModes: supportedModes) }
}

/// Everything an SDI output needs that the coordinator worked out: where it goes, how, and the open port.
public struct SDIOutputSetup {
    public let slot: OutputSlot
    public let planned: PlannedSDIOutput
    public let port: any SDIOutputPort
    public let info: SDIDeviceInfo
}

public struct SDIEnvironment {
    public typealias DeviceProvider = @MainActor () -> [SDIDeviceHandle]
    public typealias TargetFactory = @MainActor (ScreenProfile, SDIOutputSetup) throws -> any OutputTarget

    public var devices: DeviceProvider
    /// Builds the output for an opened port (normally an `SDIOutput` with the app's scene provider and clock).
    /// The coordinator closes the port again if this throws.
    public var makeTarget: TargetFactory

    public init(devices: @escaping DeviceProvider, makeTarget: @escaping TargetFactory) {
        self.devices = devices
        self.makeTarget = makeTarget
    }
}
