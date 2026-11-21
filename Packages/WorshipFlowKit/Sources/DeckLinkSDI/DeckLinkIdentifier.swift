// HW-003 / SCRN-11: stable names for DeckLink hardware, so a saved screen assignment can find its card again.
import Foundation

/// Identifies a card or one of its sub-devices. The SDK's persistent ID stays the same across restarts and re-plugs;
/// the device group ID is shared by every sub-device of one card.
public enum DeckLinkIdentifier: Hashable, Sendable, CustomStringConvertible {
    /// A whole card: all sub-devices that report the same device group ID.
    case group(Int64)
    /// One sub-device or a card with no group: its persistent ID.
    case device(Int64)
    /// The SDK reported neither; the display name is all there is. Not stable across profiles.
    case named(String)

    private static let groupPrefix = "decklink:group:"
    private static let devicePrefix = "decklink:device:"
    private static let namedPrefix = "decklink:name:"

    /// `decklink:group:<16 hex digits>`, `decklink:device:<16 hex digits>` or `decklink:name:<text>`.
    public var description: String {
        switch self {
        case .group(let id): return Self.groupPrefix + Self.hex(id)
        case .device(let id): return Self.devicePrefix + Self.hex(id)
        case .named(let name): return Self.namedPrefix + name
        }
    }

    /// Reads what `description` wrote. Hex is case-insensitive, may be 1 to 16 digits and may start with `0x`; the
    /// 64 bits are the bit pattern of the signed ID. Anything else returns nil.
    public init?(_ text: String) {
        if text.hasPrefix(Self.groupPrefix), let id = Self.parseHex(String(text.dropFirst(Self.groupPrefix.count))) {
            self = .group(id)
        } else if text.hasPrefix(Self.devicePrefix), let id = Self.parseHex(String(text.dropFirst(Self.devicePrefix.count))) {
            self = .device(id)
        } else if text.hasPrefix(Self.namedPrefix), text.count > Self.namedPrefix.count {
            self = .named(String(text.dropFirst(Self.namedPrefix.count)))
        } else {
            return nil
        }
    }

    static func hex(_ id: Int64) -> String {
        let digits = String(UInt64(bitPattern: id), radix: 16)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }

    static func parseHex(_ text: String) -> Int64? {
        var body = Substring(text)
        if body.hasPrefix("0x") || body.hasPrefix("0X") { body = body.dropFirst(2) }
        guard (1...16).contains(body.count), body.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { return nil }
        guard let value = UInt64(body, radix: 16) else { return nil }
        return Int64(bitPattern: value)
    }
}
