// CUE-003: the fake behaves like the contract of MIDIPorts says, so router tests mean something.
import Testing
import Foundation
import CueEngine
@testable import MIDIIO

@Suite struct FakeMIDIPortsTests {
    @Test func listsSourcesAndDestinationsWithStableIDs() {
        let f = FakeMIDIPorts()
        f.addSource(id: 11, name: "Pad Controller", manufacturer: "Acme")
        f.addDestination(id: 21, name: "Lights", manufacturer: "Beta")
        #expect(f.sources() == [MIDIEndpointInfo(id: 11, name: "Pad Controller", manufacturer: "Acme", isOnline: true)])
        #expect(f.destinations().map(\.id) == [21])
    }

    @Test func messagesFlowOnlyFromConnectedSources() async throws {
        let f = FakeMIDIPorts()
        f.addSource(id: 1, name: "A")
        f.addSource(id: 2, name: "B")
        try f.connect(source: 1)
        let stream = f.makeIncomingStream()
        f.emit(.noteOn(channel: 1, note: 60, velocity: 100), from: 1)
        f.emit(.noteOn(channel: 1, note: 61, velocity: 100), from: 2)      // not connected: not delivered
        f.emit(.noteOn(channel: 1, note: 62, velocity: 100), from: 1)
        var got: [MIDIMessage] = []
        for await r in stream { got.append(r.message); if got.count == 2 { break } }
        #expect(got == [.noteOn(channel: 1, note: 60, velocity: 100), .noteOn(channel: 1, note: 62, velocity: 100)])
    }

    @Test func connectingAnUnknownOrOfflineSourceFails() {
        let f = FakeMIDIPorts()
        f.addSource(id: 1, name: "A", isOnline: false)
        #expect(throws: MIDIPortError.self) { try f.connect(source: 1) }
        #expect(throws: MIDIPortError.self) { try f.connect(source: 99) }
        #expect(f.connectedSourceIDs.isEmpty)
    }

    @Test func removingASourceDropsItsConnectionAndSignalsAChange() async throws {
        let f = FakeMIDIPorts()
        f.addSource(id: 1, name: "A")
        try f.connect(source: 1)
        let changes = f.makeChangeStream()
        f.removeSource(id: 1)
        #expect(f.connectedSourceIDs.isEmpty)
        var it = changes.makeAsyncIterator()
        #expect(await it.next() != nil)
    }

    @Test func sendRecordsMessagesAndRefusesOfflineOrInvalid() throws {
        let f = FakeMIDIPorts()
        f.addDestination(id: 5, name: "Out")
        try f.send(.programChange(channel: 3, program: 9), to: 5)
        #expect(f.sent.count == 1)
        #expect(f.sent.first?.message == .programChange(channel: 3, program: 9))
        #expect(f.sent.first?.destination == 5)
        #expect(throws: MIDIPortError.self) { try f.send(.noteOn(channel: 0, note: 1, velocity: 1), to: 5) }
        f.setOnline(false, destination: 5)
        #expect(throws: MIDIPortError.self) { try f.send(.noteOn(channel: 1, note: 1, velocity: 1), to: 5) }
        #expect(f.sent.count == 1)
    }

    @Test func rawBytesWithRunningStatusAreDecodedAndForeignBytesCounted() async throws {
        let f = FakeMIDIPorts()
        f.addSource(id: 1, name: "A")
        try f.connect(source: 1)
        let stream = f.makeIncomingStream()
        f.emit(bytes: [0x90, 60, 100, 62, 100, 0xF8, 0xF0, 1, 2, 0xF7], from: 1)
        var got: [MIDIMessage] = []
        for await r in stream { got.append(r.message); if got.count == 2 { break } }
        #expect(got.count == 2)
    }

    @Test func virtualEndpointsSwitchOnAndOff() throws {
        let f = FakeMIDIPorts()
        #expect(f.virtualEndpointsEnabled == false)
        #expect(throws: MIDIPortError.self) { try f.publish(.noteOn(channel: 1, note: 1, velocity: 1)) }
        try f.setVirtualEndpointsEnabled(true)
        #expect(f.virtualEndpointsEnabled)
        try f.publish(.noteOn(channel: 1, note: 1, velocity: 1))
        #expect(f.published == [.noteOn(channel: 1, note: 1, velocity: 1)])
        try f.setVirtualEndpointsEnabled(false)
        #expect(f.virtualEndpointsEnabled == false)
    }
}
