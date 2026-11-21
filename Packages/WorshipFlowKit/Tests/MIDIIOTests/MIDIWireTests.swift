// CUE-003 (AUTO-03, AUTO-04): conversion between Universal MIDI Packet words / raw bytes and CueEngine.MIDIMessage.
// Pure functions; no CoreMIDI needed.
import Testing
import Foundation
import CueEngine
@testable import MIDIIO

@Suite struct MIDIWireTests {
    @Test func everyMessageKindOnEveryChannelRoundTripsThroughWords() throws {
        for ch in 1...16 {
            let messages: [MIDIMessage] = [
                .noteOn(channel: ch, note: 60, velocity: 100),
                .noteOff(channel: ch, note: 61, velocity: 5),
                .controlChange(channel: ch, controller: 7, value: 127),
                .programChange(channel: ch, program: 33),
            ]
            for m in messages {
                let w = try #require(MIDIWire.word(for: m))
                #expect(w >> 28 == 0x2)                      // UMP message type 2: MIDI 1.0 channel voice
                let decoded = MIDIWire.decode(words: [w])
                #expect(decoded.messages == [m])
                #expect(decoded.ignored == 0)
            }
        }
    }

    @Test func wordLayoutMatchesTheUMPSpecification() {
        // note on, channel 1 (0), note 60, velocity 100 -> type 2, group 0, status 0x90
        #expect(MIDIWire.word(for: .noteOn(channel: 1, note: 60, velocity: 100)) == 0x2090_3C64)
        // program change keeps its second data byte at zero
        #expect(MIDIWire.word(for: .programChange(channel: 16, program: 5)) == 0x20CF_0500)
    }

    @Test func invalidMessagesDoNotEncode() {
        #expect(MIDIWire.word(for: .noteOn(channel: 0, note: 60, velocity: 100)) == nil)
        #expect(MIDIWire.word(for: .noteOn(channel: 17, note: 60, velocity: 100)) == nil)
        #expect(MIDIWire.word(for: .noteOn(channel: 1, note: 128, velocity: 100)) == nil)
        #expect(MIDIWire.word(for: .controlChange(channel: 1, controller: 1, value: -1)) == nil)
    }

    @Test func noteOnWithVelocityZeroArrivesAsANoteOff() {
        let r = MIDIWire.decode(words: [0x2090_3C00])
        #expect(r.messages == [.noteOff(channel: 1, note: 60, velocity: 0)])
    }

    @Test func unsupportedAndNonChannelWordsAreIgnoredAndCounted() {
        let words: [UInt32] = [
            0x10F8_0000,                  // system real-time: timing clock
            0x10FE_0000,                  // active sensing
            0x20A0_3C40,                  // polyphonic key pressure (channel voice 1, not supported)
            0x20E0_0040,                  // pitch bend
            0x3016_0102, 0x0304_0506,     // sysex7, two words
            0x2090_3C64,                  // a real note in the middle
            0x40A0_3C00, 0x8000_0000,     // MIDI 2.0 channel voice (2 words)
            0x5000_0000, 0, 0, 0,         // data128 (4 words)
            0x0000_0000,                  // utility (NOOP)
        ]
        let r = MIDIWire.decode(words: words)
        #expect(r.messages == [.noteOn(channel: 1, note: 60, velocity: 100)])
        #expect(r.ignored == 8)
    }

    @Test func aTruncatedMultiWordEventIsIgnoredNotTrapped() {
        let r = MIDIWire.decode(words: [0x3016_0102])      // sysex7 announces 2 words, only 1 present
        #expect(r.messages.isEmpty)
        #expect(r.ignored == 1)
        #expect(MIDIWire.decode(words: []).messages.isEmpty)
    }

    @Test func outOfRangeDataBitsAreMaskedByTheSender() {
        // A misbehaving sender sets the top bit of a data byte; the word must not produce an invalid message.
        let r = MIDIWire.decode(words: [0x2090_BC64])      // data1 = 0xBC has bit 7 set
        for m in r.messages { #expect(m.isValid) }
    }

    @Test func runningStatusBytesDecodeThroughTheEngineParser() {
        let bytes: [UInt8] = [0x90, 60, 100, 62, 90, 64, 0, 0xB0, 7, 99, 8, 100]
        let messages = MIDIWire.messages(fromBytes: bytes)
        #expect(messages == [
            .noteOn(channel: 1, note: 60, velocity: 100),
            .noteOn(channel: 1, note: 62, velocity: 90),
            .noteOff(channel: 1, note: 64, velocity: 0),
            .controlChange(channel: 1, controller: 7, value: 99),
            .controlChange(channel: 1, controller: 8, value: 100),
        ])
    }

    @Test func hostTimeConversionTreatsZeroAsNow() {
        let now = MIDIWire.nowSeconds()
        let t = MIDIWire.seconds(fromHostTime: 0)
        #expect(t >= now)
        #expect(t - now < 1)
        #expect(MIDIWire.seconds(fromHostTime: 1_000_000_000) > 0)
    }
}
