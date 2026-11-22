// FIX-I item 1: "Previous / Next with keyboard buttons doesn't work". The cause, proved in the running app: SwiftUI's `isFocused` environment
// value is inherited by every view under a focused `.focusable()` container, so the pop-up and the buttons in the centre column
// (inside the slide grid's focusable container) all reported "I have focus" whenever the slide grid had it, and the key router then
// believed a control owned every key. These tests cover the rule that replaces it: a control's report counts only while the slide
// grid itself does not have focus, each control is tracked by its own identity, and nothing can stay stuck.
import Foundation
import Testing
@testable import OperatorCore

@Suite struct FIXI_ControlFocusTests {
    /// What the app showed after a click in the media bin: the slide grid took focus back and three buttons and a pop-up under it all
    /// reported true at once.
    @Test func controlsUnderTheFocusedSlideGridDoNotOwnTheKeys() {
        var tracker = ControlFocusTracker()
        for kind: FocusedElement in [.button, .button, .button, .popUp] { tracker.report(id: UUID(), kind: kind, focused: true) }
        #expect(tracker.current(gridHasFocus: true) == nil)
        for key: KeyboardKey in [.rightArrow, .leftArrow, .space, .returnKey] {
            let focus = tracker.current(gridHasFocus: true) ?? .none
            #expect(KeyRouting.decision(for: key, focus: focus, sheetOpen: false) != .passThrough, "\(key)")
        }
    }

    @Test func aControlThatReallyHasFocusOwnsTheKeysWhileTheGridDoesNot() {
        var tracker = ControlFocusTracker()
        let slider = UUID()
        tracker.report(id: slider, kind: .slider, focused: true)
        #expect(tracker.current(gridHasFocus: false) == .slider)
        #expect(KeyRouting.decision(for: .rightArrow, focus: tracker.current(gridHasFocus: false) ?? .none, sheetOpen: false) == .passThrough)
    }

    @Test func reportsAreTrackedPerControlSoNothingStaysStuck() {
        var tracker = ControlFocusTracker()
        let a = UUID(), b = UUID(), c = UUID()
        tracker.report(id: a, kind: .popUp, focused: true)
        tracker.report(id: b, kind: .button, focused: true)
        tracker.report(id: c, kind: .button, focused: true)
        // The old single-slot record ended on the last kind written and was only cleared by that kind's own "false".
        tracker.report(id: c, kind: .button, focused: false)
        tracker.report(id: b, kind: .button, focused: false)
        #expect(tracker.current(gridHasFocus: false) == .popUp)
        tracker.report(id: a, kind: .popUp, focused: false)
        #expect(tracker.current(gridHasFocus: false) == nil)
    }

    @Test func aControlThatLeavesTheScreenIsForgotten() {
        var tracker = ControlFocusTracker()
        let id = UUID()
        tracker.report(id: id, kind: .toggle, focused: true)
        tracker.remove(id: id)
        #expect(tracker.current(gridHasFocus: false) == nil)
    }

    @Test func escapeClearsEveryReport() {
        var tracker = ControlFocusTracker()
        tracker.report(id: UUID(), kind: .segmented, focused: true)
        tracker.report(id: UUID(), kind: .tab, focused: true)
        tracker.clear()
        #expect(tracker.current(gridHasFocus: false) == nil)
    }

    @Test func theNewestReportWinsWhenSeveralControlsClaimFocus() {
        var tracker = ControlFocusTracker()
        tracker.report(id: UUID(), kind: .button, focused: true)
        tracker.report(id: UUID(), kind: .slider, focused: true)
        #expect(tracker.current(gridHasFocus: false) == .slider)
    }
}
