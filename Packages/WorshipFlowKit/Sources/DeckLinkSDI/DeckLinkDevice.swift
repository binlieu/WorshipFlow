// HW-003 / SCRN-11: one DeckLink card as an SDIDevice.
//
// A card is a group of DeckLink sub-devices (one IDeckLink each). The physical SDI connectors are numbered from 1, as
// SDIConnectorPlanner expects; `DeckLinkConnectorLayout` says which sub-device drives which connector in the card's
// current profile. Status: Implemented, Not Verified. It has never run against a card.
import DeckLinkC
import Foundation
import SDIEngine
import Synchronization

public struct DeckLinkProfileInfo: Equatable, Sendable {
    public var id: UInt32
    public var name: String
    public var isActive: Bool
    public var supportsExternalKeying: Bool
    public var supportsInternalKeying: Bool
    public var supportsPlayback: Bool
    public var supportsCapture: Bool
    /// BMDDuplexMode text ("dxfu", "dxha", "dxsp", "dxin") or "unknown".
    public var duplex: String
    public var subDeviceCount: Int?
}

/// What the SDK says about one sub-device, as plain values.
public struct DeckLinkSubDeviceInfo: Equatable, Sendable {
    public var identifier: DeckLinkIdentifier
    public var modelName: String
    public var displayName: String
    public var subDeviceIndex: Int
    public var supportsPlayback: Bool
    public var supportsCapture: Bool
    public var supportsInternalKeying: Bool
    public var supportsExternalKeying: Bool
    public var supportsInputFormatDetection: Bool
    public var duplex: String
    public var activeProfile: UInt32?
    public var hasSingleProfile: Bool
    public var profiles: [DeckLinkProfileInfo]
}

public final class DeckLinkDevice: SDIDevice {
    public typealias Port = DeckLinkOutputPort
    public typealias InputPort = DeckLinkInputPort

    public let identifier: DeckLinkIdentifier

    struct State {
        var members: [DLBDevice] = []
        /// Bumped each time a member leaves, so ports opened before it are recognised as stale.
        var generation = 0
        /// Physical connectors held by an open output port or input port, by port.
        var outputs: [Int: ObjectIdentifier] = [:]
        var inputs: [Int: ObjectIdentifier] = [:]
        /// The second connector of a fill-and-key pair, claimed by the port on the first.
        var keyClaims: [Int: Int] = [:]
    }

    let state = Mutex(State())

    init(identifier: DeckLinkIdentifier, members: [DLBDevice]) {
        self.identifier = identifier
        state.withLock { $0.members = members }
        sortMembers()
    }

    // MARK: SDIDevice

    public var info: SDIDeviceInfo {
        let members = currentMembers()
        let name = members.first?.info.modelName ?? "DeckLink"
        // The card can key if any of its profiles can; whether the current profile can is checked when a port is enabled.
        let keying = members.contains { $0.info.supportsExternalKeying || $0.info.profiles.contains { $0.supportsExternalKeying } }
        return SDIDeviceInfo(displayName: name, connectorCount: layout.connectorCount, supportsExternalKeying: keying, isSimulated: false)
    }

    public var isConnected: Bool { currentMembers().contains { $0.isPresent } }

    public func openOutput(connector: Int) throws -> DeckLinkOutputPort {
        guard isConnected else { throw SDIError.deviceDisconnected }
        guard layout.entry(connector: connector) != nil else { throw SDIError.connectorUnavailable(connector) }
        let port = DeckLinkOutputPort(device: self, connector: connector, generation: state.withLock { $0.generation })
        try claimOutput(connector: connector, port: ObjectIdentifier(port))
        return port
    }

    // MARK: Input

    /// Opens a capture port on a physical connector.
    public func openInput(connector: Int) throws -> DeckLinkInputPort {
        guard isConnected else { throw SDIError.deviceDisconnected }
        guard layout.entry(connector: connector) != nil else { throw SDIError.connectorUnavailable(connector) }
        let port = DeckLinkInputPort(device: self, connector: connector, generation: state.withLock { $0.generation })
        try claimInput(connector: connector, port: ObjectIdentifier(port))
        return port
    }

    // MARK: Data

    /// The connector layout under the cards' current profiles.
    public var layout: DeckLinkConnectorLayout {
        let members = currentMembers()
        var pairProfiles: [UInt32?] = [nil, nil]
        for member in members {
            let i = member.info
            let index = Int(i.subDeviceIndex)
            if (0...1).contains(index), i.hasActiveProfile { pairProfiles[index] = i.activeProfileID }
        }
        return DeckLinkConnectorLayout.make(modelName: members.first?.info.modelName ?? "", pairProfiles: pairProfiles, subDeviceCount: members.count)
    }

