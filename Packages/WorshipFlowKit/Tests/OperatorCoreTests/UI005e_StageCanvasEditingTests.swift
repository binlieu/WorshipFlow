// UI-005e / FIX-K: hit testing, the eight handles, nudging and the one-write-one-undo drag on the Stage canvas.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@Suite struct UI005e_StageCanvasEditingTests {
    typealias E = StageCanvasEditing
    let W = 800.0, H = 450.0
    let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)

    func close(_ a: NormalizedRect, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Bool {
        abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9 && abs(a.width - w) < 1e-9 && abs(a.height - h) < 1e-9
    }

    // MARK: Hit testing

    @Test func aPointInsideABoxPicksIt() {
        let id = UUID()
        let hit = E.hit(x: 300, y: 150, canvasWidth: W, canvasHeight: H, elements: [(id, start)], selected: nil, editable: true)
        #expect(hit == .element(id))
        #expect(E.hit(x: 5, y: 5, canvasWidth: W, canvasHeight: H, elements: [(id, start)], selected: nil, editable: true) == .none)
    }

    @Test func overlappingBoxesPickTheSmallestAndALaterOneOnATie() {
        let big = UUID(), small = UUID(), same = UUID()
        let large = NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let inner = NormalizedRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let p = (x: 0.45 * W, y: 0.45 * H)
        #expect(E.hit(x: p.x, y: p.y, canvasWidth: W, canvasHeight: H, elements: [(big, large), (small, inner)], selected: nil, editable: true) == .element(small))
        #expect(E.hit(x: p.x, y: p.y, canvasWidth: W, canvasHeight: H, elements: [(small, inner), (big, large)], selected: nil, editable: true) == .element(small))
        #expect(E.hit(x: p.x, y: p.y, canvasWidth: W, canvasHeight: H, elements: [(small, inner), (same, inner)], selected: nil, editable: true) == .element(same))
    }

    @Test func theSelectedElementsHandlesWinOverBoxesAndOnlyWhenEditable() {
        let a = UUID(), b = UUID()
        let other = NormalizedRect(x: 0.55, y: 0.2, width: 0.4, height: 0.3)       // touches a's right edge area
        let c = E.handleCenter(.right, frame: start, canvasWidth: W, canvasHeight: H)
        let hit = E.hit(x: c.x, y: c.y, canvasWidth: W, canvasHeight: H, elements: [(a, start), (b, other)], selected: a, editable: true)
        #expect(hit == .handle(a, .right))
        let readOnly = E.hit(x: c.x, y: c.y, canvasWidth: W, canvasHeight: H, elements: [(a, start), (b, other)], selected: a, editable: false)
        #expect(readOnly != .handle(a, .right))
        // a handle sticks out of the box by half its grab area: still hit just outside the edge
        let corner = E.handleCenter(.bottomRight, frame: start, canvasWidth: W, canvasHeight: H)
        #expect(E.hit(x: corner.x + 6, y: corner.y + 6, canvasWidth: W, canvasHeight: H, elements: [(a, start)], selected: a, editable: true) == .handle(a, .bottomRight))
    }

    @Test func allEightHandlesAreHitAtTheirCentres() {
        let a = UUID()
        for handle in StageHandle.allCases {
            let c = E.handleCenter(handle, frame: start, canvasWidth: W, canvasHeight: H)
            #expect(E.hit(x: c.x, y: c.y, canvasWidth: W, canvasHeight: H, elements: [(a, start)], selected: a, editable: true) == .handle(a, handle))
        }
    }

    // MARK: Moving and the eight handles

    @Test func movingKeepsTheBoxOnScreen() {
        #expect(close(E.moved(start, dx: 0.1, dy: -0.05), 0.3, 0.15, 0.4, 0.3))
        #expect(close(E.moved(start, dx: 5, dy: 5), 0.6, 0.7, 0.4, 0.3))
        #expect(close(E.moved(start, dx: -5, dy: -5), 0, 0, 0.4, 0.3))
    }

    @Test func eachHandleMovesOnlyItsOwnEdges() {
        // dx 0.1, dy 0.05
        #expect(close(E.resized(start, handle: .topLeft, dx: 0.1, dy: 0.05), 0.3, 0.25, 0.3, 0.25))
        #expect(close(E.resized(start, handle: .top, dx: 0.1, dy: 0.05), 0.2, 0.25, 0.4, 0.25))
        #expect(close(E.resized(start, handle: .topRight, dx: 0.1, dy: 0.05), 0.2, 0.25, 0.5, 0.25))
        #expect(close(E.resized(start, handle: .left, dx: 0.1, dy: 0.05), 0.3, 0.2, 0.3, 0.3))
        #expect(close(E.resized(start, handle: .right, dx: 0.1, dy: 0.05), 0.2, 0.2, 0.5, 0.3))
        #expect(close(E.resized(start, handle: .bottomLeft, dx: 0.1, dy: 0.05), 0.3, 0.2, 0.3, 0.35))
        #expect(close(E.resized(start, handle: .bottom, dx: 0.1, dy: 0.05), 0.2, 0.2, 0.4, 0.35))
        #expect(close(E.resized(start, handle: .bottomRight, dx: 0.1, dy: 0.05), 0.2, 0.2, 0.5, 0.35))
    }

    @Test func aHandleCannotMakeTheBoxSmallerThanTheMinimumOrPushItOffScreen() {
        let m = StageElement.minimumSize
        // dragging the left edge far right stops at the minimum width with the right edge fixed
        #expect(close(E.resized(start, handle: .left, dx: 5, dy: 0), 0.6 - m, 0.2, m, 0.3))
        #expect(close(E.resized(start, handle: .right, dx: -5, dy: 0), 0.2, 0.2, m, 0.3))
        #expect(close(E.resized(start, handle: .top, dx: 0, dy: 5), 0.2, 0.5 - m, 0.4, m))
        #expect(close(E.resized(start, handle: .bottom, dx: 0, dy: -5), 0.2, 0.2, 0.4, m))
        // and not past the screen's edges
        #expect(close(E.resized(start, handle: .topLeft, dx: -5, dy: -5), 0, 0, 0.6, 0.5))
        #expect(close(E.resized(start, handle: .bottomRight, dx: 5, dy: 5), 0.2, 0.2, 0.8, 0.8))
    }

    @Test func nudgingMovesOnePointOrTenWithShiftAndStaysOnScreen() {
        #expect(E.nudgeDistance(shift: false) == 1)
        #expect(E.nudgeDistance(shift: true) == 10)
        let moved = E.nudged(start, directionX: 1, directionY: 0, points: 1, canvasWidth: W, canvasHeight: H)
        #expect(close(moved, 0.2 + 1 / 800, 0.2, 0.4, 0.3))
        let down = E.nudged(start, directionX: 0, directionY: 1, points: 10, canvasWidth: W, canvasHeight: H)
        #expect(close(down, 0.2, 0.2 + 10 / 450, 0.4, 0.3))
        let edge = E.nudged(NormalizedRect(x: 0, y: 0, width: 0.4, height: 0.3), directionX: -1, directionY: -1, points: 10, canvasWidth: W, canvasHeight: H)
        #expect(close(edge, 0, 0, 0.4, 0.3))
    }

    // MARK: A drag touches no model

    @Test func aDragFollowsThePointerAndFinishesWithTheTwoFrames() {
        var drag = E.Drag(elementID: UUID(), mode: .move, start: start)
        drag.update(dx: 0.1, dy: 0.1)
        #expect(close(drag.current, 0.3, 0.3, 0.4, 0.3))
        drag.update(dx: 0.05, dy: 0)
        #expect(close(drag.current, 0.25, 0.2, 0.4, 0.3))      // measured from where the pointer went down, not from the last step
        let done = drag.finish()
        #expect(done?.from == start)
        #expect(done.map { close($0.to, 0.25, 0.2, 0.4, 0.3) } == true)
        var resize = E.Drag(elementID: UUID(), mode: .resize(.bottomRight), start: start)
        resize.update(dx: 0.1, dy: 0.1)
        #expect(close(resize.current, 0.2, 0.2, 0.5, 0.4))
    }

    @Test func aDragThatEndsWhereItBeganHasNothingToWrite() {
        var drag = E.Drag(elementID: UUID(), mode: .move, start: start)
        #expect(drag.finish() == nil)
        drag.update(dx: 0.1, dy: 0)
        drag.update(dx: 0, dy: 0)
        #expect(drag.finish() == nil)
    }

    // MARK: One write and one undo step on release

    @MainActor func ready() async throws -> (StageModel, StageLayout, UUID) {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        let layout = try #require(model.createLayout(name: "Mine"))
        return (model, layout, layout.elements[0].id)
    }

    @MainActor @Test func releasingWritesOnceAndUndoRestoresInOneStep() async throws {
        let (model, layout, id) = try await ready()
        var writes = 0
        model.onChange = { writes += 1 }
        let undo = UndoManager()
        undo.groupsByEvent = false
        let from = layout.elements[0].frame
        let to = NormalizedRect(x: from.x + 0.02, y: 0.1, width: from.width, height: from.height)      // on screen: nothing to clamp
        undo.beginUndoGrouping()
        E.commit(stage: model, layoutID: layout.id, elementID: id, from: from, to: to, undoManager: undo)
        undo.endUndoGrouping()
        #expect(writes == 1)
        #expect(model.layout(withID: layout.id)?.elements[0].frame == to)
        #expect(undo.canUndo)
        undo.undo()
        #expect(writes == 2)
        #expect(model.layout(withID: layout.id)?.elements[0].frame == from)
        #expect(!undo.canUndo)
        #expect(undo.canRedo)
        undo.redo()
        #expect(model.layout(withID: layout.id)?.elements[0].frame == to)
    }

    @MainActor @Test func aCommitWithAnUnchangedFrameWritesNothingAndRegistersNoUndo() async throws {
        let (model, layout, id) = try await ready()
        var writes = 0
        model.onChange = { writes += 1 }
        let undo = UndoManager()
        let frame = layout.elements[0].frame
        E.commit(stage: model, layoutID: layout.id, elementID: id, from: frame, to: frame, undoManager: undo)
        #expect(writes == 0)
        #expect(!undo.canUndo)
    }

    @MainActor @Test func theBuiltInLayoutIsNeverWritten() async throws {
        let (model, _, _) = try await ready()
        var writes = 0
        model.onChange = { writes += 1 }
        let undo = UndoManager()
        let first = StageLayout.standard.elements[0]
        var moved = first.frame; moved.x += 0.1
        E.commit(stage: model, layoutID: StageLayout.standardID, elementID: first.id, from: first.frame, to: moved, undoManager: undo)
        #expect(writes == 0)
        #expect(!undo.canUndo)
        #expect(model.layout(withID: StageLayout.standardID)?.elements[0].frame == first.frame)
    }

    // MARK: The attached lines follow their element (FIX-J made them relative)

    @Test func theSecondLanguageLineAndTheNextLabelMoveAndScaleWithTheirElement() {
        let base = StageLayout.standard
        func layers(_ layout: StageLayout) -> [TextLayer] {
            StageEditing.sampleScene(layout: layout, timers: [], now: 0, timeOfDayText: "9:14").textLayers
        }
        var moved = base
        for i in moved.elements.indices where moved.elements[i].kind == .currentSlide || moved.elements[i].kind == .nextSlide {
            let f = moved.elements[i].frame
            moved.elements[i].frame = NormalizedRect(x: f.x + 0.05, y: f.y - 0.02, width: f.width, height: f.height)
        }
        let before = layers(base), after = layers(moved)
        #expect(before.count == after.count)
        // every lyric-block layer (current, its second language, the NEXT label, the next line) shifted by the same amount
        var shifted = 0
        for (b, a) in zip(before, after) where abs(a.frame.x - b.frame.x - 0.05) < 1e-9 && abs(a.frame.y - b.frame.y + 0.02) < 1e-9 { shifted += 1 }
        #expect(shifted >= 4)
    }
}
