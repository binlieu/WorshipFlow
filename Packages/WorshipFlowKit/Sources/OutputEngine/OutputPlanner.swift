// HW-002 / OUT-005: one plan for every destination of every screen: displays, windows, SDI connectors, and mirrors.
// `OutputRouter` (Domain) still plans displays and windows; this adds SDI, which Domain cannot know about because it
// cannot import the SDI engine. Pure: no devices, no windows. A screen, and each of its mirrors, is planned and faulted
// on its own; nothing is ever moved to another display or connector.
import Foundation
import Domain
import SDIEngine

/// One destination of one screen: the primary (`mirror == nil`) or the mirror at that index of `ScreenProfile.mirrors`.
public struct OutputSlot: Hashable, Sendable {
    public let screenID: UUID
    public let mirror: Int?
    public init(screenID: UUID, mirror: Int? = nil) {
        self.screenID = screenID
        self.mirror = mirror
    }
    public var isPrimary: Bool { mirror == nil }
}

/// What the planner needs to know about one SDI card.
public struct SDIDeviceStatus: Equatable, Sendable {
    public var id: String
    public var info: SDIDeviceInfo
    public var isConnected: Bool
    public var supportedModes: [SDIVideoMode]

    public init(id: String, info: SDIDeviceInfo, isConnected: Bool, supportedModes: [SDIVideoMode] = SDIVideoMode.allKnown) {
        self.id = id
        self.info = info
        self.isConnected = isConnected
        self.supportedModes = supportedModes
    }
}

public struct PlannedSDIOutput: Equatable, Sendable {
    public var deviceID: String
    public var connector: Int
    /// Set for a keyed output: the connector that carries the key (the pair's second connector unless the device reports
    /// its route the other way round, KI-053). `connector` stays the one the port is opened on.
    public var keyConnector: Int?
    public var fillAlphaMode: AlphaMode
    public var mode: SDIVideoMode
    /// The connector that carries the fill (or the picture, for a plain output). Equals `connector` unless the device's
    /// reported route puts the fill on the pair's second connector.
    public var fillConnector: Int

    public var keying: SDIKeying { keyConnector == nil ? .none : .external(fillAlphaMode: fillAlphaMode) }
}

public enum PlannedDestination: Equatable, Sendable {
    case display(UInt32)
    case window
    case sdi(PlannedSDIOutput)
}

public enum OutputFault: Equatable, Sendable {
    case routing(RoutingFault)
    case sdiDeviceMissing
    case sdiModeUnsupported(String)
    case sdiConnector(SDIPlanFault)

    /// Text for the operator window. Says what happened and what to do.
    public var operatorMessage: String {
        switch self {
        case .routing(let fault): return fault.operatorMessage
        case .sdiDeviceMissing:
            return "The SDI card for this screen is not connected. Reconnect it, or choose another output."
        case .sdiModeUnsupported(let name):
            return "The SDI card does not support the video mode \(name). Choose a mode from the list."
        case .sdiConnector(let fault): return fault.operatorMessage
        }
    }

    /// True when the output should start again by itself once the thing it waits for comes back (KI-012).
    var resumesWhenItReturns: Bool {
        switch self {
        case .routing(.displayMissing), .sdiDeviceMissing: return true
        default: return false
        }
    }
}

public enum ConnectorUse: Equatable, Sendable {
    case unused
    case output(OutputSlot)
    case fill(OutputSlot)
    case key(OutputSlot)
}

/// What each connector of one card carries. `uses[0]` is connector 1.
public struct SDIConnectorMap: Equatable, Sendable {
    public var deviceID: String
    public var uses: [ConnectorUse]
}

public struct OutputPlan: Equatable, Sendable {
    public var assignments: [OutputSlot: PlannedDestination] = [:]
    public var faults: [OutputSlot: OutputFault] = [:]
    /// One per known SDI card, connected or not.
    public var connectorMaps: [String: SDIConnectorMap] = [:]
    /// Every slot that was planned, primaries first.
    public var slots: [OutputSlot] = []

    public init() {}
}

extension SDIVideoMode {
    /// The engine's mode for a Domain description.
    public init(_ description: VideoModeDescription) {
        self.init(width: description.width, height: description.height, frameDurationValue: description.frameDurationValue,
                  timeScale: description.timeScale, isInterlaced: description.isInterlaced, name: description.name)
    }
}

extension VideoModeDescription {
    /// The Domain description of an engine mode, for the interface.
    public init(_ mode: SDIVideoMode) {
        self.init(width: mode.width, height: mode.height, frameDurationValue: mode.frameDurationValue, timeScale: mode.timeScale,
                  isInterlaced: mode.isInterlaced, name: mode.name)
    }
}

extension AlphaMode {
    public init(_ mode: SDIAlphaMode) {
        switch mode {
        case .premultiplied: self = .premultiplied
        case .straight: self = .straight
        }
    }
}

