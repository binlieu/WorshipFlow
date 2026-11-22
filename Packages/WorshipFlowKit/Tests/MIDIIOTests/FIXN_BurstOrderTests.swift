// FIX-N item 10: a burst through the router is never shed and never reordered, whatever the load. Counted by the router and the ports themselves
// (not by how fast the main actor runs the consumer), so the answer does not depend on patience: the router's own counter and the ports' drop counter say
// whether anything was lost; the sink says whether it arrived in order.
import Testing
import Foundation
import CueEngine
@testable import MIDIIO

@MainActor
private final class OrderSink { var messages: [MIDIMessage] = [] }

@MainActor
@Suite struct FIXN_BurstOrderTests {
    @Test func aBurstOfControlChangesArrivesCompleteAndInOrderWithNothingShed() async throws {
        let f = FakeMIDIPorts(); f.addSource(id: 1, name: "Pad")
        let sink = OrderSink()
        let all = MIDIBinding(name: "any cc", pattern: MIDIPattern(kind: .controlChange), command: .transport(.next))
        let r = MIDIRouter(ports: f, bindings: MIDIBindingSet(bindings: [all])) { _, m in sink.messages.append(m) }
        r.filter = MIDICommandFilter(noteStaleAfter: 5, ccRepeatWindow: 0)
        r.start(); r.selectSource(1)
        let count = 5000
        for i in 0..<count { f.emit(.controlChange(channel: 1, controller: i % 128, value: i % 100), from: 1) }
        // Drain without a time limit that means anything: yield until the router has taken every message (a hang would be a lost message, and the
        // ports' counters below would already say so).
        let deadline = Date().addingTimeInterval(600)
        while sink.messages.count < count, Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        #expect(f.statistics.delivered == count && f.statistics.droppedMessages == 0)
        #expect(r.receivedCount == count)
        let expected: [MIDIMessage] = (0..<count).map { .controlChange(channel: 1, controller: $0 % 128, value: $0 % 100) }
        #expect(sink.messages == expected)
        r.stop()
    }

    @Test func aSubscriberThatFallsBehindShedsTheOldestAndSaysSo() async throws {
        // The one place messages ARE shed, and it is counted: a bounded buffer (the app's holds 65,536). Never silent, never reordering what is kept.
        let b = Broadcaster<Int>(capacity: 4)
        let stream = b.subscribe()
        var dropped = 0
        for i in 0..<10 { dropped += b.send(i) }
        b.finish()
        var kept: [Int] = []
        for await v in stream { kept.append(v) }
        #expect(dropped == 6)
        #expect(kept == [6, 7, 8, 9])
    }
}
