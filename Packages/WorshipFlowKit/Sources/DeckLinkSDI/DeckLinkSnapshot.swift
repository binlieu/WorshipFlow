// HW-003: the bridge's diagnostics as plain values. A tree the diagnostics screen and the hardware test bundle can
// store and print without touching Foundation containers across threads.
import Foundation

public indirect enum DeckLinkSnapshotValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([DeckLinkSnapshotValue])
    case object([String: DeckLinkSnapshotValue])

    /// Converts what the bridge returns (NSString, NSNumber, NSNull, NSArray, NSDictionary).
    public init(foundation value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.int64Value)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { DeckLinkSnapshotValue(foundation: $0) })
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { DeckLinkSnapshotValue(foundation: $0) })
        default:
            self = .string(String(describing: value))
        }
    }

    public subscript(key: String) -> DeckLinkSnapshotValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    public var intValue: Int64? { if case .int(let i) = self { return i } else { return nil } }
    public var arrayValue: [DeckLinkSnapshotValue]? { if case .array(let a) = self { return a } else { return nil } }

    /// Indented, key-sorted text. Stable, so two snapshots can be compared as text.
    public func rendered(indent: Int = 0) -> String {
        let pad = String(repeating: "  ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return "\"" + s + "\""
        case .array(let a):
            if a.isEmpty { return "[]" }
            return "[\n" + a.map { pad + "  " + $0.rendered(indent: indent + 1) }.joined(separator: ",\n") + "\n" + pad + "]"
        case .object(let o):
            if o.isEmpty { return "{}" }
            return "{\n" + o.keys.sorted().map { pad + "  \"" + $0 + "\": " + (o[$0]?.rendered(indent: indent + 1) ?? "null") }.joined(separator: ",\n") + "\n" + pad + "}"
        }
    }
}
