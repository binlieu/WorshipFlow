// CUE-001 (AUTO-03, AUTO-04): MIDI messages, byte encoding and a forgiving byte parser. Foundation only.
import Foundation

/// A channel voice message the show-control layer understands. Channels are 1 to 16; data values 0 to 127.
/// Out-of-range values are representable (so callers can build one from user input) but report `isValid == false`
/// and never encode to bytes.
public enum MIDIMessage: Sendable, Equatable, Hashable, Codable {
    case noteOn(channel: Int, note: Int, velocity: Int)
    case noteOff(channel: Int, note: Int, velocity: Int)
    case controlChange(channel: Int, controller: Int, value: Int)
    case programChange(channel: Int, program: Int)

    public var channel: Int {
        switch self {
        case .noteOn(let c, _, _), .noteOff(let c, _, _), .controlChange(let c, _, _), .programChange(let c, _): return c
        }
    }

    public var isValid: Bool {
        guard (1...16).contains(channel) else { return false }
        switch self {
        case .noteOn(_, let a, let b), .noteOff(_, let a, let b), .controlChange(_, let a, let b):
            return (0...127).contains(a) && (0...127).contains(b)
        case .programChange(_, let p):
            return (0...127).contains(p)
        }
    }

    /// The status byte (type and channel) and the data bytes. Nil when the message is not valid.
    public var bytes: [UInt8]? {
        guard isValid else { return nil }
        let ch = UInt8(channel - 1)
        switch self {
        case .noteOff(_, let n, let v): return [0x80 | ch, UInt8(n), UInt8(v)]
        case .noteOn(_, let n, let v): return [0x90 | ch, UInt8(n), UInt8(v)]
        case .controlChange(_, let c, let v): return [0xB0 | ch, UInt8(c), UInt8(v)]
        case .programChange(_, let p): return [0xC0 | ch, UInt8(p)]
        }
    }

    /// Encodes a sequence. Invalid messages are skipped. With `runningStatus` a status byte is left out when it equals
    /// the one just sent.
    public static func encode(_ messages: [MIDIMessage], runningStatus: Bool) -> [UInt8] {
        var out: [UInt8] = []
        var last: UInt8?
        for m in messages {
            guard let b = m.bytes else { continue }
            if runningStatus, last == b[0] {
                out.append(contentsOf: b.dropFirst())
            } else {
                out.append(contentsOf: b)
            }
            last = b[0]
        }
        return out
    }
}

/// Turns a stream of raw MIDI bytes into messages. Keeps running status and half-received messages between calls, so it
/// can be fed packet by packet. Anything it does not understand is skipped; it never traps and never yields an invalid
/// message. Unsupported but well-formed messages (aftertouch, pitch bend, system messages) are consumed silently.
public struct MIDIParser: Sendable {
    /// Data bytes that were dropped because they were malformed: stray data with no status, or the data of a message
    /// cut short by a new status byte. Well-formed messages the parser does not care about are not counted.
    public private(set) var ignoredByteCount = 0

    private var status: UInt8?          // running status (0x80...0xEF), nil when none
    private var data: [UInt8] = []      // data bytes of the message in progress
    private var inSystemExclusive = false
    private var skipRemaining = 0       // data bytes still to swallow for a system common message

    public init() {}

    public static func parse(_ bytes: [UInt8]) -> [MIDIMessage] {
        var p = MIDIParser()
        return p.feed(bytes)
    }

    public mutating func reset() {
        status = nil
        data = []
        inSystemExclusive = false
        skipRemaining = 0
    }

    public mutating func feed<S: Sequence>(_ bytes: S) -> [MIDIMessage] where S.Element == UInt8 {
        var out: [MIDIMessage] = []
        for byte in bytes { consume(byte, into: &out) }
        return out
    }

    private static func dataLength(forStatus s: UInt8) -> Int {
        switch s & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }

    private mutating func consume(_ byte: UInt8, into out: inout [MIDIMessage]) {
        if byte >= 0xF8 { return }                       // real-time: may appear anywhere, changes nothing

        if byte >= 0x80 {                                // a status byte
            if !data.isEmpty { ignoredByteCount += data.count; data = [] }   // cut-short message
            inSystemExclusive = false
            skipRemaining = 0
            if byte < 0xF0 {
                status = byte
            } else {
                status = nil                             // system messages cancel running status
                switch byte {
                case 0xF0: inSystemExclusive = true
                case 0xF1, 0xF3: skipRemaining = 1
                case 0xF2: skipRemaining = 2
                default: break                           // 0xF4 0xF5 undefined, 0xF6 tune request, 0xF7 end marker
                }
            }
            return
        }

        // A data byte.
        if inSystemExclusive { return }
        if skipRemaining > 0 { skipRemaining -= 1; return }
        guard let s = status else { ignoredByteCount += 1; return }
        data.append(byte)
        guard data.count == Self.dataLength(forStatus: s) else { return }
        let d = data
        data = []
        if let m = Self.message(status: s, data: d) { out.append(m) }
    }

    private static func message(status s: UInt8, data d: [UInt8]) -> MIDIMessage? {
        let channel = Int(s & 0x0F) + 1
        switch s & 0xF0 {
        case 0x80: return .noteOff(channel: channel, note: Int(d[0]), velocity: Int(d[1]))
        case 0x90:
            return d[1] == 0 ? .noteOff(channel: channel, note: Int(d[0]), velocity: 0)
                             : .noteOn(channel: channel, note: Int(d[0]), velocity: Int(d[1]))
        case 0xB0: return .controlChange(channel: channel, controller: Int(d[0]), value: Int(d[1]))
        case 0xC0: return .programChange(channel: channel, program: Int(d[0]))
        default: return nil      // 0xA0 polyphonic pressure, 0xD0 channel pressure, 0xE0 pitch bend
        }
    }
}
