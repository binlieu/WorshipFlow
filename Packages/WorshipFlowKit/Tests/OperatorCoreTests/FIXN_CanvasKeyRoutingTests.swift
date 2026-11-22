// FIX-N item 1 (FIX-K, UI-005e): a click on a Stage canvas box made the canvas's key view report itself to the router as a slider, and a
// slider passes every key but Escape to the control, so Space, Return and B did nothing until Escape. The canvas is now its own focus kind:
// it takes only the arrow keys, and only while a box is selected; every other key is routed exactly as if the slide grid had focus.
import Foundation
import Testing
@testable import OperatorCore

@Suite struct FIXN_CanvasKeyRoutingTests {
    static let arrows: [KeyboardKey] = [.leftArrow, .rightArrow, .upArrow, .downArrow]
    static let allKeys: [KeyboardKey] = [.returnKey, .keypadEnter, .space, .leftArrow, .rightArrow, .upArrow, .downArrow, .escape, .deleteKey, .b, .other]
    static let nonArrows = allKeys.filter { !arrows.contains($0) }

    @Test func aCanvasWithABoxSelectedTakesTheArrowKeysWithAndWithoutShift() {
        for key in Self.arrows {
            for shift in [false, true] {
                #expect(KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: true, sheetOpen: false, shiftDown: shift) == .passThrough, "\(key) shift \(shift)")
            }
        }
    }

    @Test func aHeldArrowStillReachesTheCanvas() {
        for key in Self.arrows {
            #expect(KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: true, sheetOpen: false, isRepeat: true) == .passThrough, "\(key)")
        }
    }

    @Test func aCanvasWithNothingSelectedLeavesTheArrowsToTheSlideSelection() {
        #expect(KeyRouting.decision(for: .rightArrow, focus: .canvas, canvasHasSelection: false, sheetOpen: false) == .moveSelection(.right))
        #expect(KeyRouting.decision(for: .leftArrow, focus: .canvas, canvasHasSelection: false, sheetOpen: false) == .moveSelection(.left))
        #expect(KeyRouting.decision(for: .downArrow, focus: .canvas, canvasHasSelection: false, sheetOpen: false) == .moveSelection(.down))
        #expect(KeyRouting.decision(for: .upArrow, focus: .canvas, canvasHasSelection: false, sheetOpen: false) == .moveSelection(.up))
    }

    @Test func everyOtherKeyIsRoutedExactlyAsIfTheSlideGridHadFocus() {
        for selected in [false, true] {
            for key in Self.nonArrows {
                for shift in [false, true] {
                    for isRepeat in [false, true] {
                        for section in [KeySection.slideGrid, .mediaBin] {
                            let canvas = KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: selected, section: section, sheetOpen: false, shiftDown: shift, isRepeat: isRepeat)
                            let grid = KeyRouting.decision(for: key, focus: .slideGrid, section: section, sheetOpen: false, shiftDown: shift, isRepeat: isRepeat)
                            #expect(canvas == grid, "\(key) shift \(shift) repeat \(isRepeat) section \(section) selected \(selected)")
                        }
                    }
                }
            }
        }
    }

    @Test func theShowsKeysAlwaysWorkWithTheCanvasFocused() {
        #expect(KeyRouting.decision(for: .space, focus: .canvas, canvasHasSelection: true, sheetOpen: false) == .transport(.next))
        #expect(KeyRouting.decision(for: .space, focus: .canvas, canvasHasSelection: true, sheetOpen: false, shiftDown: true) == .transport(.previous))
        #expect(KeyRouting.decision(for: .returnKey, focus: .canvas, canvasHasSelection: true, sheetOpen: false) == .transport(.goLive))
        #expect(KeyRouting.decision(for: .keypadEnter, focus: .canvas, canvasHasSelection: true, sheetOpen: false) == .transport(.goLive))
        #expect(KeyRouting.decision(for: .b, focus: .canvas, canvasHasSelection: true, sheetOpen: false) == .transport(.blackout))
        #expect(KeyRouting.decision(for: .escape, focus: .canvas, canvasHasSelection: true, sheetOpen: false) == .transport(.clear))
        #expect(KeyRouting.decision(for: .escape, focus: .canvas, canvasHasSelection: true, sheetOpen: false, shiftDown: true) == .transport(.clearAll))
    }

    @Test func aSheetOrACommandKeyStillKeepsEveryKeyOutOfTheShow() {
        for key in Self.allKeys {
            #expect(KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: true, sheetOpen: true) == .passThrough, "\(key)")
            #expect(KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: true, sheetOpen: false, commandModifierDown: true) == .passThrough, "\(key)")
        }
    }

    @Test func theCanvasIsNotAControlAndEscapeIsNotItsHandBack() {
        #expect(!FocusedElement.canvas.isControl)
        #expect(KeyRouting.decision(for: .escape, focus: .canvas, canvasHasSelection: true, sheetOpen: false) != .focusShow)
    }

    @Test func theTrackerHandsTheCanvasBackAsTheCanvasKind() {
        var tracker = ControlFocusTracker()
        let id = UUID()
        tracker.report(id: id, kind: .canvas, focused: true)
        #expect(tracker.current(gridHasFocus: false) == .canvas)
        tracker.report(id: id, kind: .canvas, focused: false)
        #expect(tracker.current(gridHasFocus: false) == nil)
    }
}

// FIX-N item 8: arrows nudge the selected box whenever the canvas was the last thing clicked, even if a button has keyboard focus since.
@Suite struct FIXN_CanvasLastClickedRoutingTests {
    @Test func aButtonToggleOrCheckboxDoesNotTakeTheArrowsFromTheSelectedBox() {
        for focus: FocusedElement in [.button, .toggle, .checkbox] {
            for (key, move): (KeyboardKey, SelectionMove) in [(.leftArrow, .left), (.rightArrow, .right), (.upArrow, .up), (.downArrow, .down)] {
                #expect(KeyRouting.decision(for: key, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false) == .nudgeCanvas(move), "\(focus) \(key)")
                #expect(KeyRouting.decision(for: key, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false, shiftDown: true, isRepeat: true) == .nudgeCanvas(move))
            }
        }
    }

    @Test func withoutALastClickOnTheCanvasOrASelectionTheControlKeepsItsKeys() {
        for focus: FocusedElement in [.button, .toggle, .checkbox] {
            #expect(KeyRouting.decision(for: .leftArrow, focus: focus, canvasHasSelection: true, canvasLastClicked: false, sheetOpen: false) == .passThrough)
            #expect(KeyRouting.decision(for: .leftArrow, focus: focus, canvasHasSelection: false, canvasLastClicked: true, sheetOpen: false) == .passThrough)
        }
    }

    @Test func controlsThatUseArrowsAndEveryOtherKeyAreUnchanged() {
        for focus: FocusedElement in [.slider, .segmented, .tab, .popUp] {
            #expect(KeyRouting.decision(for: .leftArrow, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false) == .passThrough, "\(focus)")
        }
        for focus: FocusedElement in [.button, .toggle, .checkbox] {
            #expect(KeyRouting.decision(for: .space, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false) == .passThrough)
            #expect(KeyRouting.decision(for: .returnKey, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false) == .passThrough)
            #expect(KeyRouting.decision(for: .escape, focus: focus, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: false) == .focusShow)
        }
    }

    @Test func aSheetStillKeepsEveryKeyOutOfTheCanvas() {
        #expect(KeyRouting.decision(for: .leftArrow, focus: .button, canvasHasSelection: true, canvasLastClicked: true, sheetOpen: true) == .passThrough)
    }
}
