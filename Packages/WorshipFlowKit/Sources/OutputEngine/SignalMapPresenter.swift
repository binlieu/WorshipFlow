// UI-002 Part 2: the signal map as data. The view draws what this returns and decides nothing. Everything comes from
// the profiles, what each card reports about itself (`SDIDeviceInfo`: connector order, fill and key route) and the
// connector map the planner made. Names of converters, switchers and projectors are never invented: a label for where
// a destination goes appears only when the operator typed one.
import Foundation
import Domain
import SDIEngine

public struct SignalMapInput: Sendable {
    public var profiles: [ScreenProfile]
    public var devices: [SDIDeviceStatus]
    public var maps: [String: SDIConnectorMap]
    /// The run state of each destination (primary or mirror). A destination with no entry counts as stopped.
    public var states: [OutputSlot: ScreenState]
    public var displayName: @Sendable (UInt32) -> String
    public var hostName: String

    public init(profiles: [ScreenProfile], devices: [SDIDeviceStatus], maps: [String: SDIConnectorMap], states: [OutputSlot: ScreenState],
                displayName: @escaping @Sendable (UInt32) -> String, hostName: String) {
        self.profiles = profiles
        self.devices = devices
        self.maps = maps
        self.states = states
        self.displayName = displayName
        self.hostName = hostName
    }
}

public enum SignalTileKind: Equatable, Sendable { case unused, output, fill, key, display, window }

public struct SignalTile: Equatable, Identifiable, Sendable {
    public var id: String
    public var connector: Int?
    public var title: String
    public var subtitle: String
    public var kind: SignalTileKind
    public var screenID: UUID?
    public var isMirror: Bool
    /// What the operator typed about where this goes; nil when nothing was typed.
    public var connectedTo: String?
    /// The fault in words, or nil.
    public var faultText: String?
    /// Plain word for the run state: Running, Stopped, Hidden, Fault; nil for an unused connector.
    public var stateWord: String?
    public var isSimulated: Bool
}

public struct SignalDeviceBlock: Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isSimulated: Bool
    public var isConnected: Bool
    /// "DeckLink Duo 2 · 4 connectors" or "Not connected".
    public var caption: String
    public var routeLines: [String]
    public var tiles: [SignalTile]
}

public struct SignalMap: Equatable, Sendable {
    public var hostTitle: String
    public var summary: String
    public var isSimulated: Bool
    public var devices: [SignalDeviceBlock]
    public var directPaths: [SignalTile]
}

