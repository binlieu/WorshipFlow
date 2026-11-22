// FIX-P items 3 to 6 (review of FIX-N, M3, M4, M5, L1, L2; L3 did not reproduce, see the report): a run cut short by a layout change is written to the layout it began on and never leaves an
// empty undo step; a drag ended early does not start again from the same press; a stale selection takes no arrow keys; the nudge quiet period follows the
// system key-repeat delay; Tab ends "the canvas was clicked last".
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite @MainActor struct FIXP_CanvasTests {
    let W = 1000.0, H = 500.0
    let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)

    @MainActor func ready() async throws -> (StageModel, StageLayout, StageLayout) {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        let one = try #require(model.createLayout(name: "One"))
        let two = try #require(model.createLayout(name: "Two"))
        return (model, one, two)
    }

    // MARK: M3

    @Test func aCommitForAnElementThatIsNotInTheLayoutWritesNothingAndRegistersNoUndoStep() async throws {
        let (model, one, two) = try await ready()
        let undo = UndoManager()
        var writes = 0
        model.onChange = { writes += 1 }
        let from = one.elements[0].frame
        let to = NormalizedRect(x: from.x + 0.02, y: from.y, width: from.width, height: from.height)
        StageCanvasEditing.commit(stage: model, layoutID: two.id, elementID: one.elements[0].id, from: from, to: to, undoManager: undo)
        #expect(writes == 0)
        #expect(!undo.canUndo, "an undo step that restores nothing must not be registered")
        #expect(model.layout(withID: one.id)?.elements[0].frame == from)
    }

    @Test func aDragCutShortByALayoutChangeIsWrittenToTheLayoutItBeganOn() async throws {
        let (model, one, two) = try await ready()
        var s = StagePointerSession()
        _ = s.press()
        s.begin(.init(elementID: one.elements[0].id, mode: .move, start: one.elements[0].frame), layoutID: one.id)
        s.update(dx: 0.02, dy: 0)
        // the view now shows layout two; the commit must still name layout one
        let interrupted = s.interrupt()
        let commit = try #require(interrupted)
        #expect(commit.layoutID == one.id)
        let undo = UndoManager()
        StageCanvasEditing.commit(stage: model, layoutID: commit.layoutID ?? two.id, elementID: commit.elementID, from: commit.from, to: commit.to, undoManager: undo)
        #expect(model.layout(withID: one.id)?.elements[0].frame == commit.to)
        #expect(model.layout(withID: two.id)?.elements[0].frame == two.elements[0].frame)
        #expect(undo.canUndo)
    }

    @Test func aNudgeRunRemembersTheLayoutItOpenedOn() {
        var commits: [StageNudgeSession.Commit] = []
        let session = StageNudgeSession(autoTick: false, onCommit: { commits.append($0) })
        let a = UUID(), b = UUID(), element = UUID()
        session.nudge(elementID: element, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H, layoutID: a)
        session.nudge(elementID: element, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H, layoutID: b)      // the view moved on to layout b
        session.flush()
        #expect(commits.map(\.layoutID) == [a, b], "the first run is written to layout a, not to whichever layout the view shows when it ends")
    }

    // MARK: M4

    @Test func aPressThatWasEndedEarlyIsNotStartedAgainByTheSameGestures() {
        var s = StagePointerSession()
        let first = s.press(startedAt: 120, 80)
        #expect(first)
        s.begin(.init(elementID: UUID(), mode: .move, start: start), layoutID: UUID())
        s.update(dx: 0.05, dy: 0)
        let interrupted = s.interrupt()
        #expect(interrupted != nil)
        let again = s.press(startedAt: 120, 80)
        let andAgain = s.press(startedAt: 120, 80)
        #expect(!again && !andAgain, "the gesture is still being delivered: it must not move the box a second time")
        let ended = s.finish()
        #expect(ended == nil, "the gesture's own end writes nothing more")
        let next = s.press(startedAt: 120, 80)
        #expect(next, "and the next press works")
    }

    @Test func aNewPressElsewhereWorksEvenIfTheEndOfTheInterruptedOneNeverCame() {
        var s = StagePointerSession()
        let first = s.press(startedAt: 10, 10)
        #expect(first)
        s.begin(nil, layoutID: nil)
        _ = s.interrupt()
        let elsewhere = s.press(startedAt: 300, 200)
        #expect(elsewhere)
    }

    @Test func theOldFinishStillAllowsTheNextPress() {
        var s = StagePointerSession()
        _ = s.press()
        s.begin(.init(elementID: UUID(), mode: .move, start: start))
        s.update(dx: 0.1, dy: 0)
        let done = s.finish()
        #expect(done != nil)
        let next = s.press()
        #expect(next)
    }

    @Test func theEditCanvasPressGuardIgnoresAnInterruptedGestureUntilItsEnd() {
        var g = PressGuard()
        let p = PressGuard.Point(x: 5, y: 6)
        let e1 = g.event(startedAt: p), e2 = g.event(startedAt: p)
        #expect(e1 == .began && e2 == .continuing)
        g.interrupt()
        let e3 = g.event(startedAt: p), e4 = g.event(startedAt: p)
        #expect(e3 == .ignored && e4 == .ignored)
        g.ended()
        let e5 = g.event(startedAt: p)
        #expect(e5 == .began)
        var idle = PressGuard()
        idle.interrupt()                       // an interrupt with no press open changes nothing
        let e6 = idle.event(startedAt: .init(x: 1, y: 1))
        #expect(e6 == .began)
    }

    // MARK: M5

    @Test func aSelectionThatIsNotInTheLayoutTakesNoArrowKeys() {
        let a = UUID(), b = UUID()
        #expect(StageCanvasEditing.takesArrows(editable: true, selection: a, elementIDs: [a, b]))
        #expect(!StageCanvasEditing.takesArrows(editable: true, selection: UUID(), elementIDs: [a, b]))
        #expect(!StageCanvasEditing.takesArrows(editable: true, selection: nil, elementIDs: [a, b]))
        #expect(!StageCanvasEditing.takesArrows(editable: false, selection: a, elementIDs: [a, b]))
        #expect(StageCanvasEditing.validSelection(a, in: [a, b]) == a)
        #expect(StageCanvasEditing.validSelection(UUID(), in: [a, b]) == nil)
        #expect(StageCanvasEditing.validSelection(nil, in: [a]) == nil)
    }

    @Test func withAStaleSelectionTheArrowsMoveTheSlideSelectionAsIfNothingWereSelected() {
        let canvasTakes = StageCanvasEditing.takesArrows(editable: true, selection: UUID(), elementIDs: [UUID()])
        #expect(KeyRouting.decision(for: .rightArrow, focus: .canvas, canvasHasSelection: canvasTakes, sheetOpen: false) == .moveSelection(.right))
    }

    // MARK: L1

    @Test func theQuietPeriodIsLongerThanTheSystemKeyRepeatDelay() {
        for delay in [0.0, 0.25, 0.5, 1.0, 1.8, 2.0] {
            for floor in [0.6, 1.0] {
                let quiet = NudgeTiming.quietPeriod(keyRepeatDelay: delay, floor: floor)
                #expect(quiet > delay, "delay \(delay) floor \(floor)")
                #expect(quiet >= floor)
            }
        }
        #expect(NudgeTiming.quietPeriod(keyRepeatDelay: 0.2, floor: 0.6) == 0.6, "a short delay keeps the floor")
        #expect(NudgeTiming.quietPeriod(keyRepeatDelay: .nan, floor: 0.6) == 0.6)
        #expect(NudgeTiming.quietPeriod(keyRepeatDelay: -1, floor: 0.6) == 0.6)
    }

    // MARK: L2

    @Test func tabEndsTheCanvasWasClickedLastAndNoOtherKeyDoes() {
        #expect(KeyRouting.clearsCanvasClick(keyCode: 48))
        for code: UInt16 in [123, 124, 125, 126, 49, 36, 53, 11, 0] { #expect(!KeyRouting.clearsCanvasClick(keyCode: code)) }
        // with the click cleared, arrows on a radio group (a button to the router) are the group's own
        #expect(KeyRouting.decision(for: .downArrow, focus: .button, canvasHasSelection: true, canvasLastClicked: false, sheetOpen: false) == .passThrough)
    }
}
