// CUE-001 (AUTO-03, AUTO-04): MIDI byte parsing and encoding. Table-driven, concrete byte sequences.
import Testing
import Foundation
@testable import CueEngine

@Suite struct MIDIParserTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var bytes: [UInt8]
        var expected: [MIDIMessage]
        var ignored: Int = 0
        var testDescription: String { name }
    }

    static let table: [Case] = [
        Case(name: "note on channel 1", bytes: [0x90, 60, 100], expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "note on channel 16, lowest note, top velocity", bytes: [0x9F, 0, 127], expected: [.noteOn(channel: 16, note: 0, velocity: 127)]),
        Case(name: "note off keeps its release velocity", bytes: [0x80, 60, 64], expected: [.noteOff(channel: 1, note: 60, velocity: 64)]),
        Case(name: "note on with velocity zero is a note off", bytes: [0x90, 60, 0], expected: [.noteOff(channel: 1, note: 60, velocity: 0)]),
        Case(name: "control change channel 2", bytes: [0xB1, 7, 100], expected: [.controlChange(channel: 2, controller: 7, value: 100)]),
        Case(name: "program change is two bytes, channel 3", bytes: [0xC2, 5], expected: [.programChange(channel: 3, program: 5)]),
        Case(name: "empty input", bytes: [], expected: []),
        Case(name: "running status note on then note on with velocity zero",
             bytes: [0x90, 60, 100, 62, 100, 64, 0],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100), .noteOn(channel: 1, note: 62, velocity: 100), .noteOff(channel: 1, note: 64, velocity: 0)]),
        Case(name: "running status control change",
             bytes: [0xB0, 1, 10, 1, 20],
             expected: [.controlChange(channel: 1, controller: 1, value: 10), .controlChange(channel: 1, controller: 1, value: 20)]),
        Case(name: "running status program change",
             bytes: [0xC0, 1, 2, 3],
             expected: [.programChange(channel: 1, program: 1), .programChange(channel: 1, program: 2), .programChange(channel: 1, program: 3)]),
        Case(name: "a new status byte replaces running status",
             bytes: [0x90, 60, 100, 0xB1, 7, 9, 8, 10],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100), .controlChange(channel: 2, controller: 7, value: 9), .controlChange(channel: 2, controller: 8, value: 10)]),
        Case(name: "stray data bytes without a status are ignored and counted",
             bytes: [60, 100, 0x90, 62, 100],
             expected: [.noteOn(channel: 1, note: 62, velocity: 100)], ignored: 2),
        Case(name: "real-time clock byte between data bytes does not break the message",
             bytes: [0x90, 60, 0xF8, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "real-time bytes before and after do not disturb running status",
             bytes: [0x90, 60, 100, 0xFE, 0xF8, 62, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100), .noteOn(channel: 1, note: 62, velocity: 100)]),
        Case(name: "truncated message is dropped when a new status arrives",
             bytes: [0x90, 60, 0x80, 61, 0],
             expected: [.noteOff(channel: 1, note: 61, velocity: 0)], ignored: 1),
        Case(name: "lone status byte then another status",
             bytes: [0x90, 0xC0, 9],
             expected: [.programChange(channel: 1, program: 9)]),
        Case(name: "system exclusive is skipped and running status is cancelled",
             bytes: [0x90, 60, 100, 0xF0, 1, 2, 3, 0xF7, 61, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)], ignored: 2),
        Case(name: "system exclusive then a fresh message",
             bytes: [0xF0, 0x7E, 0x7F, 0xF7, 0x90, 60, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "system exclusive cut off by a status byte (no end marker)",
             bytes: [0xF0, 1, 2, 0x90, 60, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "pitch bend is consumed whole and produces nothing",
             bytes: [0xE0, 1, 2, 0x90, 60, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "pitch bend keeps its own running status, so its data bytes are not misread",
             bytes: [0xE0, 1, 2, 3, 4, 0x90, 60, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "polyphonic aftertouch (two data bytes) is consumed",
             bytes: [0xA0, 60, 10, 0x90, 61, 100],
             expected: [.noteOn(channel: 1, note: 61, velocity: 100)]),
        Case(name: "channel pressure (one data byte) is consumed",
             bytes: [0xD0, 5, 0x90, 61, 100],
             expected: [.noteOn(channel: 1, note: 61, velocity: 100)]),
        Case(name: "song position pointer (two data bytes) is consumed and cancels running status",
             bytes: [0x90, 60, 100, 0xF2, 1, 2, 62, 100, 0x90, 63, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100), .noteOn(channel: 1, note: 63, velocity: 100)], ignored: 2),
        Case(name: "song select, tune request and stray end-of-sysex are consumed",
             bytes: [0xF3, 4, 0xF6, 0xF7, 0x90, 60, 100],
             expected: [.noteOn(channel: 1, note: 60, velocity: 100)]),
        Case(name: "only status bytes", bytes: [0x90, 0x91, 0x92], expected: []),
        Case(name: "all-zero data after a note on is one message plus running status",
             bytes: [0x90, 0, 0, 0, 0],
             expected: [.noteOff(channel: 1, note: 0, velocity: 0), .noteOff(channel: 1, note: 0, velocity: 0)]),
    ]

    @Test(arguments: table) func parses(_ c: Case) {
        var parser = MIDIParser()
        #expect(parser.feed(c.bytes) == c.expected)
        #expect(parser.ignoredByteCount == c.ignored)
    }

    @Test func oneShotParseMatchesAFreshParser() {
        #expect(MIDIParser.parse([0x90, 60, 100, 62, 0]) == [.noteOn(channel: 1, note: 60, velocity: 100), .noteOff(channel: 1, note: 62, velocity: 0)])
    }

    @Test func messagesSplitAcrossChunksAreJoinedAndRunningStatusSurvivesBetweenChunks() {
        var p = MIDIParser()
        #expect(p.feed([0x90, 60]) == [])
        #expect(p.feed([100]) == [.noteOn(channel: 1, note: 60, velocity: 100)])
        #expect(p.feed([62, 100]) == [.noteOn(channel: 1, note: 62, velocity: 100)])
        #expect(p.feed([63]) == [])
        #expect(p.feed([0]) == [.noteOff(channel: 1, note: 63, velocity: 0)])
    }

    @Test func aStatusByteAloneInOneChunkThenDataInTheNext() {
        var p = MIDIParser()
        #expect(p.feed([0xB4]) == [])
        #expect(p.feed([10, 20]) == [.controlChange(channel: 5, controller: 10, value: 20)])
    }

    @Test func resetForgetsRunningStatusAndPartialMessage() {
        var p = MIDIParser()
        _ = p.feed([0x90, 60, 100])
        p.reset()
        #expect(p.feed([62, 100]) == [])            // running status gone: stray data
        _ = p.feed([0x90, 60])
        p.reset()
        #expect(p.feed([100]) == [])                // partial message gone
    }

    @Test func everyPossiblePairOfBytesIsHandledWithoutTrapping() {
        // Safe-by-construction check: 65,536 two-byte inputs, each also followed by a valid message.
        // After any garbage a clean status byte must always recover.
        for a in 0...255 {
            for b in 0...255 {
                var p = MIDIParser()
                _ = p.feed([UInt8(a), UInt8(b)])
                let out = p.feed([0x90, 60, 100])
                #expect(out.last == .noteOn(channel: 1, note: 60, velocity: 100), "a=\(a) b=\(b)")
            }
        }
    }

    @Test func aLongRandomStreamNeverProducesAnInvalidMessage() {
        var rng = SplitMix(seed: 0xC0FFEE)
        var p = MIDIParser()
        for _ in 0..<200 {
            let chunk = (0..<64).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            for m in p.feed(chunk) { #expect(m.isValid) }
        }
    }
}

/// Tiny deterministic generator so the random test is repeatable.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@Suite struct MIDIEncodingTests {
    @Test(arguments: [
        (MIDIMessage.noteOn(channel: 1, note: 60, velocity: 100), [UInt8]([0x90, 60, 100])),
        (.noteOn(channel: 16, note: 127, velocity: 1), [0x9F, 127, 1]),
        (.noteOff(channel: 16, note: 60, velocity: 0), [0x8F, 60, 0]),
        (.controlChange(channel: 2, controller: 64, value: 127), [0xB1, 64, 127]),
        (.programChange(channel: 3, program: 127), [0xC2, 127]),
    ]) func encodes(_ m: MIDIMessage, _ bytes: [UInt8]) {
        #expect(m.bytes == bytes)
    }

    @Test(arguments: [
        MIDIMessage.noteOn(channel: 0, note: 60, velocity: 100),
        .noteOn(channel: 17, note: 60, velocity: 100),
        .noteOn(channel: 1, note: 128, velocity: 100),
        .noteOn(channel: 1, note: -1, velocity: 100),
        .noteOff(channel: 1, note: 60, velocity: 128),
        .controlChange(channel: 1, controller: 200, value: 0),
        .controlChange(channel: 1, controller: 1, value: -5),
        .programChange(channel: 1, program: 128),
    ]) func outOfRangeMessagesDoNotEncode(_ m: MIDIMessage) {
        #expect(m.isValid == false)
        #expect(m.bytes == nil)
    }

    @Test func runningStatusIsUsedOnlyWhenAsked() {
        let seq: [MIDIMessage] = [
            .noteOn(channel: 1, note: 60, velocity: 100),
            .noteOn(channel: 1, note: 62, velocity: 100),
            .noteOn(channel: 2, note: 60, velocity: 100),
            .controlChange(channel: 2, controller: 7, value: 9),
            .controlChange(channel: 2, controller: 7, value: 10),
            .noteOff(channel: 2, note: 60, velocity: 0),
        ]
        #expect(MIDIMessage.encode(seq, runningStatus: false) ==
                [0x90, 60, 100, 0x90, 62, 100, 0x91, 60, 100, 0xB1, 7, 9, 0xB1, 7, 10, 0x81, 60, 0])
        #expect(MIDIMessage.encode(seq, runningStatus: true) ==
                [0x90, 60, 100, 62, 100, 0x91, 60, 100, 0xB1, 7, 9, 7, 10, 0x81, 60, 0])
    }

    @Test func invalidMessagesInASequenceAreSkippedAndDoNotBreakRunningStatus() {
        let seq: [MIDIMessage] = [
            .noteOn(channel: 1, note: 60, velocity: 100),
            .noteOn(channel: 99, note: 60, velocity: 100),
            .noteOn(channel: 1, note: 61, velocity: 100),
        ]
        #expect(MIDIMessage.encode(seq, runningStatus: true) == [0x90, 60, 100, 61, 100])
    }

    @Test func encodeThenParseRoundTrips() {
        let seq: [MIDIMessage] = [
            .noteOn(channel: 1, note: 0, velocity: 1),
            .noteOn(channel: 1, note: 127, velocity: 127),
            .noteOff(channel: 1, note: 5, velocity: 64),
            .controlChange(channel: 16, controller: 120, value: 0),
            .controlChange(channel: 16, controller: 121, value: 127),
            .programChange(channel: 9, program: 0),
            .programChange(channel: 9, program: 1),
            .noteOn(channel: 9, note: 40, velocity: 90),
        ]
        for rs in [false, true] {
            #expect(MIDIParser.parse(MIDIMessage.encode(seq, runningStatus: rs)) == seq, "runningStatus=\(rs)")
        }
    }

    @Test func noteOnWithVelocityZeroEncodesAsWrittenButParsesAsNoteOff() {
        let m = MIDIMessage.noteOn(channel: 1, note: 60, velocity: 0)
        #expect(m.bytes == [0x90, 60, 0])
        #expect(MIDIParser.parse(m.bytes ?? []) == [.noteOff(channel: 1, note: 60, velocity: 0)])
    }
}