public enum SignalMapPresenter {
    public static func map(_ input: SignalMapInput) -> SignalMap {
        let enabled = input.profiles.filter(\.isEnabled)
        func state(_ slot: OutputSlot) -> ScreenState { input.states[slot] ?? .stopped }
        func word(_ s: ScreenState) -> String {
            switch s {
            case .stopped: "Stopped"
            case .running: "Running"
            case .hidden: "Hidden"
            case .faulted: "Fault"
            }
        }
        func fault(_ s: ScreenState) -> String? {
            switch s {
            case .faulted(let message): message
            case .hidden: "Hidden: another window is covering this output."
            default: nil
            }
        }
        func who(_ slot: OutputSlot) -> (name: String, note: String?, mirror: Bool)? {
            guard let p = input.profiles.first(where: { $0.id == slot.screenID }) else { return nil }
            return (slot.mirror.map { "\(p.name) (mirror \($0 + 1))" } ?? p.name, p.connectedNote(mirror: slot.mirror), slot.mirror != nil)
        }

        var blocks: [SignalDeviceBlock] = []
        for device in input.devices {
            let uses = input.maps[device.id]?.uses ?? Array(repeating: .unused, count: device.info.connectorCount)
            let order = connectorOrder(device.info)
            func partner(of connector: Int, kind: SignalTileKind) -> Int? {
                for (i, use) in uses.enumerated() {
                    switch (kind, use) {
                    case (.key, .fill) : if case .key(let k) = uses[connector - 1], case .fill(let f) = use, k == f { return i + 1 }
                    case (.fill, .key) : if case .fill(let f) = uses[connector - 1], case .key(let k) = use, k == f { return i + 1 }
                    default: break
                    }
                }
                return nil
            }
            var tiles: [SignalTile] = []
            for connector in order {
                let use = uses.indices.contains(connector - 1) ? uses[connector - 1] : .unused
                let prefix = "SDI \(connector)"
                func tile(_ title: String, _ subtitle: String, _ kind: SignalTileKind, _ slot: OutputSlot?) -> SignalTile {
                    let info = slot.flatMap(who)
                    let s = slot.map(state)
                    return SignalTile(id: "\(device.id)#\(connector)", connector: connector, title: "\(prefix) · \(title)", subtitle: subtitle,
                                      kind: kind, screenID: slot?.screenID, isMirror: info?.mirror ?? false, connectedTo: info?.note,
                                      faultText: s.flatMap(fault), stateWord: s.map(word), isSimulated: device.info.isSimulated)
                }
                switch use {
                case .unused:
                    var t = tile("Unused", "Not used by any screen", .unused, nil)
                    if let role = device.info.connectors.first(where: { $0.connector == connector })?.keyRole {
                        t.subtitle = "Not used · \(role == .fill ? "fill" : "key") position of its pair"
                    }
                    tiles.append(t)
                case .output(let slot):
                    tiles.append(tile("Output", who(slot)?.name ?? "A screen that was removed", .output, slot))
                case .fill(let slot):
                    tiles.append(tile("Fill", who(slot)?.name ?? "A screen that was removed", .fill, slot))
                case .key(let slot):
                    var sub = who(slot)?.name ?? "A screen that was removed"
                    if let f = partner(of: connector, kind: .key) { sub += " · paired with SDI \(f)" }
                    tiles.append(tile("Key", sub, .key, slot))
                }
            }
            if let pairs = Optional(tiles), !pairs.isEmpty {
                // A fill tile also names its key partner, so the pair reads the same from either side.
                for i in tiles.indices where tiles[i].kind == .fill {
                    if let c = tiles[i].connector, let k = partner(of: c, kind: .fill) { tiles[i].subtitle += " · paired with SDI \(k)" }
                }
            }
            blocks.append(SignalDeviceBlock(
                id: device.id, name: device.info.displayName, isSimulated: device.info.isSimulated, isConnected: device.isConnected,
                caption: device.isConnected ? "\(device.info.displayName) · \(device.info.connectorCount) connectors"
                                            : "\(device.info.displayName) · Not connected",
                routeLines: routeLines(for: device.info), tiles: tiles))
        }

        var direct: [SignalTile] = []
        for p in enabled {
            let slots: [(OutputSlot, OutputDestination)] = [(OutputSlot(screenID: p.id), p.destination)]
                + p.mirrors.enumerated().map { (OutputSlot(screenID: p.id, mirror: $0.offset), $0.element) }
            for (slot, destination) in slots {
                let title: String
                let kind: SignalTileKind
                switch destination {
                case .sdi: continue
                case .window: title = "Window"; kind = .window
                case .display(let id): title = input.displayName(id); kind = .display
                }
                let s = state(slot)
                direct.append(SignalTile(id: "\(p.id)#\(slot.mirror.map(String.init) ?? "p")", connector: nil, title: title,
                                         subtitle: who(slot)?.name ?? p.name, kind: kind, screenID: p.id, isMirror: slot.mirror != nil,
                                         connectedTo: p.connectedNote(mirror: slot.mirror), faultText: fault(s), stateWord: word(s), isSimulated: false))
            }
        }

        let running = enabled.filter { input.states[OutputSlot(screenID: $0.id)] == .running }.count
        let summary = enabled.isEmpty ? "No screens are enabled." : "\(running) of \(enabled.count) screens running"
        return SignalMap(hostTitle: input.hostName, summary: summary, isSimulated: blocks.contains { $0.isSimulated },
                         devices: blocks, directPaths: direct)
    }

    /// The connectors in the order the device lists them; 1...count when it lists none or an incomplete set.
    static func connectorOrder(_ info: SDIDeviceInfo) -> [Int] {
        let reported = info.connectors.map(\.connector)
        if Set(reported) == Set(1...max(info.connectorCount, 1)), reported.count == info.connectorCount, info.connectorCount > 0 { return reported }
        return info.connectorCount > 0 ? Array(1...info.connectorCount) : []
    }

    /// One line per keyable pair: where the card puts fill and key, and where that answer came from.
    public static func routeLines(for info: SDIDeviceInfo) -> [String] {
        guard !info.keyRoutes.isEmpty else {
            return info.supportsExternalKeying
                ? ["The card reports no fill and key route; fill is assumed on the first connector of a pair."] : []
        }
        return info.keyRoutes.map { r in
            let low = min(r.fillConnector, r.keyConnector), high = max(r.fillConnector, r.keyConnector)
            let source: String
            switch r.source {
            case .manualTable: source = "from the vendor manual's table, not measured"
            case .simulator: source = "reported by the card's simulator"
            case .assumed: source = "assumed, not reported"
            }
            return "Connectors \(low) and \(high): fill on \(r.fillConnector), key on \(r.keyConnector) (\(source))"
        }
    }
}
