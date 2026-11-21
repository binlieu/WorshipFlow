// CUE-001 (AUTO-03): MIDI bindings, learn, conflicts and the held-pad rule.
import Testing
import Foundation
@testable import CueEngine

private func binding(_ pattern: MIDIPattern, _ command: MIDICommand, name: String = "b") -> MIDIBinding {
    MIDIBinding(id: UUID(), name: name, pattern: pattern, command: command)
}

@Suite struct MIDIPatternTests {
    @Test func noteOnPatternMatchesChannelNoteAndVelocityRange() {
        let p = MIDIPattern(kind: .noteOn, channel: 1, number: 60)
        #expect(p.matches(.noteOn(channel: 1, note: 60, velocity: 1)))
        #expect(p.matches(.noteOn(channel: 1, note: 60, velocity: 127)))
        #expect(!p.matches(.noteOn(channel: 2, note: 60, velocity: 100)))
        #expect(!p.matches(.noteOn(channel: 1, note: 61, velocity: 100)))
        let soft = MIDIPattern(kind: .noteOn, channel: 1, number: 60, valueRange: 1...63)
        #expect(soft.matches(.noteOn(channel: 1, note: 60, velocity: 63)))
        #expect(!soft.matches(.noteOn(channel: 1, note: 60, velocity: 64)))
    }

    @Test func nilChannelAndNumberMeanAny() {
        let anyNote = MIDIPattern(kind: .noteOn, channel: 3, number: nil)
        #expect(anyNote.matches(.noteOn(channel: 3, note: 0, velocity: 5)))
        #expect(anyNote.matches(.noteOn(channel: 3, note: 127, velocity: 5)))
        let omni = MIDIPattern(kind: .noteOn, channel: nil, number: 60)
        for ch in 1...16 { #expect(omni.matches(.noteOn(channel: ch, note: 60, velocity: 9))) }
    }

    @Test func noteOffAndZeroVelocityNeverMatch() {
        let p = MIDIPattern(kind: .noteOn)
        #expect(!p.matches(.noteOff(channel: 1, note: 60, velocity: 64)))
        #expect(!p.matches(.noteOn(channel: 1, note: 60, velocity: 0)))
    }

    @Test func controlChangeAndProgramChangePatterns() {
        let cc = MIDIPattern(kind: .controlChange, channel: 1, number: 20, valueRange: 64...127)
        #expect(cc.matches(.controlChange(channel: 1, controller: 20, value: 64)))
        #expect(!cc.matches(.controlChange(channel: 1, controller: 20, value: 63)))
        #expect(!cc.matches(.controlChange(channel: 1, controller: 21, value: 100)))
        let pc = MIDIPattern(kind: .programChange, channel: 2, number: 5)
        #expect(pc.matches(.programChange(channel: 2, program: 5)))
        #expect(!pc.matches(.programChange(channel: 2, program: 6)))
        #expect(!pc.matches(.controlChange(channel: 2, controller: 5, value: 5)))
    }

    @Test func invalidMessagesNeverMatch() {
        let p = MIDIPattern(kind: .noteOn)
        #expect(!p.matches(.noteOn(channel: 0, note: 60, velocity: 100)))
        #expect(!p.matches(.noteOn(channel: 1, note: 200, velocity: 100)))
    }

    @Test func patternValidity() {
        #expect(MIDIPattern(kind: .noteOn, channel: 1, number: 60).isValid)
        #expect(!MIDIPattern(kind: .noteOn, channel: 0).isValid)
        #expect(!MIDIPattern(kind: .noteOn, channel: 17).isValid)
        #expect(!MIDIPattern(kind: .noteOn, number: 128).isValid)
        #expect(!MIDIPattern(kind: .controlChange, valueRange: 0...200).isValid)
        #expect(!MIDIPattern(kind: .programChange, valueRange: 0...10).isValid)
    }
}

@Suite struct MIDIBindingSetTests {
    let next = MIDICommand.transport(.next)
    let prev = MIDICommand.transport(.previous)