public enum OutputPlanner {
    /// Primaries are planned before mirrors (each in profile order), so a mirror can never take what a screen's own
    /// output needs. Disabled profiles, and their mirrors, are left out.
    public static func plan(profiles: [ScreenProfile], availableDisplays: [UInt32], operatorDisplay: UInt32?,
                            sdiDevices: [SDIDeviceStatus]) -> OutputPlan {
        var result = OutputPlan()
        let enabled = profiles.filter(\.isEnabled)

        struct Entry {
            var slot: OutputSlot
            var destination: OutputDestination
            var mode: VideoModeDescription
            var synthetic = UUID()
        }
        var entries: [Entry] = enabled.map { Entry(slot: OutputSlot(screenID: $0.id), destination: $0.destination, mode: $0.videoMode) }
        for profile in enabled {
            for (i, mirror) in profile.mirrors.enumerated() {
                entries.append(Entry(slot: OutputSlot(screenID: profile.id, mirror: i), destination: mirror, mode: profile.videoMode))
            }
        }
        result.slots = entries.map(\.slot)
        let slotOf = Dictionary(entries.map { ($0.synthetic, $0.slot) }, uniquingKeysWith: { first, _ in first })

        // Displays and windows: the existing router, one synthetic profile per slot.
        let synthetic = entries.map { ScreenProfile(id: $0.synthetic, name: "", role: .audience, destination: $0.destination) }
        let routing = OutputRouter.plan(profiles: synthetic, availableDisplays: availableDisplays, operatorDisplay: operatorDisplay)
        for entry in entries {
            if let assigned = routing.assignments[entry.synthetic] {
                switch assigned {
                case .display(let id): result.assignments[entry.slot] = .display(id)
                case .window: result.assignments[entry.slot] = .window
                case .sdi: break
                }
            } else if let fault = routing.faults[entry.synthetic] {
                if case .displayInUse(let owner) = fault, let ownerSlot = slotOf[owner] {
                    result.faults[entry.slot] = .routing(.displayInUse(by: ownerSlot.screenID))
                } else {
                    result.faults[entry.slot] = .routing(fault)
                }
            }
        }

        // SDI: per device, the engine's connector planner.
        let devices = Dictionary(sdiDevices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var requests: [String: [SDIOutputRequest]] = [:]
        var requested: [UUID: (entry: Entry, deviceID: String, mode: SDIVideoMode, alpha: AlphaMode)] = [:]
        for entry in entries {
            guard case .sdi(let deviceID, let connector, let keying, let alphaMode) = entry.destination else { continue }
            guard let device = devices[deviceID], device.isConnected else { result.faults[entry.slot] = .sdiDeviceMissing; continue }
            let mode = SDIVideoMode(entry.mode)
            guard device.supportedModes.contains(mode) else { result.faults[entry.slot] = .sdiModeUnsupported(mode.name); continue }
            requests[deviceID, default: []].append(SDIOutputRequest(screenID: entry.synthetic, connector: connector, keying: keying))
            requested[entry.synthetic] = (entry, deviceID, mode, AlphaMode(alphaMode))
        }
        var plans: [String: SDIConnectorPlan] = [:]
        for (deviceID, list) in requests {
            guard let device = devices[deviceID] else { continue }
            let connectorPlan = SDIConnectorPlanner.plan(requests: list, connectorCount: device.info.connectorCount,
                                                         supportsExternalKeying: device.info.supportsExternalKeying,
                                                         keyRoutes: device.info.keyRoutes)
            plans[deviceID] = connectorPlan
            for request in list {
                guard let info = requested[request.screenID] else { continue }
                if let assignment = connectorPlan.assignments[request.screenID] {
                    result.assignments[info.entry.slot] = .sdi(PlannedSDIOutput(deviceID: deviceID, connector: assignment.connector,
                                                                                 keyConnector: assignment.keyConnector,
                                                                                 fillAlphaMode: info.alpha, mode: info.mode,
                                                                                 fillConnector: assignment.fillConnector))
                } else if let fault = connectorPlan.faults[request.screenID] {
                    result.faults[info.entry.slot] = .sdiConnector(fault)
                }
            }
        }
        for device in sdiDevices {
            var uses: [ConnectorUse] = []
            for connector in 1...max(1, device.info.connectorCount) where connector <= device.info.connectorCount {
                switch plans[device.id]?.role(of: connector) ?? .unused {
                case .unused: uses.append(.unused)
                case .output(let id): uses.append(slotOf[id].map(ConnectorUse.output) ?? .unused)
                case .fill(let id): uses.append(slotOf[id].map(ConnectorUse.fill) ?? .unused)
                case .key(let id): uses.append(slotOf[id].map(ConnectorUse.key) ?? .unused)
                }
            }
            result.connectorMaps[device.id] = SDIConnectorMap(deviceID: device.id, uses: uses)
        }
        return result
    }
}
