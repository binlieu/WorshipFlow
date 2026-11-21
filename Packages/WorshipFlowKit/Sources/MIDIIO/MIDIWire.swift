// CUE-003: conversion between Universal MIDI Packet words (and raw MIDI 1.0 bytes) and CueEngine.MIDIMessage.
// Pure functions. Byte-level decoding goes through the engine's MIDIParser so there is one definition of what a
// message is (note-on with velocity zero is a note-off, and so on).
import Foundation
import CueEngine
import Darwin

public enum MIDIWire {
    /// One MIDI 1.0 channel voice message as a UMP word (message type 2, group 0). Nil for an invalid message.
    public static func word(for message: MIDIMessage) -> UInt32? {
        guard let b = message.bytes else { return nil }
        let d2: UInt32 = b.count > 2 ? UInt32(b[2]) : 0
        return 0x2000_0000 | UInt32(b[0]) << 16 | UInt32(b[1]) << 8 | d2
    }

    /// Number of 32-bit words in a UMP event, from its message type nibble (Universal MIDI Packet spec table).
    static func wordCount(forType type: UInt32) -> Int {
        switch type {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4                       // 0x5, 0xD, 0xE, 0xF
        }
    }

    /// Decodes a run of UMP words. Channel voice 1.0 words become messages; every other event, and a final event cut
    /// short, counts as one ignored event.
    public static func decode<C: RandomAccessCollection>(words: C) -> (messages: [MIDIMessage], ignored: Int) where C.Element == UInt32 {
        var messages: [MIDIMessage] = []
        var ignored = 0
        var i = words.startIndex
        while i < words.endIndex {
            let w = words[i]
            let type = w >> 28
            let n = wordCount(forType: type)
            if words.distance(from: i, to: words.endIndex) < n { ignored += 1; break }
            i = words.index(i, offsetBy: n)
            guard type == 0x2 else { ignored += 1; continue }
            let status = UInt8((w >> 16) & 0xFF)
            let d1 = UInt8((w >> 8) & 0x7F), d2 = UInt8(w & 0x7F)
            let bytes: [UInt8] = (status & 0xF0 == 0xC0 || status & 0xF0 == 0xD0) ? [status, d1] : [status, d1, d2]
            let parsed = MIDIParser.parse(bytes)         // a fresh parser: a UMP word is always a complete message
            if parsed.isEmpty { ignored += 1 } else { messages.append(contentsOf: parsed) }
        }
        return (messages, ignored)
    }

    /// Decodes raw MIDI 1.0 bytes with the engine's parser (running status, real-time bytes, system exclusive skipped).
    public static func messages(fromBytes bytes: [UInt8]) -> [MIDIMessage] { MIDIParser.parse(bytes) }

    // MARK: Time

    private static let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t.denom == 0 ? mach_timebase_info_data_t(numer: 1, denom: 1) : t
    }()

    /// Host time ticks (CoreMIDI's MIDITimeStamp) to seconds. Zero means "now".
    public static func seconds(fromHostTime ticks: UInt64) -> TimeInterval {
        let t = ticks == 0 ? mach_absolute_time() : ticks
        return Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    public static func nowSeconds() -> TimeInterval { seconds(fromHostTime: mach_absolute_time()) }
}
