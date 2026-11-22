// FIX-N items 6 and 9: the Stage canvas's pointer state. A press, its moves and its release are one drag and one write. A drag that SwiftUI never
// ended (the window resigned key, the view went, the layout changed) must not leave the canvas "pressed": the view ends it, once, and the next press works.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@Suite struct FIXN_StagePointerTests {
    let id = UUID()
    let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.3, height: 0.2)

    @Test func aPressMovesAndReleaseIsOneCommit() {
        var s = StagePointerSession()
        #expect(!s.pressed)
        let first = s.press()
        let second = s.press()
        #expect(first)
        #expect(!second, "the later events of the same press are not a new press")
        s.begin(StageCanvasEditing.Drag(elementID: id, mode: .move, start: start))
        s.update(dx: 0.1, dy: 0.0)
        #expect(abs((s.drag?.current.x ?? 0) - 0.3) < 1e-12)
        let commit = s.finish()
        #expect(commit?.from == start && abs((commit?.to.x ?? 0) - 0.3) < 1e-12 && commit?.elementID == id)
        #expect(!s.pressed && s.drag == nil)
    }

    @Test func aPressThatDoesNotMoveCommitsNothing() {
        var s = StagePointerSession()
        _ = s.press()
        s.begin(StageCanvasEditing.Drag(elementID: id, mode: .move, start: start))
        let none = s.finish()
        #expect(none == nil)
        #expect(!s.pressed)
    }

    @Test func aDragThatWasInterruptedIsEndedOnceAndTheNextPressWorks() {
        var s = StagePointerSession()
        _ = s.press()
        s.begin(StageCanvasEditing.Drag(elementID: id, mode: .move, start: start))
        s.update(dx: 0.0, dy: 0.2)
        let first = s.finish()        // the view calls this when the window resigns key, the view disappears or the layout changes
        #expect(first != nil && abs((first?.to.y ?? 0) - 0.4) < 1e-12)
        let second = s.finish()
        #expect(second == nil, "SwiftUI's own end, if it does come, writes nothing more")
        #expect(!s.pressed)
        let again = s.press()
        #expect(again, "a stuck pressed state would swallow this press")
    }

    @Test func aPressOnEmptyCanvasHasNoDragAndStillEnds() {
        var s = StagePointerSession()
        _ = s.press()
        s.begin(nil)
        s.update(dx: 0.3, dy: 0.3)
        let none = s.finish()
        #expect(none == nil)
        #expect(!s.pressed)
    }
}
