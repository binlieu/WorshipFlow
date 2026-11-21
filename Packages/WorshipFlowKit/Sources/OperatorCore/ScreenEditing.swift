// HW-002 / OUT-005: the operator's choices for SDI destinations, keying, modes and mirrors, as pure functions on a
// screen profile. The views call these and hand the result to `SettingsModel.updateProfile`. Foundation and Domain only.
import Foundation
import Domain

/// Which connector of a keyable pair carries the fill and which the key, as the device reports it (KI-053).
public struct SDIKeyRouteSummary: Equatable, Sendable {
    public var firstConnector: Int
    public var fillConnector: Int
    public var keyConnector: Int

    public init(firstConnector: Int, fillConnector: Int, keyConnector: Int) {
        self.firstConnector = firstConnector
        self.fillConnector = fillConnector
        self.keyConnector = keyConnector
    }
}

/// What the interface needs to know about one SDI card, in Domain terms (OperatorCore cannot import the SDI engine).
public struct SDIDeviceSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var connectorCount: Int
    public var supportsKeying: Bool
    public var isSimulated: Bool
    public var supportedModes: [VideoModeDescription]
    /// False while the card is unplugged: it is still listed, so screens that use it say why they are not running.
    public var isConnected: Bool
    /// The fill and key route of each keyable pair, as the device reports it. Empty when it reports none.
    public var keyRoutes: [SDIKeyRouteSummary]

    public init(id: String, name: String, connectorCount: Int, supportsKeying: Bool, isSimulated: Bool,
                supportedModes: [VideoModeDescription], isConnected: Bool = true, keyRoutes: [SDIKeyRouteSummary] = []) {
        self.keyRoutes = keyRoutes
        self.isConnected = isConnected
        self.id = id
        self.name = name
        self.connectorCount = connectorCount
        self.supportsKeying = supportsKeying
        self.isSimulated = isSimulated
        self.supportedModes = supportedModes
    }

    /// The reported route of the pair that starts at `firstConnector`, if the device reported one.
    public func keyRoute(firstConnector: Int) -> SDIKeyRouteSummary? { keyRoutes.first { $0.firstConnector == firstConnector } }

    /// The name with "Simulated" in it for anything that is not real hardware, so a simulator is never mistaken for a card.
    public var label: String { isSimulated && !name.localizedCaseInsensitiveContains("simulated") ? "\(name) (Simulated)" : name }
}

public enum ScreenEditing {
    // MARK: Labels

    public static func destinationLabel(_ destination: OutputDestination, devices: [SDIDeviceSummary],
                                        displayName: (UInt32) -> String) -> String {
        switch destination {
        case .window: return "Window"
        case .display(let id): return displayName(id)
        case .sdi(let deviceID, let connector, let keying, _):
            guard let device = devices.first(where: { $0.id == deviceID }) else {
                return "SDI card \(deviceID) (not connected), connector \(connector)"
            }
            if keying {
                if let route = device.keyRoute(firstConnector: connector) {
                    return "\(device.label), connectors \(connector) and \(connector + 1) (fill and key: fill on \(route.fillConnector), key on \(route.keyConnector))"
                }
                return "\(device.label), connectors \(connector) and \(connector + 1) (fill and key)"
            }
            return "\(device.label), connector \(connector)"
        }
    }

    /// Shown next to the keying toggle, when nothing is known about the card's route.
    public static func keyingCaption(connector: Int) -> String { "Uses connectors \(connector) and \(connector + 1)" }

    /// Shown next to the keying toggle: with the card's reported route, which connector carries the fill and which the key.
    public static func keyingCaption(connector: Int, device: SDIDeviceSummary?) -> String {
        guard let route = device?.keyRoute(firstConnector: connector) else { return keyingCaption(connector: connector) }
        return "Uses connectors \(connector) and \(connector + 1): fill on \(route.fillConnector), key on \(route.keyConnector)"
    }

    // MARK: SDI choices

    /// A keyed output starts on the first connector of a pair (1 or 3), so the key can use the next one.
    public static func connectorChoices(device: SDIDeviceSummary, keying: Bool) -> [Int] {
        guard device.connectorCount > 0 else { return [] }
        if keying {
            guard device.supportsKeying else { return [] }
            return (1...device.connectorCount).filter { $0 % 2 == 1 && $0 + 1 <= device.connectorCount }
        }
        return Array(1...device.connectorCount)
    }

