// CUE-001: a minimal JSON value, so an action this version does not understand can be kept and written back unchanged.
import Foundation

public enum CueJSON: Sendable, Equatable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([CueJSON])
    case object([String: CueJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([CueJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: CueJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var objectValue: [String: CueJSON]? { if case .object(let o) = self { return o } else { return nil } }
    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var boolValue: Bool? { if case .bool(let b) = self { return b } else { return nil } }
    var numberValue: Double? { if case .number(let n) = self { return n } else { return nil } }

    /// A whole, non-negative number that fits an Int.
    var countValue: Int? {
        guard case .number(let n) = self, n.isFinite, n >= 0, n == n.rounded(), n < 9_007_199_254_740_992 else { return nil }
        return Int(n)
    }

    var uuidValue: UUID? { stringValue.flatMap { UUID(uuidString: $0) } }
}

/// CUE-002a: the format version of a stored cue document.
public enum CueStorage {
    /// The top-level `version` of a stored JSON document; nil when the text is not an object or has no integer version.
    public static func version(in data: Data) -> Int? {
        struct Probe: Decodable { var version: Int? }
        return (try? JSONDecoder().decode(Probe.self, from: data))?.version
    }
}
