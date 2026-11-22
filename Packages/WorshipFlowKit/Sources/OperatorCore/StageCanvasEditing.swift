// UI-005e / FIX-K: the pure rules behind pointer and keyboard editing on the Stage canvas: which element or handle a point picks,
// what a move or a resize from each of the eight handles does to a frame, the keyboard nudge, and the one write (with one undo step)
// that ends a drag. Foundation and Domain only; the view in `App/Sources/StageCanvasView.swift` only forwards pointer events here.
import Foundation
import Domain

/// The eight handles of a selected box.
public enum StageHandle: CaseIterable, Sendable, Equatable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    /// Where the handle sits on the box: 0 left or top, 0.5 middle, 1 right or bottom.
    public var anchor: (x: Double, y: Double) {
        switch self {
        case .topLeft: (0, 0)
        case .top: (0.5, 0)
        case .topRight: (1, 0)
        case .left: (0, 0.5)
        case .right: (1, 0.5)
        case .bottomLeft: (0, 1)
        case .bottom: (0.5, 1)
        case .bottomRight: (1, 1)
        }
    }
    public var movesLeft: Bool { anchor.x == 0 }
    public var movesRight: Bool { anchor.x == 1 }
    public var movesTop: Bool { anchor.y == 0 }
    public var movesBottom: Bool { anchor.y == 1 }
}

/// What a point on the canvas picks.
public enum StageCanvasHit: Equatable, Sendable {
    case handle(UUID, StageHandle)
    case element(UUID)
    case none
}

public enum StageCanvasEditing {
    /// The grab area of a handle, in points, centred on the handle (the drawn square is 8 pt).
    public static let handleGrab: Double = 16
    /// A handle's centre is this far inside the box's own edge, so the drawn square stays inside the box.
    public static let handleInset: Double = 1

    // MARK: Hit testing

    /// The centre of a handle in canvas points.
    public static func handleCenter(_ handle: StageHandle, frame: NormalizedRect, canvasWidth: Double, canvasHeight: Double) -> (x: Double, y: Double) {
        let w = frame.width * canvasWidth, h = frame.height * canvasHeight
        return (frame.x * canvasWidth + handleInset + handle.anchor.x * (w - 2 * handleInset),
                frame.y * canvasHeight + handleInset + handle.anchor.y * (h - 2 * handleInset))
    }

    /// What the point (canvas points, top left origin) picks. The selected element's handles come first when the layout can be edited (the nearest
    /// handle when several overlap on a small box); then the element whose box contains the point, the smallest box when boxes overlap (so a small
    /// clock inside a large lyric box can be picked), the later one on a tie.
    public static func hit(x: Double, y: Double, canvasWidth: Double, canvasHeight: Double,
                           elements: [(id: UUID, frame: NormalizedRect)], selected: UUID?, editable: Bool) -> StageCanvasHit {
        if editable, let selected, let element = elements.first(where: { $0.id == selected }) {
            var best: (handle: StageHandle, distance: Double)?
            for handle in StageHandle.allCases {
                let c = handleCenter(handle, frame: element.frame, canvasWidth: canvasWidth, canvasHeight: canvasHeight)
                guard abs(x - c.x) <= handleGrab / 2, abs(y - c.y) <= handleGrab / 2 else { continue }
                let d = (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)
                if best == nil || d < best!.distance { best = (handle, d) }
            }
            if let best { return .handle(selected, best.handle) }
        }
        var found: (id: UUID, area: Double)?
        for element in elements {
            let f = element.frame
            guard x >= f.x * canvasWidth, x <= (f.x + f.width) * canvasWidth, y >= f.y * canvasHeight, y <= (f.y + f.height) * canvasHeight else { continue }
            let area = f.width * f.height
            if found == nil || area <= found!.area { found = (element.id, area) }
        }
        return found.map { .element($0.id) } ?? .none
    }

    // MARK: Frames

    private static func clamp(_ v: Double, _ low: Double, _ high: Double) -> Double { v.isNaN ? low : min(high, max(low, v)) }

    /// The frame after moving by a fraction of the screen; stays on screen.
    public static func moved(_ start: NormalizedRect, dx: Double, dy: Double) -> NormalizedRect {
        NormalizedRect(x: clamp(start.x + dx, 0, 1 - start.width), y: clamp(start.y + dy, 0, 1 - start.height), width: start.width, height: start.height)
    }