    @Test func lookupReturnsTheCommandOfTheMatchingBinding() {
        let set = MIDIBindingSet(bindings: [
            binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next),
            binding(MIDIPattern(kind: .noteOn, channel: 1, number: 61), prev),
        ])
        #expect(set.command(for: .noteOn(channel: 1, note: 60, velocity: 90)) == next)
        #expect(set.command(for: .noteOn(channel: 1, note: 61, velocity: 90)) == prev)
        #expect(set.command(for: .noteOn(channel: 1, note: 62, velocity: 90)) == nil)
        #expect(set.command(for: .noteOff(channel: 1, note: 60, velocity: 0)) == nil)
    }

    @Test func aMacroCanBeBound() {
        let macro = UUID()
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .programChange, channel: 1, number: 3), .macro(macro))])
        #expect(set.command(for: .programChange(channel: 1, program: 3)) == .macro(macro))
    }

    @Test func firstBindingInListOrderWinsWhenSeveralMatch() {
        let set = MIDIBindingSet(bindings: [
            binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next),
            binding(MIDIPattern(kind: .noteOn), prev),
        ])
        #expect(set.command(for: .noteOn(channel: 1, note: 60, velocity: 9)) == next)
        #expect(set.command(for: .noteOn(channel: 1, note: 61, velocity: 9)) == prev)
    }

    @Test func commandsExpandToCueActions() {
        let macro = UUID()
        #expect(MIDICommand.transport(.clear).actions == [.transport(.clear)])
        #expect(MIDICommand.macro(macro).actions == [.runMacro(macro)])
    }

    @Test(arguments: [
        // (a, b, conflict?)
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .noteOn, channel: 1, number: 60), true),
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .noteOn, channel: nil, number: 60), true),
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .noteOn, channel: 1, number: nil), true),
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .noteOn, channel: 2, number: 60), false),
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .noteOn, channel: 1, number: 61), false),
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60), MIDIPattern(kind: .controlChange, channel: 1, number: 60), false),
        (MIDIPattern(kind: .controlChange, channel: 1, number: 7, valueRange: 0...63), MIDIPattern(kind: .controlChange, channel: 1, number: 7, valueRange: 64...127), false),
        (MIDIPattern(kind: .controlChange, channel: 1, number: 7, valueRange: 0...64), MIDIPattern(kind: .controlChange, channel: 1, number: 7, valueRange: 64...127), true),
        (MIDIPattern(kind: .controlChange, channel: 1, number: 7), MIDIPattern(kind: .controlChange, channel: 1, number: 7, valueRange: 100...100), true),
        // A note-on can never have velocity 0, so a range of 0...0 matches nothing and cannot conflict.
        (MIDIPattern(kind: .noteOn, channel: 1, number: 60, valueRange: 0...0), MIDIPattern(kind: .noteOn, channel: 1, number: 60), false),
        (MIDIPattern(kind: .programChange, channel: 1, number: 2), MIDIPattern(kind: .programChange, channel: nil, number: 2), true),
    ]) func overlapRule(_ a: MIDIPattern, _ b: MIDIPattern, _ conflict: Bool) {
        #expect(a.overlaps(b) == conflict)
        #expect(b.overlaps(a) == conflict)
    }

    @Test func conflictsListsEachPairOnceInListOrder() {
        let a = binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next, name: "a")
        let b = binding(MIDIPattern(kind: .noteOn, channel: 1, number: 61), prev, name: "b")
        let c = binding(MIDIPattern(kind: .noteOn, channel: nil, number: 60), .transport(.stop), name: "c")
        let set = MIDIBindingSet(bindings: [a, b, c])
        #expect(set.conflicts() == [MIDIConflict(first: a.id, second: c.id)])
        #expect(MIDIBindingSet(bindings: [a, b]).conflicts().isEmpty)
    }

    @Test func conflictsWithACandidateForTheLearnScreen() {
        let a = binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)
        let set = MIDIBindingSet(bindings: [a])
        let candidate = binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), prev)
        #expect(set.conflicts(with: candidate).map(\.id) == [a.id])
        #expect(set.conflicts(with: binding(MIDIPattern(kind: .noteOn, channel: 1, number: 61), prev)).isEmpty)
        // Replacing a binding by itself is not a conflict.
        #expect(set.conflicts(with: a).isEmpty)
    }

    @Test func roundTripsThroughJSON() throws {
        let set = MIDIBindingSet(bindings: [
            binding(MIDIPattern(kind: .controlChange, channel: 4, number: 20, valueRange: 64...127), .transport(.goToSlide(index: 2))),
            binding(MIDIPattern(kind: .noteOn), .macro(UUID())),
        ])
        let data = try JSONEncoder().encode(set)
        #expect(try JSONDecoder().decode(MIDIBindingSet.self, from: data) == set)
    }
}

