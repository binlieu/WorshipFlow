// OUT-002: screen profiles and routing. A screen faults on its own; it is never moved to another display.
import Foundation

/// How the colour of a keyed SDI output relates to its alpha. Domain's own copy so Domain never imports the SDI engine.
public enum SDIAlphaMode: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    /// Colour is already multiplied by alpha (what the compositor produces).
    case premultiplied
    /// Colour is divided by alpha before it is sent as fill.
    case straight
}

/// A video mode for an SDI destination, described without any vendor or engine type (HW-09: 59.94 and 60 are different).
public struct VideoModeDescription: Sendable, Equatable, Codable, Hashable {
    public let width: Int
    public let height: Int
    /// Frame duration in `timeScale` units.
    public let frameDurationValue: Int64
    public let timeScale: Int64
    public let isInterlaced: Bool
    public let name: String

    public init(width: Int, height: Int, frameDurationValue: Int64, timeScale: Int64, isInterlaced: Bool = false, name: String) {
        self.width = width
        self.height = height
        self.frameDurationValue = frameDurationValue
        self.timeScale = timeScale
        self.isInterlaced = isInterlaced
        self.name = name
    }

    public static let hd1080p5994 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 60000, name: "1080p59.94")
    public static let hd1080p60 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 60000, name: "1080p60")
    public static let hd1080p50 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 50000, name: "1080p50")
    public static let hd1080p2997 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 30000, name: "1080p29.97")
    public static let hd1080p30 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 30000, name: "1080p30")
    public static let hd1080p25 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1000, timeScale: 25000, name: "1080p25")
    public static let hd1080i5994 = VideoModeDescription(width: 1920, height: 1080, frameDurationValue: 1001, timeScale: 30000, isInterlaced: true, name: "1080i59.94")
    public static let hd720p5994 = VideoModeDescription(width: 1280, height: 720, frameDurationValue: 1001, timeScale: 60000, name: "720p59.94")
    public static let hd720p60 = VideoModeDescription(width: 1280, height: 720, frameDurationValue: 1000, timeScale: 60000, name: "720p60")
    public static let hd720p50 = VideoModeDescription(width: 1280, height: 720, frameDurationValue: 1000, timeScale: 50000, name: "720p50")

    public static let allKnown: [VideoModeDescription] = [
        .hd1080p5994, .hd1080p60, .hd1080p50, .hd1080p2997, .hd1080p30, .hd1080p25, .hd1080i5994, .hd720p5994, .hd720p60, .hd720p50,
    ]

    /// What a new screen starts with.
    public static let standard = VideoModeDescription.hd1080p5994
}

public enum OutputDestination: Sendable, Equatable, Codable, Hashable {
    /// A full-screen output on the display with this CGDirectDisplayID.
    case display(UInt32)
    case window
    /// An SDI connector of a card (HW-002). Connectors are numbered from 1. With `keying` the screen takes `connector`
    /// for fill and `connector + 1` for key.
    case sdi(deviceID: String, connector: Int, keying: Bool, fillAlphaMode: SDIAlphaMode)

    public var isSDI: Bool { if case .sdi = self { return true } else { return false } }

    /// True for an SDI destination that sends a fill and key pair.
    public var isKeyed: Bool { if case .sdi(_, _, let keying, _) = self { return keying } else { return false } }
}

/// SYS-015: one box in the operator's own description of what a signal passes through on the way to a screen ("typed by you": the app cannot know
/// what is plugged in).
public struct ChainNode: Sendable, Equatable, Codable, Hashable {
    public enum Kind: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
        case enclosure, converter, other
    }
    public static let maxLabelLength = 120

    public var kind: Kind
    public var label: String

    public init(kind: Kind, label: String) {
        self.kind = kind
        self.label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxLabelLength))
    }

    private enum CodingKeys: String, CodingKey { case kind, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: (try? c.decode(Kind.self, forKey: .kind)) ?? .other, label: try c.decodeIfPresent(String.self, forKey: .label) ?? "")
    }
}

