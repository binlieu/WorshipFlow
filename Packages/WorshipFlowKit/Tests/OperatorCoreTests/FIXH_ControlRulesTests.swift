// FIX-H item 8 (UI-005b): what can be tested of the custom controls without the interface: how a focused slider moves with the keys,
// and the enabled state that dims a control and makes it ignore input. What needs VoiceOver by hand is listed in the hands-on checklist.
import Testing
@testable import OperatorCore

@Suite struct FIXH_ControlRulesTests {
    @Test func theArrowsMoveASliderInStepsOfATwentiethOfItsRange() {
        #expect(SliderStepping.value(from: 0.5, range: 0...1, move: .larger) == 0.55)
        #expect(SliderStepping.value(from: 0.5, range: 0...1, move: .smaller) == 0.45)
        #expect(SliderStepping.value(from: 30, range: 0...200, move: .larger) == 40)
    }

    @Test func aPageMoveIsAFifthAndHomeAndEndGoToTheEnds() {
        #expect(SliderStepping.value(from: 0.5, range: 0...1, move: .largerPage) == 0.7)
        #expect(SliderStepping.value(from: 0.5, range: 0...1, move: .smallerPage) == 0.3)
        #expect(SliderStepping.value(from: 0.5, range: 0...1, move: .minimum) == 0)
        #expect(SliderStepping.value(from: 0.5, range: 2...8, move: .maximum) == 8)
    }

    @Test func aMoveNeverLeavesTheRange() {
        #expect(SliderStepping.value(from: 0.98, range: 0...1, move: .larger) == 1)
        #expect(SliderStepping.value(from: 0.02, range: 0...1, move: .smaller) == 0)
        #expect(SliderStepping.value(from: 5, range: 0...1, move: .smaller) == 0.95)       // a value outside is first held inside
    }

    @Test func oddValuesAndEmptyRangesAreHandled() {
        #expect(SliderStepping.value(from: .nan, range: 0...1, move: .larger) == 0.05)
        #expect(SliderStepping.value(from: .infinity, range: 0...1, move: .smaller) == 0.95)
        #expect(SliderStepping.value(from: 3, range: 4...4, move: .larger) == 4)
    }

    @Test func aDisabledControlIsDimmedAndIgnoresInput() {
        #expect(ControlEnabledStyle.opacity(isEnabled: true) == 1)
        #expect(ControlEnabledStyle.opacity(isEnabled: false) == 0.45)
        #expect(ControlEnabledStyle.acceptsInput(isEnabled: true) && !ControlEnabledStyle.acceptsInput(isEnabled: false))
    }

    @Test func segmentsAreIdentifiedByPositionSoTwoSegmentsMayShareALabel() {
        #expect(SegmentIdentity.ids(count: 3) == [0, 1, 2])
        #expect(SegmentIdentity.ids(count: 0).isEmpty)
        #expect(SegmentIdentity.selectedIndex(values: ["a", "b", "a"], selection: "a") == 0)        // the first match, by value
        #expect(SegmentIdentity.selectedIndex(values: ["a", "b"], selection: "z") == nil)
    }
}