@Suite struct MIDILearnTests {
    @Test func unarmedLearnerIgnoresEverything() {
        var l = MIDILearner()
        #expect(l.feed(.noteOn(channel: 1, note: 60, velocity: 100)) == nil)
        #expect(!l.isArmed)
    }

    @Test func armedLearnerTurnsTheFirstUsableMessageIntoAPatternThenDisarms() {
        var l = MIDILearner()
        l.arm()
        #expect(l.isArmed)
        #expect(l.feed(.noteOff(channel: 3, note: 60, velocity: 0)) == nil)             // releases are not learnable
        #expect(l.feed(.noteOn(channel: 3, note: 60, velocity: 0)) == nil)              // neither is velocity zero
        #expect(l.isArmed)
        #expect(l.feed(.noteOn(channel: 3, note: 60, velocity: 100)) == MIDIPattern(kind: .noteOn, channel: 3, number: 60))
        #expect(!l.isArmed)
        #expect(l.feed(.noteOn(channel: 3, note: 61, velocity: 100)) == nil)
    }

    @Test func learnsControlChangeAndProgramChangeWithoutAValueRange() {
        var l = MIDILearner()
        l.arm()
        #expect(l.feed(.controlChange(channel: 2, controller: 20, value: 127)) == MIDIPattern(kind: .controlChange, channel: 2, number: 20))
        l.arm()
        #expect(l.feed(.programChange(channel: 16, program: 9)) == MIDIPattern(kind: .programChange, channel: 16, number: 9))
    }

    @Test func invalidMessagesAreNotLearned() {
        var l = MIDILearner()
        l.arm()
        #expect(l.feed(.noteOn(channel: 99, note: 60, velocity: 100)) == nil)
        #expect(l.isArmed)
    }

    @Test func cancelDisarms() {
        var l = MIDILearner()
        l.arm()
        l.cancel()
        #expect(l.feed(.noteOn(channel: 1, note: 60, velocity: 100)) == nil)
    }

    @Test func staticHelperLearnsWithoutState() {
        #expect(MIDIPattern.learned(from: .noteOn(channel: 1, note: 5, velocity: 9)) == MIDIPattern(kind: .noteOn, channel: 1, number: 5))
        #expect(MIDIPattern.learned(from: .noteOff(channel: 1, note: 5, velocity: 9)) == nil)
    }
}

@Suite struct MIDICommandFilterTests {
    let next = MIDICommand.transport(.next)
    let prev = MIDICommand.transport(.previous)

