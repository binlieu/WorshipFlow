// FIX-N item 5 (UI-005e): holding an arrow key on the Stage canvas wrote, published and recorded an undo step about 30 times a second. Nudges now move a
// transient frame and are committed once: when the key is released, or after a short quiet period (an injected clock), as one undo step per run.
// A stage screen updates once per commit. Item 8: the run also ends when the selection changes or another edit happens.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
final class NudgeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@Suite @MainActor struct FIXN_StageNudgeTests {
    let W = 1000.0, H = 500.0
    let start = NormalizedRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)

    private func make(quiet: TimeInterval = 0.5) -> (StageNudgeSession, NudgeClock, Box) {
        let clock = NudgeClock()
        let box = Box()
        let session = StageNudgeSession(quietPeriod: quiet, autoTick: false, clock: { clock.now }) { box.commits.append($0) }
        return (session, clock, box)
    }
    @MainActor final class Box { var commits: [StageNudgeSession.Commit] = [] }

    @Test func aHeldKeyMovesTheTransientFrameOnlyAndIsCommittedOnceOnRelease() {
        let (session, clock, box) = make()
        let id = UUID()
        for _ in 0..<30 { clock.advance(0.03); session.nudge(elementID: id, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H) }
        #expect(box.commits.isEmpty)
        let shown = try? #require(session.transientFrame(for: id))
        #expect(abs((shown?.x ?? 0) - (0.2 + 30.0 / W)) < 1e-9)
        #expect(session.transientFrame(for: UUID()) == nil)
        session.keyReleased()
        #expect(box.commits.count == 1)
        #expect(box.commits.first?.from == start)
        #expect(abs((box.commits.first?.to.x ?? 0) - (0.2 + 30.0 / W)) < 1e-9)
        #expect(session.transientFrame(for: id) == nil)
        session.keyReleased()
        #expect(box.commits.count == 1, "a second release has nothing to commit")
    }

    @Test func aQuietPeriodCommitsTheRunAndTheNextNudgeStartsANewOne() {
        let (session, clock, box) = make(quiet: 0.5)
        let id = UUID()
        session.nudge(elementID: id, stored: start, directionX: 0, directionY: 1, shift: true, canvasWidth: W, canvasHeight: H)
        clock.advance(0.4); session.tick()
        #expect(box.commits.isEmpty, "still inside the quiet period")
        session.nudge(elementID: id, stored: start, directionX: 0, directionY: 1, shift: true, canvasWidth: W, canvasHeight: H)
        clock.advance(0.4); session.tick()
        #expect(box.commits.isEmpty, "a nudge restarts the quiet period")
        clock.advance(0.2); session.tick()
        #expect(box.commits.count == 1)
        #expect(abs((box.commits[0].to.y) - (0.2 + 20.0 / H)) < 1e-9, "two Shift nudges of ten points")
        // The stored frame has moved by now; the next run starts from it.
        let moved = box.commits[0].to
        session.nudge(elementID: id, stored: moved, directionX: -1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H)
        session.keyReleased()
        #expect(box.commits.count == 2 && box.commits[1].from == moved)
    }

    @Test func aRunThatEndsWhereItStartedCommitsNothing() {
        let (session, _, box) = make()
        let id = UUID()
        session.nudge(elementID: id, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H)
        session.nudge(elementID: id, stored: start, directionX: -1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H)
        session.keyReleased()
        #expect(box.commits.isEmpty)
    }

    @Test func aNudgeOnAnotherElementEndsTheRunOfTheFirst() {
        let (session, _, box) = make()
        let a = UUID(), b = UUID()
        session.nudge(elementID: a, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H)
        session.nudge(elementID: b, stored: start, directionX: 0, directionY: 1, shift: false, canvasWidth: W, canvasHeight: H)
        #expect(box.commits.count == 1 && box.commits[0].elementID == a)
        session.flush()
        #expect(box.commits.count == 2 && box.commits[1].elementID == b)
    }

    @Test func aSelectionChangeOrAnotherEditEndsTheRun() {
        let (session, _, box) = make()
        let id = UUID()
        session.nudge(elementID: id, stored: start, directionX: 1, directionY: 0, shift: false, canvasWidth: W, canvasHeight: H)
        session.flush()          // what the view calls when the selection changes, the layout changes or the view goes
        #expect(box.commits.count == 1)
        session.flush()
        #expect(box.commits.count == 1)
    }

    @Test func theFrameStaysOnTheCanvasAtTheEdge() {
        let (session, _, box) = make()
        let id = UUID()
        let edge = NormalizedRect(x: 0.89, y: 0.2, width: 0.1, height: 0.3)
        for _ in 0..<50 { session.nudge(elementID: id, stored: edge, directionX: 1, directionY: 0, shift: true, canvasWidth: W, canvasHeight: H) }
        session.keyReleased()
        #expect(abs((box.commits.first?.to.x ?? 0) - 0.9) < 1e-9)
    }

    // MARK: Through the real model: one write, one undo step

    @Test func thirtyNudgesWriteOnceAndUndoInOneStep() async throws {
        let model = StageModel(store: try LibraryStore.inMemory())
        await model.load()
        let layout = try #require(model.createLayout(name: "Mine"))
        let element = layout.elements[0]
        var writes = 0
        model.onChange = { writes += 1 }
        let undo = UndoManager()
        undo.groupsByEvent = false
        let clock = NudgeClock()
        let session = StageNudgeSession(quietPeriod: 0.5, autoTick: false, clock: { clock.now }) { c in
            StageCanvasEditing.commit(stage: model, layoutID: layout.id, elementID: c.elementID, from: c.from, to: c.to, undoManager: undo)
        }
        let before = element.frame
        undo.beginUndoGrouping()
        for _ in 0..<30 {
            clock.advance(0.03)
            session.nudge(elementID: element.id, stored: model.layout(withID: layout.id)!.elements[0].frame, directionX: 0, directionY: 1, shift: false, canvasWidth: 1000, canvasHeight: 500)
        }
        #expect(writes == 0, "nothing is written while the key is held")
        session.keyReleased()
        undo.endUndoGrouping()
        #expect(writes == 1)
        #expect(abs((model.layout(withID: layout.id)?.elements[0].frame.y ?? 0) - (before.y + 30.0 / 500)) < 1e-9)
        undo.undo()
        #expect(model.layout(withID: layout.id)?.elements[0].frame == before)
        #expect(!undo.canUndo)
    }
}