    /// The frame after dragging `handle` by a fraction of the screen from `start`: only the edges the handle moves change; not smaller than
    /// `StageElement.minimumSize`, not off screen.
    public static func resized(_ start: NormalizedRect, handle: StageHandle, dx: Double, dy: Double) -> NormalizedRect {
        let minimum = StageElement.minimumSize
        var left = start.x, right = start.x + start.width, top = start.y, bottom = start.y + start.height
        if handle.movesLeft { left = clamp(left + dx, 0, right - minimum) }
        if handle.movesRight { right = clamp(right + dx, left + minimum, 1) }
        if handle.movesTop { top = clamp(top + dy, 0, bottom - minimum) }
        if handle.movesBottom { bottom = clamp(bottom + dy, top + minimum, 1) }
        return NormalizedRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// The frame after an arrow key: `points` (1, or 10 with Shift) canvas points in the direction (-1, 0, 1), as a fraction of the canvas.
    public static func nudged(_ frame: NormalizedRect, directionX: Int, directionY: Int, points: Double, canvasWidth: Double, canvasHeight: Double) -> NormalizedRect {
        guard canvasWidth > 0, canvasHeight > 0 else { return frame }
        return moved(frame, dx: Double(directionX) * points / canvasWidth, dy: Double(directionY) * points / canvasHeight)
    }

    /// 1 point, 10 with Shift.
    public static func nudgeDistance(shift: Bool) -> Double { shift ? 10 : 1 }

    // MARK: One drag, one write

    /// A pointer drag on one element, held in the view until the pointer is released. It touches no model: `finish` returns the two frames the
    /// view then writes once, or nil when nothing moved.
    public struct Drag: Equatable, Sendable {
        public enum Mode: Equatable, Sendable { case move, resize(StageHandle) }
        public let elementID: UUID
        public let mode: Mode
        public let start: NormalizedRect
        public private(set) var current: NormalizedRect

        public init(elementID: UUID, mode: Mode, start: NormalizedRect) {
            self.elementID = elementID; self.mode = mode; self.start = start; self.current = start
        }

        /// The pointer is `dx`, `dy` (fractions of the canvas) from where it went down.
        public mutating func update(dx: Double, dy: Double) {
            switch mode {
            case .move: current = StageCanvasEditing.moved(start, dx: dx, dy: dy)
            case .resize(let handle): current = StageCanvasEditing.resized(start, handle: handle, dx: dx, dy: dy)
            }
        }

        public func finish() -> (from: NormalizedRect, to: NormalizedRect)? { current == start ? nil : (start, current) }
    }

    /// Writes `to` once, and registers one undo step that restores `from` (and, undone, one redo step). A frame that did not change writes nothing,
    /// and the built-in layout is never written.
    @MainActor public static func commit(stage: StageModel, layoutID: UUID, elementID: UUID, from: NormalizedRect, to: NormalizedRect, undoManager: UndoManager?) {
        // FIX-P item 3: an element that is not in that layout writes nothing and registers no undo step (an undo step that restores nothing).
        guard from != to, stage.isEditable(layoutID), stage.layout(withID: layoutID)?.elements.contains(where: { $0.id == elementID }) == true else { return }
        stage.setFrame(elementID, in: layoutID, x: to.x, y: to.y, width: to.width, height: to.height)
        undoManager?.registerUndo(withTarget: stage) { stage in
            MainActor.assumeIsolated { commit(stage: stage, layoutID: layoutID, elementID: elementID, from: to, to: from, undoManager: undoManager) }
        }
        undoManager?.setActionName("Move or resize element")
    }

    // MARK: Selection (FIX-P item 5)

    /// The selection, only if that element is in the layout; a box that is not there (the layout was switched, the box was removed) is no selection.
    public static func validSelection(_ selection: UUID?, in elementIDs: [UUID]) -> UUID? {
        guard let selection, elementIDs.contains(selection) else { return nil }
        return selection
    }

    /// Whether the canvas takes the arrow keys: an editable layout with a selected box that is really in it. A stale selection takes none, so the arrows
    /// move the slide selection as if nothing were selected.
    public static func takesArrows(editable: Bool, selection: UUID?, elementIDs: [UUID]) -> Bool {
        editable && validSelection(selection, in: elementIDs) != nil
    }
}

/// FIX-P item 6 (L1): a run of nudges ends after a quiet period, which must be longer than the system's "Delay Until Repeat": between the first
/// arrow press and its first auto-repeat nothing arrives for that long, and a shorter period would end the run, then start a second one.
public enum NudgeTiming {
    public static let margin: TimeInterval = 0.25
    public static func quietPeriod(keyRepeatDelay: TimeInterval, floor: TimeInterval) -> TimeInterval {
        guard keyRepeatDelay.isFinite, keyRepeatDelay > 0 else { return floor }
        return max(floor, keyRepeatDelay + margin)
    }
}
