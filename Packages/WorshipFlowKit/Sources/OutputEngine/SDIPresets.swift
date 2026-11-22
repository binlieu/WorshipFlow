// UI-002 Part 2: the two preset buttons of the signal map. A preset only proposes: it lists what would change, and the
// operator applies it. Applying goes through the same profile update as any manual change, so the existing planner and the
// existing question before a card profile change (KI-054) stay in charge.
import Foundation
import Domain
import SDIEngine

public enum SDIPreset: Equatable, Sendable, CaseIterable {
    /// Every screen on the card gets its own connector, no keying.
    case independent
    /// The Broadcast screen takes the first pair as fill and key; the other screens move to the remaining connectors.
    case fillKeyBroadcast

    public var title: String { self == .independent ? "Independent outputs" : "Fill + Key broadcast" }
}

public struct PresetChange: Equatable, Sendable, Identifiable {
    public var screenID: UUID
    public var screenName: String
    public var before: String
    public var after: String
    var destination: OutputDestination
    public var id: UUID { screenID }
}

public struct PresetProposal: Equatable, Sendable {
    public var preset: SDIPreset
    public var isAvailable: Bool
    public var unavailableReason: String?
    public var changes: [PresetChange]
    /// Things the operator should know: a screen that could not be placed, a mirror that will lose its connector.
    public var notes: [String]

    public var summary: String {
        if !isAvailable { return unavailableReason ?? "Not available." }
        return changes.isEmpty ? "Already set up this way." : "\(changes.count) screen\(changes.count == 1 ? "" : "s") would change."
    }

    /// The profiles after the proposal. Profiles it does not touch are returned as they are.
    public func applied(to profiles: [ScreenProfile]) -> [ScreenProfile] {
        profiles.map { p in
            guard let change = changes.first(where: { $0.screenID == p.id }) else { return p }
            var q = p
            q.destination = change.destination
            return q
        }
    }
}

public enum SDIPresets {
    public static func proposal(_ preset: SDIPreset, device: SDIDeviceStatus, profiles: [ScreenProfile]) -> PresetProposal {
        func unavailable(_ why: String) -> PresetProposal { PresetProposal(preset: preset, isAvailable: false, unavailableReason: why, changes: [], notes: []) }
        guard device.isConnected else { return unavailable("This card is not connected.") }
        let count = device.info.connectorCount
        func onCard(_ p: ScreenProfile) -> Bool {
            if case .sdi(let id, _, _, _) = p.destination { return id == device.id } else { return false }
        }
        func alpha(_ p: ScreenProfile) -> SDIAlphaMode {
            if case .sdi(_, _, _, let a) = p.destination { return a } else { return .premultiplied }
        }
        let enabled = profiles.filter(\.isEnabled)

        var target: [UUID: OutputDestination] = [:]
        var notes: [String] = []
        var broadcast: ScreenProfile?
        var next = 1
        var others = enabled.filter(onCard)

        switch preset {
        case .independent:
            break
        case .fillKeyBroadcast:
            guard device.info.supportsExternalKeying, count >= 2 else { return unavailable("This card cannot send a fill and key pair.") }
            broadcast = others.first { $0.role == .broadcast } ?? enabled.first { $0.role == .broadcast }
            guard let b = broadcast else { return unavailable("There is no Broadcast screen to send as fill and key. Add one first.") }
            target[b.id] = .sdi(deviceID: device.id, connector: 1, keying: true, fillAlphaMode: alpha(b))
            others.removeAll { $0.id == b.id }
            next = 3
        }
        for p in others {
            if next > count {
                notes.append("\(p.name) has no free connector and was left as it is.")
                continue
            }
            target[p.id] = .sdi(deviceID: device.id, connector: next, keying: false, fillAlphaMode: alpha(p))
            next += 1
        }

        var changes: [PresetChange] = []
        for p in profiles {
            guard let destination = target[p.id], destination != p.destination else { continue }
            changes.append(PresetChange(screenID: p.id, screenName: p.name, before: describe(p.destination, device: device),
                                        after: describe(destination, device: device), destination: destination))
        }
        // Mirrors on this card keep their connectors; the planner gives primaries first, so say which would lose out.
        let finalPrimary: [UUID: OutputDestination] = Dictionary(profiles.map { ($0.id, target[$0.id] ?? $0.destination) }, uniquingKeysWith: { first, _ in first })
        var taken = Set<Int>()
        for p in enabled {
            if case .sdi(let id, let c, let k, _)? = finalPrimary[p.id], id == device.id { taken.insert(c); if k { taken.insert(c + 1) } }
        }
        for p in enabled {
            for (i, m) in p.mirrors.enumerated() {
                if case .sdi(let id, let c, let k, _) = m, id == device.id, taken.contains(c) || (k && taken.contains(c + 1)) {
                    notes.append("Mirror \(i + 1) of \(p.name) uses SDI \(c), which a screen now takes, so it will not start until you move it.")
                } else if case .sdi(let id, let c, let k, _) = m, id == device.id { taken.insert(c); if k { taken.insert(c + 1) } }
            }
        }
        return PresetProposal(preset: preset, isAvailable: true, unavailableReason: nil, changes: changes, notes: notes)
    }

    private static func describe(_ destination: OutputDestination, device: SDIDeviceStatus) -> String {
        switch destination {
        case .window: return "Window"
        case .display: return "Display"
        case .sdi(_, let c, let keying, _):
            guard keying else { return "SDI \(c)" }
            if let route = device.info.keyRoute(firstConnector: c) {
                return "SDI \(c) + \(c + 1) (fill on SDI \(route.fillConnector), key on SDI \(route.keyConnector))"
            }
            return "SDI \(c) + \(c + 1) (fill and key)"
        }
    }
}
