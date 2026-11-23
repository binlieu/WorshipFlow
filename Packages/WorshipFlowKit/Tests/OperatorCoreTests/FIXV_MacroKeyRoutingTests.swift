// FIX-V item 1 (REVIEW-4 M5): a macro's function key is a routed command like every other show key. It ran before KeyRouting, so it fired with a
// button focused, in Edit and on the Stage canvas, and in other windows. These tests are on the pure routing function.
import Foundation
import Testing
@testable import OperatorCore

@Suite struct FIXV_MacroKeyRoutingTests {
    static let allFocus: [FocusedElement] = [.none, .slideGrid, .textInput, .searchField, .toggle, .checkbox, .segmented, .tab, .slider, .button, .popUp, .canvas]
    static let typing: Set<FocusedElement> = [.textInput, .searchField]

    private func route(_ focus: FocusedElement = .slideGrid, mode: WorkspaceMode = .show, key: CueFunctionKey = .f5, operatorWindow: Bool = true,
                       sheet: Bool = false, modal: Bool = false, command: Bool = false, shift: Bool = false, isRepeat: Bool = false,
                       selection: Bool = false) -> KeyDecision {
        KeyRouting.decision(for: .other, focus: focus, canvasHasSelection: selection, sheetOpen: sheet, commandModifierDown: command, shiftDown: shift,
                            isRepeat: isRepeat, macroKey: key, mode: mode, isOperatorWindow: operatorWindow, modalUp: modal)
    }

    @Test func aMacroKeyRunsInShowAndCuesForEveryFocusButTextFields() {
        for mode in [WorkspaceMode.show, .cues] {
            for focus in Self.allFocus {
                let expected: KeyDecision = Self.typing.contains(focus) ? .passThrough : .runMacro(.f5)
                #expect(route(focus, mode: mode) == expected, "\(mode) \(focus)")
            }
        }
    }

    @Test func aMacroKeyIsOffInEditStageScreensAndMedia() {
        for mode in [WorkspaceMode.edit, .stage, .screens, .media] {
            for focus in Self.allFocus {
                for selection in [false, true] {
                    #expect(route(focus, mode: mode, selection: selection) == .passThrough, "\(mode) \(focus) selection \(selection)")
                }
            }
        }
    }

    @Test func aMacroKeyNeverRunsInAnotherWindow() {
        for mode in WorkspaceMode.allCases { for focus in Self.allFocus { #expect(route(focus, mode: mode, operatorWindow: false) == .passThrough, "\(mode) \(focus)") } }
    }

    @Test func aSheetAnAlertAModifierShiftOrARepeatStopsIt() {
        for focus in Self.allFocus {
            #expect(route(focus, sheet: true) == .passThrough, "sheet \(focus)")
            #expect(route(focus, modal: true) == .passThrough, "modal \(focus)")
            #expect(route(focus, command: true) == .passThrough, "modifier \(focus)")
            #expect(route(focus, shift: true) == .passThrough, "shift \(focus)")
            #expect(route(focus, isRepeat: true) == .passThrough, "repeat \(focus)")
        }
    }

    @Test func everyFunctionKeyIsRouted() {
        for key in CueFunctionKey.allCases { #expect(route(key: key) == .runMacro(key)) }
    }

    @Test func aFocusedButtonDoesNotTakeAFunctionKeyButStillKeepsSpaceAndReturn() {
        #expect(route(.button) == .runMacro(.f5))
        #expect(KeyRouting.decision(for: .space, focus: .button, sheetOpen: false) == .passThrough)
        #expect(KeyRouting.decision(for: .returnKey, focus: .toggle, sheetOpen: false) == .passThrough)
    }

    @Test func theOtherKeysAreRoutedAsBefore() {
        for mode in WorkspaceMode.allCases {
            #expect(KeyRouting.decision(for: .space, focus: .slideGrid, sheetOpen: false, macroKey: nil, mode: mode, isOperatorWindow: true) == .transport(.next))
            #expect(KeyRouting.decision(for: .b, focus: .canvas, sheetOpen: false, macroKey: nil, mode: mode, isOperatorWindow: false) == .transport(.blackout))
        }
    }

    @Test func theModesThatRunMacroKeysAreShowAndCues() {
        #expect(WorkspaceMode.allCases.filter { KeyRouting.macroKeysWork(in: $0) } == [.show, .cues])
    }
}