public struct ScreenProfile: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var role: ScreenRole
    public var destination: OutputDestination
    public var isEnabled: Bool
    /// Extra destinations that show the same scene as `destination` (OUT-005). Each is routed and faulted on its own;
    /// a missing mirror never stops the primary. Absent in profiles stored before mirrors existed.
    public var mirrors: [OutputDestination]
    /// The mode SDI destinations (primary and mirrors) run in. Ignored by displays and windows.
    public var videoMode: VideoModeDescription
    /// UI-002: what the operator typed about where each destination goes ("ATEM input 5"). Index 0 is the primary
    /// destination, index n + 1 is mirror n. Free text, never read by the engine; the app cannot know what is plugged in.
    public var connectedTo: [String]
    /// SYS-015: what the operator typed about where the KEY of each keyed SDI destination goes, indexed like `connectedTo` (a Fill and Key
    /// destination uses two connectors, so the fill's note and the key's note are separate). Free text, never read by the engine.
    public var connectedToKey: [String]
    /// SYS-015: per destination (indexed like `connectedTo`), the boxes the operator says the signal passes through (enclosure, converter, other).
    public var signalChains: [[ChainNode]]
    /// SYS-015: the Look this screen follows on its own, if the operator chose one. Nil: the show's current Look. Stored only; nothing reads it yet.
    public var screenLookID: UUID?

    /// SYS-015: the most boxes a chain keeps.
    public static let maxChainLength = 12

    public init(id: UUID = UUID(), name: String, role: ScreenRole, destination: OutputDestination, isEnabled: Bool = true,
                mirrors: [OutputDestination] = [], videoMode: VideoModeDescription = .standard, connectedTo: [String] = [],
                connectedToKey: [String] = [], signalChains: [[ChainNode]] = [], screenLookID: UUID? = nil) {
        self.connectedToKey = connectedToKey
        self.signalChains = signalChains
        self.screenLookID = screenLookID
        self.connectedTo = connectedTo
        self.id = id
        self.name = name
        self.role = role
        self.destination = destination
        self.isEnabled = isEnabled
        self.mirrors = mirrors
        self.videoMode = videoMode
    }

    private enum CodingKeys: String, CodingKey { case id, name, role, destination, isEnabled, mirrors, videoMode, connectedTo, connectedToKey, signalChains, screenLookID }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  role: try c.decode(ScreenRole.self, forKey: .role),
                  destination: try c.decode(OutputDestination.self, forKey: .destination),
                  isEnabled: try c.decode(Bool.self, forKey: .isEnabled),
                  mirrors: try c.decodeIfPresent([OutputDestination].self, forKey: .mirrors) ?? [],
                  videoMode: try c.decodeIfPresent(VideoModeDescription.self, forKey: .videoMode) ?? .standard,
                  connectedTo: try c.decodeIfPresent([String].self, forKey: .connectedTo) ?? [],
                  connectedToKey: try c.decodeIfPresent([String].self, forKey: .connectedToKey) ?? [],
                  signalChains: try c.decodeIfPresent([[ChainNode]].self, forKey: .signalChains) ?? [],
                  screenLookID: try c.decodeIfPresent(UUID.self, forKey: .screenLookID))
    }

    /// A value at its default writes no key.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(role, forKey: .role)
        try c.encode(destination, forKey: .destination)
        try c.encode(isEnabled, forKey: .isEnabled)
        try c.encode(mirrors, forKey: .mirrors)
        try c.encode(videoMode, forKey: .videoMode)
        try c.encode(connectedTo, forKey: .connectedTo)
        if !connectedToKey.isEmpty { try c.encode(connectedToKey, forKey: .connectedToKey) }
        if !signalChains.isEmpty { try c.encode(signalChains, forKey: .signalChains) }
        try c.encodeIfPresent(screenLookID, forKey: .screenLookID)
    }

    /// The typed "connected to" note of the primary destination (`mirror == nil`) or of a mirror; nil when empty.
    public func connectedNote(mirror: Int?) -> String? {
        let index = (mirror ?? -1) + 1
        guard connectedTo.indices.contains(index) else { return nil }
        let text = connectedTo[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Sets the note, trimmed. A mirror that does not exist takes no note.
    public mutating func setConnectedNote(_ text: String, mirror: Int?) {
        if let mirror, !mirrors.indices.contains(mirror) { return }
        let index = (mirror ?? -1) + 1
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while connectedTo.count <= index { connectedTo.append("") }
        connectedTo[index] = trimmed
        while connectedTo.last == "" { connectedTo.removeLast() }
    }
}

extension ScreenProfile {
    /// SYS-015: the typed note about where the key of the primary destination (`mirror == nil`) or of a mirror goes; nil when empty.
    public func connectedKeyNote(mirror: Int?) -> String? {
        let index = (mirror ?? -1) + 1
        guard connectedToKey.indices.contains(index) else { return nil }
        let text = connectedToKey[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// SYS-015: sets the key note, trimmed and bounded. A mirror that does not exist takes no note.
    public mutating func setConnectedKeyNote(_ text: String, mirror: Int?) {
        if let mirror, !mirrors.indices.contains(mirror) { return }
        let index = (mirror ?? -1) + 1
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ChainNode.maxLabelLength))
        while connectedToKey.count <= index { connectedToKey.append("") }
        connectedToKey[index] = trimmed
        while connectedToKey.last == "" { connectedToKey.removeLast() }
    }

    /// SYS-015: the signal chain the operator typed for the primary destination or a mirror (empty when none).
    public func signalChain(mirror: Int?) -> [ChainNode] {
        let index = (mirror ?? -1) + 1
        return signalChains.indices.contains(index) ? signalChains[index] : []
    }

    /// SYS-015: sets the chain, at most `maxChainLength` boxes. A mirror that does not exist takes none.
    public mutating func setSignalChain(_ chain: [ChainNode], mirror: Int?) {
        if let mirror, !mirrors.indices.contains(mirror) { return }
        let index = (mirror ?? -1) + 1
        while signalChains.count <= index { signalChains.append([]) }
        signalChains[index] = Array(chain.prefix(Self.maxChainLength)).map { ChainNode(kind: $0.kind, label: $0.label) }
        while signalChains.last?.isEmpty == true { signalChains.removeLast() }
    }
}

public enum RoutingFault: Sendable, Equatable, Hashable {
    case displayMissing
    case displayInUse(by: UUID)
    case operatorDisplay

    /// Text for the operator window. Says what happened and what to do.
    public var operatorMessage: String {
        switch self {
        case .displayMissing:
            return "The display for this screen is not connected. Reconnect it, or choose another display or a window."
        case .displayInUse:
            return "Another screen already uses this display. Give each screen its own display, or use a window."
        case .operatorDisplay:
            return "This is the display the operator window is on. Choose another display or a window so the output does not cover the controls."
        }
    }
}

public struct RoutingPlan: Sendable, Equatable {
    public var assignments: [UUID: OutputDestination]
    public var faults: [UUID: RoutingFault]

    public init(assignments: [UUID: OutputDestination] = [:], faults: [UUID: RoutingFault] = [:]) {
        self.assignments = assignments
        self.faults = faults
    }
}

public enum OutputRouter {
    /// Disabled profiles appear in neither list. The first profile in order keeps a contested display.
    public static func plan(profiles: [ScreenProfile], availableDisplays: [UInt32], operatorDisplay: UInt32?) -> RoutingPlan {
        var plan = RoutingPlan()
        var owners: [UInt32: UUID] = [:]
        let available = Set(availableDisplays)
        for profile in profiles where profile.isEnabled {
            switch profile.destination {
            case .sdi:
                continue                      // planned by OutputPlanner, together with the card's connectors
            case .window:
                plan.assignments[profile.id] = .window
            case .display(let id):
                if id == operatorDisplay {
                    plan.faults[profile.id] = .operatorDisplay
                } else if !available.contains(id) {
                    plan.faults[profile.id] = .displayMissing
                } else if let owner = owners[id] {
                    plan.faults[profile.id] = .displayInUse(by: owner)
                } else {
                    owners[id] = profile.id
                    plan.assignments[profile.id] = .display(id)
                }
            }
        }
        return plan
    }
}