    public var subDevices: [DeckLinkSubDeviceInfo] {
        currentMembers().map { member in
            let i = member.info
            return DeckLinkSubDeviceInfo(
                identifier: i.hasPersistentID ? .device(i.persistentID) : .named(i.displayName),
                modelName: i.modelName, displayName: i.displayName, subDeviceIndex: Int(i.subDeviceIndex),
                supportsPlayback: i.supportsPlayback, supportsCapture: i.supportsCapture,
                supportsInternalKeying: i.supportsInternalKeying, supportsExternalKeying: i.supportsExternalKeying,
                supportsInputFormatDetection: i.supportsInputFormatDetection, duplex: i.duplexModeString,
                activeProfile: i.hasActiveProfile ? i.activeProfileID : nil, hasSingleProfile: i.hasSingleProfile,
                profiles: i.profiles.map {
                    DeckLinkProfileInfo(id: $0.profileID, name: DeckLinkProfile.name($0.profileID), isActive: $0.isActive,
                                        supportsExternalKeying: $0.supportsExternalKeying, supportsInternalKeying: $0.supportsInternalKeying,
                                        supportsPlayback: $0.supportsPlayback, supportsCapture: $0.supportsCapture,
                                        duplex: $0.duplexModeString, subDeviceCount: $0.numberOfSubDevices >= 0 ? Int($0.numberOfSubDevices) : nil)
                })
        }
    }

    /// A profile the card offers that supports the external keyer, if any, for telling the operator what to switch to.
    public var profileSupportingExternalKeying: DeckLinkProfileInfo? {
        for sub in subDevices { if let p = sub.profiles.first(where: { $0.supportsExternalKeying }) { return p } }
        return nil
    }

    /// Everything the bridge and this adapter know, as plain values.
    public func statusSnapshot() -> DeckLinkSnapshotValue {
        let members = currentMembers()
        let state = self.state.withLock { (generation: $0.generation, outputs: $0.outputs.keys.sorted(), inputs: $0.inputs.keys.sorted(), claims: $0.keyClaims) }
        return .object([
            "identifier": .string(identifier.description),
            "connected": .bool(isConnected),
            "generation": .int(Int64(state.generation)),
            "openOutputConnectors": .array(state.outputs.map { .int(Int64($0)) }),
            "openInputConnectors": .array(state.inputs.map { .int(Int64($0)) }),
            "keyClaims": .object(Dictionary(uniqueKeysWithValues: state.claims.map { (String($0.key), .int(Int64($0.value))) })),
            "layout": layout.snapshot,
            "subDevices": .array(members.map { DeckLinkSnapshotValue(foundation: $0.statusSnapshot()) }),
        ])
    }

    // MARK: Profiles