    @Test func aHeldPadAdvancesOnceNoMatterHowManyNoteOnsArrive() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0) == next)
        for i in 1...20 {
            #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: Double(i) * 0.02) == nil)
        }
        #expect(f.command(for: .noteOff(channel: 1, note: 60, velocity: 0), in: set, at: 0.5) == nil)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.6) == next)
    }

    @Test func velocityZeroNoteOnReleasesThePad() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0) == next)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 0), in: set, at: 0.1) == nil)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.2) == next)
    }

    @Test func aNoteOffNeverTriggersEvenWithACatchAllBinding() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOff(channel: 1, note: 60, velocity: 64), in: set, at: 0) == nil)
    }

    @Test func heldStateIsPerNoteForACatchAllBinding() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0) == next)
        #expect(f.command(for: .noteOn(channel: 1, note: 61, velocity: 100), in: set, at: 0.1) == next)   // another pad
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.2) == nil)    // first still held
        #expect(f.command(for: .noteOff(channel: 1, note: 60, velocity: 0), in: set, at: 0.3) == nil)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.4) == next)
        #expect(f.command(for: .noteOn(channel: 1, note: 61, velocity: 100), in: set, at: 0.5) == nil)
    }

    @Test func aMissedNoteOffDoesNotKillThePadForever() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)])
        var f = MIDICommandFilter(noteStaleAfter: 5)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0) == next)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 4.9) == nil)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 10.0) == next)   // 5.1 s after the last sign of life
    }

    @Test func aControlChangeFiresOnEnteringItsRangeNotOnEveryValue() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .controlChange, channel: 1, number: 20, valueRange: 64...127), next)])
        var f = MIDICommandFilter(ccRepeatWindow: 0.3)
        func cc(_ v: Int, _ t: Double) -> MIDICommand? { f.command(for: .controlChange(channel: 1, controller: 20, value: v), in: set, at: t) }
        #expect(cc(0, 0.00) == nil)
        #expect(cc(10, 0.01) == nil)
        #expect(cc(70, 0.02) == next)       // sweep upward crosses into the range: once
        #expect(cc(80, 0.03) == nil)
        #expect(cc(127, 0.04) == nil)
        #expect(cc(127, 0.05) == nil)       // repeated value
        #expect(cc(5, 0.06) == nil)         // leaves the range: re-armed
        #expect(cc(65, 0.07) == next)
    }

    @Test func aPadSendingOnly127OnPressWorksAgainAfterTheRepeatWindow() {
        // A momentary "trigger" controller sends 127 on every press and nothing on release.
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .controlChange, channel: 1, number: 20, valueRange: 127...127), next)])
        var f = MIDICommandFilter(ccRepeatWindow: 0.3)
        func press(_ t: Double) -> MIDICommand? { f.command(for: .controlChange(channel: 1, controller: 20, value: 127), in: set, at: t) }
        #expect(press(0.00) == next)
        #expect(press(0.02) == nil)         // auto-repeat inside the window
        #expect(press(0.10) == nil)
        #expect(press(0.35) == nil)         // still within 0.3 s of the previous message (0.10 -> 0.35 = 0.25)
        #expect(press(1.00) == next)        // 0.65 s of silence: a new press
    }

    @Test func programChangeFiresEveryTime() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .programChange, channel: 1, number: 5), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .programChange(channel: 1, program: 5), in: set, at: 0) == next)
        #expect(f.command(for: .programChange(channel: 1, program: 5), in: set, at: 0.1) == next)
        #expect(f.command(for: .programChange(channel: 1, program: 6), in: set, at: 0.2) == nil)
    }

    @Test func theRuleAppliesToMacrosToo() {
        let m = MIDICommand.macro(UUID())
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), m)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0) == m)
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.01) == nil)
    }

    @Test func resetForgetsHeldPads() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)])
        var f = MIDICommandFilter()
        _ = f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0)
        f.reset()
        #expect(f.command(for: .noteOn(channel: 1, note: 60, velocity: 100), in: set, at: 0.01) == next)
    }

    @Test func unmatchedMessagesReturnNilAndKeepNoState() {
        let set = MIDIBindingSet(bindings: [binding(MIDIPattern(kind: .noteOn, channel: 1, number: 60), next)])
        var f = MIDICommandFilter()
        #expect(f.command(for: .noteOn(channel: 1, note: 99, velocity: 100), in: set, at: 0) == nil)
        #expect(f.command(for: .controlChange(channel: 1, controller: 1, value: 1), in: set, at: 0) == nil)
    }
}
