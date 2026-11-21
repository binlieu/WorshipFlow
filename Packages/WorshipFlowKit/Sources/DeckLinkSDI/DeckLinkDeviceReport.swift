// HW-004 / KI-053, KI-054, KI-056: what the adapter tells the engine about a DeckLink card, as pure functions of the
// layout, the profile list and the driver state, so the wording and the decisions are unit tested without a card.
// NOTHING HERE IS HARDWARE VERIFIED: the route comes from the manual's table (the SDK has no attribute that says it).
import Foundation
import SDIEngine

enum DeckLinkDeviceReport {
    /// The fill and key connectors of each pair that can key. For the Duo 2 they are the manual's table for the one
    /// sub-device full-duplex profile (fill on the second connector, key on the first), reported whatever profile is in
    /// force now, because the route is a property of the keying arrangement and the profile state says whether it is on.
    /// For other models the old convention, marked as assumed.
    static func keyRoutes(layout: DeckLinkConnectorLayout, connectorCount: Int) -> [SDIKeyRoute] {
        var routes: [SDIKeyRoute] = []
        var first = 1
        while first + 1 <= connectorCount {
            switch layout.source {
            case .manualTableDuo2:
                routes.append(SDIKeyRoute(firstConnector: first, fillConnector: first + 1, keyConnector: first, source: .manualTable))
            case .subDeviceOrder:
                routes.append(.convention(firstConnector: first, source: .assumed))
            }
            first += 2
        }
        return routes
    }

    static func connectors(layout: DeckLinkConnectorLayout) -> [SDIConnectorInfo] {
        layout.entries.map { entry in
            let role: SDIKeyRole?
            switch entry.role {
            case .inputOrKey: role = .key
            case .outputOrFill: role = .fill
            case .inputOrOutput: role = nil
            }
            return SDIConnectorInfo(connector: entry.connector, canOutput: entry.role.canOutput, canInput: entry.role.canInput, keyRole: role)
        }
    }

    /// The profile a pair would be switched to for keying: one that supports the external keyer, the one sub-device
    /// full-duplex profile first because that is what the manual's table is written for.
    static func keyingProfile(among profiles: [DeckLinkProfileInfo]) -> DeckLinkProfileInfo? {
        let candidates = profiles.filter { $0.supportsExternalKeying }
        return candidates.first { $0.id == DeckLinkProfile.oneSubDeviceFullDuplex } ?? candidates.first { !$0.isActive } ?? candidates.first
    }

    static func profileState(firstConnector: Int, connectorCount: Int, activeProfile: UInt32?, activeProfileKeys: Bool,
                             profiles: [DeckLinkProfileInfo]) -> SDIProfileState {
        let activeName = activeProfile.map { DeckLinkProfile.name($0) }
        if activeProfileKeys {
            return SDIProfileState(firstConnector: firstConnector, activeName: activeName, keyingAvailableNow: true, keyingChange: nil)
        }
        var change: SDIProfileChange?
        if let target = keyingProfile(among: profiles.filter { $0.id != activeProfile }) {
            change = SDIProfileChange(firstConnector: firstConnector, fromName: activeName, toName: target.name,
                                      interruptedConnectors: Array(1...max(1, connectorCount)))
        }
        return SDIProfileState(firstConnector: firstConnector, activeName: activeName, keyingAvailableNow: false, keyingChange: change)
    }

    /// The state of the world in words the operator can act on. `deviceNames` are the cards found.
    static func environmentStatus(environment: DeckLinkEnvironment, deviceNames: [String]) -> SDIEnvironmentStatus {
        guard environment.driverPresent else {
            if environment.frameworkOnDisk {
                return SDIEnvironmentStatus(
                    state: .driverNotInstalled, driverInstalled: false, apiVersion: nil, frameworkLoadable: false, deviceCount: 0,
                    message: "Blackmagic Desktop Video's files are on this Mac, but WORSHIPFLOW could not load them, so SDI outputs are not available. Restart the Mac and open WORSHIPFLOW again. If this stays, reinstall Blackmagic Desktop Video. Screens on displays and windows still work.")
            }
            return SDIEnvironmentStatus(state: .driverNotInstalled, driverInstalled: false, apiVersion: nil, frameworkLoadable: nil, deviceCount: 0,
                                        message: DeckLinkEnvironment.driverMissingMessage)
        }
        let version = environment.apiVersion.map { "driver API \($0)" } ?? "driver API version unknown"
        guard !deviceNames.isEmpty else {
            return SDIEnvironmentStatus(
                state: .noCardFound, driverInstalled: true, apiVersion: environment.apiVersion, frameworkLoadable: true, deviceCount: 0,
                message: "Blackmagic Desktop Video is installed (\(version)), but no DeckLink card was found. Check the Thunderbolt cable and that the enclosure is switched on, then press Rescan.")
        }
        return SDIEnvironmentStatus(state: .cardFound, driverInstalled: true, apiVersion: environment.apiVersion, frameworkLoadable: true,
                                    deviceCount: deviceNames.count,
                                    message: "DeckLink card found: " + deviceNames.joined(separator: ", ") + " (\(version)).")
    }
}