    /// Switches the profile of one connector pair (0 for connectors 1 and 2, 1 for 3 and 4 on a Duo 2) and waits for
    /// the SDK to report it active. The SDK applies it to every sub-device that shares the pair, so ports open on the
    /// pair must be closed first; this refuses instead of stopping them.
    public func activateProfile(_ profile: UInt32, forPair pair: Int, timeout: TimeInterval = 5) async throws {
        let connectors = [2 * pair + 1, 2 * pair + 2]
        let busy = state.withLock { s in connectors.filter { s.outputs[$0] != nil || s.inputs[$0] != nil } }
        guard busy.isEmpty else {
            throw DeckLinkError.profileChangeFailed("Close the outputs and inputs on connectors \(connectors.map(String.init).joined(separator: " and ")) first.")
        }
        guard let member = member(subDeviceIndex: pair) ?? currentMembers().first else { throw DeckLinkError.profileUnavailable("No sub-device for that connector pair.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try member.activateProfile(profile, timeout: timeout)
                    continuation.resume()
                } catch {
                    let nsError = error as NSError
                    let detail = DeckLinkMapping.detail(error)
                    if nsError.domain == DLBErrorDomain, nsError.code == DLBError.Code.notSupported.rawValue {
                        continuation.resume(throwing: DeckLinkError.profileUnavailable(detail))
                    } else {
                        continuation.resume(throwing: DeckLinkError.profileChangeFailed(detail))
                    }
                }
            }
        }
        refreshAll()
    }

    /// Re-reads every sub-device (after a profile change, or by another application).
    public func refreshAll() {
        for member in currentMembers() { _ = member.refreshInfo() }
    }

    // MARK: Membership (used by the provider)

    func currentMembers() -> [DLBDevice] { state.withLock { $0.members } }

    func sortMembers() {
        state.withLock { s in s.members.sort { $0.info.subDeviceIndex < $1.info.subDeviceIndex } }
    }

    func addMember(_ device: DLBDevice) {
        state.withLock { $0.members.append(device) }
        sortMembers()
    }

    /// Removes members that satisfy `shouldRemove`; returns how many were removed and how many remain.
    func removeMembers(where shouldRemove: (DLBDevice) -> Bool) -> (removed: [DLBDevice], remaining: Int) {
        state.withLock { s in
            let gone = s.members.filter(shouldRemove)
            if !gone.isEmpty {
                s.members.removeAll(where: shouldRemove)
                s.generation += 1
                s.outputs.removeAll()
                s.inputs.removeAll()
                s.keyClaims.removeAll()
            }
            return (gone, s.members.count)
        }
    }

    func member(subDeviceIndex: Int) -> DLBDevice? {
        currentMembers().first { Int($0.info.subDeviceIndex) == subDeviceIndex }
    }

    var generation: Int { state.withLock { $0.generation } }

    // MARK: Port bookkeeping (used by the ports)

    private func claimOutput(connector: Int, port: ObjectIdentifier) throws {
        try state.withLock { s in
            guard s.outputs[connector] == nil, s.inputs[connector] == nil, s.keyClaims[connector] == nil else { throw SDIError.connectorUnavailable(connector) }
            s.outputs[connector] = port
        }
    }

    private func claimInput(connector: Int, port: ObjectIdentifier) throws {
        try state.withLock { s in
            guard s.outputs[connector] == nil, s.inputs[connector] == nil, s.keyClaims[connector] == nil else { throw SDIError.connectorUnavailable(connector) }
            s.inputs[connector] = port
        }
    }

    /// Reserves the connector after `first` as the key of a fill-and-key pair.
    func claimKey(first: Int, port: ObjectIdentifier) throws {
        try state.withLock { s in
            let second = first + 1
            guard s.outputs[second] == nil, s.inputs[second] == nil else { throw SDIError.connectorUnavailable(second) }
            if let owner = s.keyClaims[second], owner != first { throw SDIError.connectorUnavailable(second) }
            s.keyClaims[second] = first
        }
    }

    func releaseKey(first: Int) {
        state.withLock { s in s.keyClaims = s.keyClaims.filter { $0.value != first } }
    }

    func release(connector: Int, port: ObjectIdentifier) {
        state.withLock { s in
            if s.outputs[connector] == port { s.outputs[connector] = nil }
            if s.inputs[connector] == port { s.inputs[connector] = nil }
        }
    }

    /// Whether the port that was opened at `generation` is still the current connection of the card.
    func isCurrent(generation opened: Int) -> Bool { generation == opened }

    // MARK: Resolution

    /// The sub-device and, for fill and key, the route that serve an output on `connector`.
    func resolveOutput(connector: Int, keyed: Bool) throws -> (device: DLBDevice, route: DeckLinkKeyRoute?) {
        guard isConnected else { throw SDIError.deviceDisconnected }
        let layout = self.layout
        guard let entry = layout.entry(connector: connector) else { throw SDIError.connectorUnavailable(connector) }
        if keyed {
            guard connector % 2 == 1, let route = layout.keyRoute(firstConnector: connector),
                  let device = member(subDeviceIndex: route.subDeviceIndex),
                  device.info.supportsExternalKeying, device.info.hasKeyerInterface else {
                throw SDIError.keyingUnavailable(connector: connector)
            }
            return (device, route)
        }
        guard entry.role.canOutput, let device = member(subDeviceIndex: entry.subDeviceIndex), device.info.hasOutputInterface else {
            throw SDIError.connectorUnavailable(connector)
        }
        return (device, nil)
    }

    /// The sub-device that serves a capture on `connector`.
    func resolveInput(connector: Int) throws -> DLBDevice {
        guard isConnected else { throw SDIError.deviceDisconnected }
        guard let entry = layout.entry(connector: connector), entry.role.canInput,
              let device = member(subDeviceIndex: entry.subDeviceIndex), device.info.hasInputInterface else {
            throw SDIError.connectorUnavailable(connector)
        }
        return device
    }
}
