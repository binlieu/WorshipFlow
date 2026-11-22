// FIX-N item 9: the canvases' key routing in every mode. Whatever mode shows, a canvas with a box selected takes the arrows and nothing else, and the
// show's keys (Next, Previous, Go Live, Blackout, Clear, Clear all) work; only Edit and Stage have a canvas to nudge.
import Testing
@testable import OperatorCore

@Suite struct FIXN_CanvasModesTests {
    @Test func onlyEditAndStageHaveACanvasToNudge() {
        for mode in WorkspaceMode.allCases {
            let nudges = CanvasArrows.hasSelection(mode: mode, editHasSelection: true, stageTakesArrows: true)
            #expect(nudges == (mode == .edit || mode == .stage), "\(mode)")
            #expect(!CanvasArrows.hasSelection(mode: mode, editHasSelection: false, stageTakesArrows: false), "\(mode)")
        }
        #expect(CanvasArrows.hasSelection(mode: .edit, editHasSelection: true, stageTakesArrows: false))
        #expect(!CanvasArrows.hasSelection(mode: .stage, editHasSelection: true, stageTakesArrows: false))
        #expect(CanvasArrows.hasSelection(mode: .stage, editHasSelection: false, stageTakesArrows: true))
    }

    @Test func theShowsKeysAreTheSameInEveryModeWithTheCanvasFocusedOrAButtonAfterACanvasClick() {
        let expected: [(KeyboardKey, Bool, KeyDecision)] = [
            (.space, false, .transport(.next)), (.space, true, .transport(.previous)), (.returnKey, false, .transport(.goLive)),
            (.b, false, .transport(.blackout)), (.escape, false, .transport(.clear)), (.escape, true, .transport(.clearAll)),
        ]
        for mode in WorkspaceMode.allCases {
            let hasSelection = CanvasArrows.hasSelection(mode: mode, editHasSelection: true, stageTakesArrows: true)
            for (key, shift, decision) in expected {
                #expect(KeyRouting.decision(for: key, focus: .canvas, canvasHasSelection: hasSelection, canvasLastClicked: true, sheetOpen: false, shiftDown: shift) == decision, "\(mode) \(key)")
                #expect(KeyRouting.decision(for: key, focus: .none, canvasHasSelection: hasSelection, canvasLastClicked: true, sheetOpen: false, shiftDown: shift) == decision, "\(mode) \(key)")
            }
        }
    }
}
