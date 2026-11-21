// HW-003 / SCRN-10 / SCRN-11: which physical SDI connector belongs to which DeckLink sub-device under which profile.
//
// The SDK does not expose this mapping as an attribute. For the DeckLink Duo 2 it is documented in a table in the
// SDK manual (section 2.4.11, "Device Profiles"); this file encodes that table. NOTHING HERE IS HARDWARE VERIFIED.
// For any other model the layout falls back to "connector n is sub-device n-1", and says so in `source`.
import Foundation

/// The profile identifiers (BMDProfileID) this module knows by name.
public enum DeckLinkProfile {
    public static let oneSubDeviceFullDuplex = DeckLinkModeMapping.fourCC("1dfd")
    public static let oneSubDeviceHalfDuplex = DeckLinkModeMapping.fourCC("1dhd")
    public static let twoSubDevicesFullDuplex = DeckLinkModeMapping.fourCC("2dfd")
    public static let twoSubDevicesHalfDuplex = DeckLinkModeMapping.fourCC("2dhd")
    public static let fourSubDevicesHalfDuplex = DeckLinkModeMapping.fourCC("4dhd")

    /// Plain language for the operator and the logs.
    public static func name(_ id: UInt32) -> String {
        switch id {
        case oneSubDeviceFullDuplex: return "one sub-device, full duplex"
        case oneSubDeviceHalfDuplex: return "one sub-device, half duplex"
        case twoSubDevicesFullDuplex: return "two sub-devices, full duplex"
        case twoSubDevicesHalfDuplex: return "two sub-devices, half duplex"
        case fourSubDevicesHalfDuplex: return "four sub-devices, half duplex"
        default: return DeckLinkModeMapping.text(forFourCC: id)
        }
    }
}

/// How a pair of connectors would carry fill and key, as the layout understands it. Data, not a decision: the
/// planner in SDIEngine assumes "fill on the first connector, key on the next", and this says what the SDK manual's
/// table implies for the hardware.
public struct DeckLinkKeyRoute: Equatable, Sendable {
    /// The sub-device whose keyer carries the pair.
    public var subDeviceIndex: Int
    /// The physical SDI connector (1-based) carrying the fill picture.
    public var fillConnector: Int
    /// The physical SDI connector (1-based) carrying the key (alpha as grey).
    public var keyConnector: Int
    /// True when this comes from the manual's table, false when it is only the planner's convention assumed for a
    /// model the table does not cover.
    public var fromDocumentation: Bool

    public init(subDeviceIndex: Int, fillConnector: Int, keyConnector: Int, fromDocumentation: Bool) {
        self.subDeviceIndex = subDeviceIndex
        self.fillConnector = fillConnector
        self.keyConnector = keyConnector
        self.fromDocumentation = fromDocumentation
    }
}

public struct DeckLinkConnectorLayout: Equatable, Sendable {
    public enum Role: String, Equatable, Sendable {
        /// Half-duplex: the connector can be an input or an output.
        case inputOrOutput
        /// Full-duplex pair, the lower connector: input, or the key when the keyer is on.
        case inputOrKey
        /// Full-duplex pair, the upper connector: output, or the fill when the keyer is on.
        case outputOrFill

        public var canOutput: Bool { self != .inputOrKey }
        public var canInput: Bool { self != .outputOrFill }
    }

    public struct Entry: Equatable, Sendable {
        /// Physical SDI connector, numbered from 1.
        public var connector: Int
        /// The sub-device that drives it. Its IDeckLinkOutput / IDeckLinkInput is what the bridge opens.
        public var subDeviceIndex: Int
        public var role: Role
        public init(connector: Int, subDeviceIndex: Int, role: Role) {
            self.connector = connector
            self.subDeviceIndex = subDeviceIndex
            self.role = role
        }
    }

    public enum Source: String, Equatable, Sendable {
        /// The Duo 2 table in the SDK manual, section 2.4.11. Not hardware verified.
        case manualTableDuo2
        /// No table for this model: connector n is sub-device n-1. An assumption.
        case subDeviceOrder
    }

    public var entries: [Entry]
    public var source: Source
    /// For the Duo 2: the profile of each connector pair that the layout was built from; nil where unknown.
    public var pairProfiles: [UInt32?]

    public var connectorCount: Int { entries.count }

    public func entry(connector: Int) -> Entry? { entries.first { $0.connector == connector } }

    /// Whether this model is the DeckLink Duo 2, the only model with a documented table here.
    public static func isDuo2(modelName: String) -> Bool {
        modelName.lowercased().contains("duo 2")
    }

    /// Builds the layout. `pairProfiles[p]` is the active profile of connector pair p (connectors 2p+1 and 2p+2); a
    /// nil entry means the profile is unknown, and the half-duplex arrangement is assumed.
    public static func make(modelName: String, pairProfiles: [UInt32?], subDeviceCount: Int) -> DeckLinkConnectorLayout {
        guard isDuo2(modelName: modelName) else {
            let count = max(1, subDeviceCount)
            let entries = (1...count).map { Entry(connector: $0, subDeviceIndex: $0 - 1, role: .inputOrOutput) }
            return DeckLinkConnectorLayout(entries: entries, source: .subDeviceOrder, pairProfiles: pairProfiles)
        }
        var entries: [Entry] = []
        for pair in 0..<2 {
            let profile = pair < pairProfiles.count ? pairProfiles[pair] : nil
            let lower = 2 * pair + 1
            let upper = 2 * pair + 2
            if profile == DeckLinkProfile.oneSubDeviceFullDuplex {
                // SD p carries both: lower connector in/key, upper connector out/fill.
                entries.append(Entry(connector: lower, subDeviceIndex: pair, role: .inputOrKey))
                entries.append(Entry(connector: upper, subDeviceIndex: pair, role: .outputOrFill))
            } else {
                // Two half-duplex sub-devices share the pair: SD p on the lower connector, SD p+2 on the upper one.
                entries.append(Entry(connector: lower, subDeviceIndex: pair, role: .inputOrOutput))
                entries.append(Entry(connector: upper, subDeviceIndex: pair + 2, role: .inputOrOutput))
            }
        }
        return DeckLinkConnectorLayout(entries: entries, source: .manualTableDuo2, pairProfiles: pairProfiles)
    }

    /// The fill-and-key route for the connector pair that starts at `firstConnector` (1 or 3 on a four-connector card),
    /// or nil when this layout has no sub-device that carries both.
    public func keyRoute(firstConnector: Int) -> DeckLinkKeyRoute? {
        guard let lower = entry(connector: firstConnector), let upper = entry(connector: firstConnector + 1) else { return nil }
        switch source {
        case .manualTableDuo2:
            guard lower.role == .inputOrKey, upper.role == .outputOrFill, lower.subDeviceIndex == upper.subDeviceIndex else { return nil }
            return DeckLinkKeyRoute(subDeviceIndex: lower.subDeviceIndex, fillConnector: upper.connector, keyConnector: lower.connector, fromDocumentation: true)
        case .subDeviceOrder:
            return DeckLinkKeyRoute(subDeviceIndex: lower.subDeviceIndex, fillConnector: lower.connector, keyConnector: upper.connector, fromDocumentation: false)
        }
    }

    /// Plain values for the diagnostics snapshot.
    public var snapshot: DeckLinkSnapshotValue {
        .object([
            "source": .string(source.rawValue),
            "connectorCount": .int(Int64(connectorCount)),
            "entries": .array(entries.map {
                .object(["connector": .int(Int64($0.connector)), "subDeviceIndex": .int(Int64($0.subDeviceIndex)), "role": .string($0.role.rawValue)])
            }),
        ])
    }
}
