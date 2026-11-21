// HW-002: the connector map as rows of text for the Screens panel, so what each SDI connector carries is never a guess.
import Foundation
import Domain

public struct ConnectorRow: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable { case unused, output, fill, key }
    public var connector: Int
    public var kind: Kind
    public var screenName: String?
    public var text: String
    public var id: Int { connector }
}

public enum ConnectorMapPresenter {
    public static func rows(map: SDIConnectorMap, profiles: [ScreenProfile]) -> [ConnectorRow] {
        map.uses.enumerated().map { index, use in
            let connector = index + 1
            func who(_ slot: OutputSlot) -> String {
                guard let profile = profiles.first(where: { $0.id == slot.screenID }) else { return "a screen that was removed" }
                if let mirror = slot.mirror { return "\(profile.name) (mirror \(mirror + 1))" }
                return profile.name
            }
            func name(_ slot: OutputSlot) -> String? { profiles.first { $0.id == slot.screenID }?.name }
            switch use {
            case .unused:
                return ConnectorRow(connector: connector, kind: .unused, screenName: nil, text: "Connector \(connector): unused")
            case .output(let slot):
                return ConnectorRow(connector: connector, kind: .output, screenName: name(slot), text: "Connector \(connector): output for \(who(slot))")
            case .fill(let slot):
                return ConnectorRow(connector: connector, kind: .fill, screenName: name(slot), text: "Connector \(connector): fill for \(who(slot))")
            case .key(let slot):
                return ConnectorRow(connector: connector, kind: .key, screenName: name(slot), text: "Connector \(connector): key for \(who(slot))")
            }
        }
    }
}
