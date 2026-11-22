// FIX-H item 7 (UI-005b): with keyboard focus on a control that is not a text field, Space and Return act on that control and the
// arrows act on a focused slider or segmented control; the show's transport keys apply only when nothing or the slide grid has focus.
// Escape from a focused control returns focus to the show. The decision is a pure function of (what has focus, key, sheet open).
import Testing
@testable import OperatorCore

@Suite struct FIXH_KeyFocusTests {
    static let controls: [FocusedElement] = [.toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp]
    static let keys: [KeyboardKey] = [.returnKey, .keypadEnter, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .deleteKey, .b, .other]

    @Test func spaceAndReturnOnAFocusedControlGoToTheControlNotTheShow() {
        for control in Self.controls {
            for key: KeyboardKey in [.returnKey, .keypadEnter, .space] {
                #expect(KeyRouting.decision(for: key, focus: control, sheetOpen: false) == .passThrough, "\(control) \(key)")
            }
        }
    }

    @Test func arrowsGoToAFocusedSliderOrSegmentedControlAndNeverMoveTheShow() {
        for control in Self.controls {
            for key: KeyboardKey in [.leftArrow, .rightArrow, .upArrow, .downArrow] {
                #expect(KeyRouting.decision(for: key, focus: control, sheetOpen: false) == .passThrough, "\(control) \(key)")
            }
        }
    }

    @Test func otherTransportKeysAreAlsoLeftToTheControl() {
        for control in Self.controls {
            #expect(KeyRouting.decision(for: .b, focus: control, sheetOpen: false) == .passThrough)
            #expect(KeyRouting.decision(for: .deleteKey, focus: control, sheetOpen: false) == .passThrough)
            #expect(KeyRouting.decision(for: .other, focus: control, sheetOpen: false) == .passThrough)
        }
    }

    @Test func escapeFromAFocusedControlReturnsFocusToTheShow() {
        for control in Self.controls {
            #expect(KeyRouting.decision(for: .escape, focus: control, sheetOpen: false) == .focusShow, "\(control)")
            #expect(KeyRouting.decision(for: .escape, focus: control, sheetOpen: false, shiftDown: true) == .focusShow)
        }
    }

    @Test func withNothingOrTheSlideGridFocusedTheTransportKeysDriveTheShow() {
        for focus in [FocusedElement.none, .slideGrid] {
            #expect(KeyRouting.decision(for: .space, focus: focus, sheetOpen: false) == .transport(.next))
            #expect(KeyRouting.decision(for: .returnKey, focus: focus, sheetOpen: false) == .transport(.goLive))
            // FIX-I item 2, owner: "moving left / right button will move the selection but hit enter will bring the current live".
            #expect(KeyRouting.decision(for: .rightArrow, focus: focus, sheetOpen: false) == .moveSelection(.right))
            #expect(KeyRouting.decision(for: .leftArrow, focus: focus, sheetOpen: false) == .moveSelection(.left))
            #expect(KeyRouting.decision(for: .escape, focus: focus, sheetOpen: false) == .transport(.clear))
            #expect(KeyRouting.decision(for: .escape, focus: focus, sheetOpen: false, shiftDown: true) == .transport(.clearAll))
            #expect(KeyRouting.decision(for: .b, focus: focus, sheetOpen: false) == .transport(.blackout))
            #expect(KeyRouting.decision(for: .space, focus: focus, sheetOpen: false, isRepeat: true) == .ignore)
        }
    }

    @Test func textInputsKeepEveryKeyAsBeforeAndTheSearchFieldStillLeavesOnEscape() {
        for key in Self.keys { #expect(KeyRouting.decision(for: key, focus: .textInput, sheetOpen: false) == .passThrough, "\(key)") }
        #expect(KeyRouting.decision(for: .escape, focus: .textInput, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .escape, focus: .searchField, sheetOpen: false) == .leaveSearch)
        #expect(KeyRouting.decision(for: .space, focus: .searchField, sheetOpen: false) == .passThrough)
    }

    @Test func aSheetOrACommandKeyPassesEverythingThrough() {
        for focus in Self.controls + [.none, .slideGrid, .textInput, .searchField] {
            for key in Self.keys + [.escape] {
                #expect(KeyRouting.decision(for: key, focus: focus, sheetOpen: true) == .passThrough, "\(focus) \(key)")
                #expect(KeyRouting.decision(for: key, focus: focus, sheetOpen: false, commandModifierDown: true) == .passThrough, "\(focus) \(key)")
            }
        }
    }

    @Test func aHeldKeyOnAControlIsLeftToTheControl() {
        #expect(KeyRouting.decision(for: .space, focus: .toggle, sheetOpen: false, isRepeat: true) == .passThrough)
        #expect(KeyRouting.decision(for: .rightArrow, focus: .slider, sheetOpen: false, isRepeat: true) == .passThrough)     // a slider is held to slide
    }

    @Test func theOldDecisionStillAgreesWithTheNewOneWhereTheyOverlap() {
        for key in Self.keys + [.escape] {
            #expect(KeyRouting.decision(for: key, textInputFocused: false, sheetOpen: false) == KeyRouting.decision(for: key, focus: .none, sheetOpen: false))
            #expect(KeyRouting.decision(for: key, textInputFocused: true, sheetOpen: false) == KeyRouting.decision(for: key, focus: .textInput, sheetOpen: false))
        }
    }

    @Test func appKitControlsAreClassifiedByKind() {
        #expect(FocusedElement.appKit(.checkbox) == .checkbox && FocusedElement.appKit(.switchButton) == .toggle)
        #expect(FocusedElement.appKit(.pushButton) == .button && FocusedElement.appKit(.radioButton) == .button)
        #expect(FocusedElement.appKit(.segmentedControl) == .segmented && FocusedElement.appKit(.slider) == .slider)
        #expect(FocusedElement.appKit(.popUpButton) == .popUp && FocusedElement.appKit(.tabView) == .tab)
        #expect(FocusedElement.appKit(.textInput) == .textInput && FocusedElement.appKit(.other) == .none)
    }
}