    public static func modes(for device: SDIDeviceSummary) -> [VideoModeDescription] { device.supportedModes }

    /// Sends the screen to a connector of a card. An existing keying and alpha choice is kept when the card allows it,
    /// and the mode falls back to one the card supports (the standard mode when it has it) rather than staying invalid.
    public static func choosingSDI(_ profile: ScreenProfile, device: SDIDeviceSummary, connector: Int) -> ScreenProfile {
        var p = profile
        var keying = false
        var alpha = SDIAlphaMode.premultiplied
        if case .sdi(_, _, let wasKeying, let wasAlpha) = profile.destination { keying = wasKeying; alpha = wasAlpha }
        keying = keying && device.supportsKeying
        var chosen = connector
        if keying, chosen % 2 == 0 { chosen -= 1 }
        p.destination = .sdi(deviceID: device.id, connector: chosen, keying: keying, fillAlphaMode: alpha)
        if !device.supportedModes.contains(p.videoMode) {
            if device.supportedModes.contains(.standard) { p.videoMode = .standard }
            else if let first = device.supportedModes.first { p.videoMode = first }
        }
        return p
    }

    public static func settingKeying(_ profile: ScreenProfile, on: Bool, device: SDIDeviceSummary) -> ScreenProfile {
        var p = profile
        p.destination = keying(profile.destination, on: on, device: device)
        return p
    }

    public static func settingAlphaMode(_ profile: ScreenProfile, _ mode: SDIAlphaMode) -> ScreenProfile {
        var p = profile
        p.destination = alpha(profile.destination, mode)
        return p
    }

    // MARK: Mirrors

    /// A new mirror starts as a window: it always exists, so it starts without needing anything to be connected.
    public static func addingMirror(_ profile: ScreenProfile) -> ScreenProfile {
        var p = profile
        p.mirrors.append(.window)
        return p
    }

    public static func removingMirror(_ profile: ScreenProfile, at index: Int) -> ScreenProfile {
        guard profile.mirrors.indices.contains(index) else { return profile }
        var p = profile
        p.mirrors.remove(at: index)
        if p.connectedTo.indices.contains(index + 1) { p.connectedTo.remove(at: index + 1) }     // keep the typed notes aligned
        while p.connectedTo.last == "" { p.connectedTo.removeLast() }
        return p
    }

    public static func settingMirror(_ profile: ScreenProfile, at index: Int, to destination: OutputDestination) -> ScreenProfile {
        guard profile.mirrors.indices.contains(index) else { return profile }
        var p = profile
        p.mirrors[index] = destination
        return p
    }

    public static func settingMirrorKeying(_ profile: ScreenProfile, at index: Int, on: Bool, device: SDIDeviceSummary) -> ScreenProfile {
        guard profile.mirrors.indices.contains(index) else { return profile }
        var p = profile
        p.mirrors[index] = keying(profile.mirrors[index], on: on, device: device)
        return p
    }

    public static func settingMirrorAlphaMode(_ profile: ScreenProfile, at index: Int, _ mode: SDIAlphaMode) -> ScreenProfile {
        guard profile.mirrors.indices.contains(index) else { return profile }
        var p = profile
        p.mirrors[index] = alpha(profile.mirrors[index], mode)
        return p
    }

    // MARK: Internals

    private static func keying(_ destination: OutputDestination, on: Bool, device: SDIDeviceSummary) -> OutputDestination {
        guard case .sdi(let id, let connector, _, let alpha) = destination else { return destination }
        if on {
            guard device.supportsKeying else { return destination }
            let first = connector % 2 == 0 ? connector - 1 : connector
            return .sdi(deviceID: id, connector: first, keying: true, fillAlphaMode: alpha)
        }
        return .sdi(deviceID: id, connector: connector, keying: false, fillAlphaMode: alpha)
    }

    private static func alpha(_ destination: OutputDestination, _ mode: SDIAlphaMode) -> OutputDestination {
        guard case .sdi(let id, let connector, let keying, _) = destination else { return destination }
        return .sdi(deviceID: id, connector: connector, keying: keying, fillAlphaMode: mode)
    }
}
