// UI-005e / FIX-K: the Stage canvas. The layout drawn by the compositor with sample content (16:9 on black with a shadow), over it a dashed
// 1 pt outline and a name for every element, the selected one solid 1.5 pt in the selection blue with eight handles.
//
// One pointer layer covers the whole canvas and does the hit testing itself (`StageCanvasEditing.hit`): earlier, each box carried its own
// tap and drag gestures under a canvas-wide tap that cleared the selection, and boxes could not be picked or moved. The layer picks at the
// press (a handle of the selected element first, then the smallest box under the point), follows the pointer in a local drag (the outline,
// the handles and the compositor picture are drawn from the dragged frame in the same frame; the model is not touched), and writes once on
// release, as one undo step. Arrow keys nudge the selected element 1 point (Shift 10) while the canvas has focus. The second-language line
// and the NEXT label are stored relative to their element (FIX-J), so they move and scale with it. A built-in layout draws the same but
// every press only selects.
import SwiftUI
import AppKit
import Domain
import OperatorCore

struct StageCanvas: View {
    let stage: StageModel
    let layout: StageLayout
    let editable: Bool
    @Binding var selection: UUID?
    @Environment(\.undoManager) private var undoManager
    /// FIX-N items 6 and 9: the pointer's state is a pure session; the view ends it on the gesture's end and whenever the drag is cut short.
    @State private var pointerState = StagePointerSession()
    @State private var size = CGSize(width: 820, height: 461.25)
    @State private var keys = StageKeyBox()
    /// FIX-N item 5: arrow-key nudges move a transient frame and are written once per run.
    @State private var nudges = StageNudgeSession(quietPeriod: NudgeTiming.quietPeriod(keyRepeatDelay: NSEvent.keyRepeatDelay, floor: 0.6))      // FIX-P item 6: longer than the system's delay until repeat

    /// The layout as drawn now: the dragged (or nudged) element at its transient frame, everything else as stored.
    private var shown: StageLayout {
        var copy = layout
        if let drag = pointerState.drag, let i = copy.elements.firstIndex(where: { $0.id == drag.elementID }) {
            copy.elements[i].frame = drag.current
        } else if let id = selection, let frame = nudges.transientFrame(for: id), let i = copy.elements.firstIndex(where: { $0.id == id }) {
            copy.elements[i].frame = frame
        }
        return copy
    }

    /// FIX-P item 5: only a selection that is really in this layout takes the arrow keys; a stale one leaves them to the slide selection.
    private var takesArrows: Bool { StageCanvasEditing.takesArrows(editable: editable, selection: selection, elementIDs: layout.elements.map(\.id)) }

    var body: some View {
        let layout = shown
        let _ = refreshHandlers()      // every pass leaves the handlers the app calls (and the nudges' write) holding THIS pass's layout, selection and undo manager
        ScenePreview(scene: stage.sampleScene(for: layout), width: 1280, cached: false, follow: pointerState.drag != nil || nudges.isOpen)
            .background(Color.black)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(layout.elements.enumerated()), id: \.element.id) { index, element in
                            StageElementOutline(stage: stage, element: element, index: index, canvas: geo.size, selected: selection == element.id)
                        }
                        if editable, let selected = layout.elements.first(where: { $0.id == selection }) {
                            ForEach(Array(StageHandle.allCases.enumerated()), id: \.offset) { index, handle in
                                let c = StageCanvasEditing.handleCenter(handle, frame: selected.frame, canvasWidth: geo.size.width, canvasHeight: geo.size.height)
                                StageHandleView().wfRect("st.cv.handle.\(index)", radius: 1).position(x: c.x, y: c.y).allowsHitTesting(false)
                            }
                        }
                        Color.clear.contentShape(Rectangle()).gesture(pointer(in: geo.size))
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .onAppear { size = geo.size }
                    .onChange(of: geo.size) { _, new in size = new }
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            .wfRect("st.cv")
            .background(StageKeyCatcher(box: keys, takesArrows: takesArrows, onArrow: { dx, dy, shift in nudge(dx: dx, dy: dy, shift: shift) },
                                        onRelease: { nudges.keyReleased() }))
            // FIX-N items 5, 6 and 8: a run of nudges and a drag end when the selection or the layout changes, the window resigns key or the view goes.
            .onChange(of: selection) { _, _ in nudges.flush() }
            .onChange(of: editable) { _, _ in nudges.flush() }
            .onChange(of: layout.id) { _, _ in endEverything(); clearStaleSelection() }
            .onChange(of: layout.elements.map(\.id)) { _, _ in clearStaleSelection() }
            // FIX-P item 4: only THIS canvas's window resigning ends a drag (any other window of the app resigning key says nothing about it).
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
                if let window = keys.view?.window, (note.object as? NSWindow) === window { endEverything() }
            }
            .onDisappear {
                endEverything()
                AppModel.shared.ui.stageTakesArrows = false
                AppModel.shared.ui.stageArrow = nil
                AppModel.shared.ui.stageArrowReleased = nil
                #if DEBUG || WF_MEASURE
                StageCanvasDebug.unregister()
                #endif
            }
    }

    // MARK: Pointer

    private func pointer(in canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            // FIX-P item 4: the events of a press that was ended early (resign key, layout change) are ignored until the gesture's own end.
            let sx = Double(value.startLocation.x), sy = Double(value.startLocation.y)
            if pointerState.press(startedAt: sx, sy) { pressBegan(at: value.startLocation, in: canvas) }
            else if !pointerState.accepts(startedAt: sx, sy) {
                #if DEBUG || WF_MEASURE
                StageCanvasDebug.ignoredEvents += 1
                #endif
                return
            }
            pressMoved(dx: Double(value.translation.width), dy: Double(value.translation.height), in: canvas)
        }.onEnded { _ in pressEnded() }
    }

    /// The first event of a press: the arrow keys become the canvas's, the press picks a box.
    private func pressBegan(at point: CGPoint, in canvas: CGSize) {
        _ = pointerState.press()
        nudges.flush()
        keys.takeFocus()      // the arrow keys are the canvas's from here on
        AppModel.shared.ui.canvasLastClicked = true       // FIX-N item 8
        begin(at: point, in: canvas)
    }

    private func pressMoved(dx: Double, dy: Double, in canvas: CGSize) {
        if pointerState.drag != nil { pointerState.update(dx: dx / Double(canvas.width), dy: dy / Double(canvas.height)) }
    }

    /// The gesture's own end.
    private func pressEnded() { write(pointerState.finish()) }

    /// FIX-P items 3 and 4: written to the layout the drag began on, not the one the view shows now.
    private func write(_ commit: StagePointerSession.Commit?) {
        guard let commit else { return }
        StageCanvasEditing.commit(stage: stage, layoutID: commit.layoutID ?? layout.id, elementID: commit.elementID, from: commit.from, to: commit.to, undoManager: undoManager)
    }

    /// A drag or a run of nudges that was cut short is ended now: once, with what it showed. The drag's remaining events are ignored until its own end.
    private func endEverything() {
        nudges.flush()
        write(pointerState.interrupt())
    }

    /// FIX-P item 5: a selection that names a box that is not in this layout is cleared (the arrows then move the slide selection).
    private func clearStaleSelection() {
        if let selection, StageCanvasEditing.validSelection(selection, in: layout.elements.map(\.id)) == nil { self.selection = nil }
    }

    private func begin(at point: CGPoint, in canvas: CGSize) {
        let hit = StageCanvasEditing.hit(x: Double(point.x), y: Double(point.y), canvasWidth: Double(canvas.width), canvasHeight: Double(canvas.height),
                                         elements: layout.elements.map { ($0.id, $0.frame) }, selected: selection, editable: editable)
        switch hit {
        case .none:
            selection = nil
            pointerState.begin(nil, layoutID: layout.id)
        case .element(let id):
            selection = id
            if editable, let e = layout.elements.first(where: { $0.id == id }) { pointerState.begin(.init(elementID: id, mode: .move, start: e.frame), layoutID: layout.id) } else { pointerState.begin(nil, layoutID: layout.id) }
        case .handle(let id, let handle):
            if let e = layout.elements.first(where: { $0.id == id }) { pointerState.begin(.init(elementID: id, mode: .resize(handle), start: e.frame), layoutID: layout.id) } else { pointerState.begin(nil, layoutID: layout.id) }
        }
    }

    // MARK: Keys

    /// An arrow key (FIX-N item 5): moves the transient frame; the run is written once, when the key is released or after a quiet period.
    private func nudge(dx: Int, dy: Int, shift: Bool) -> Bool {
        guard editable, let id = selection, let element = layout.elements.first(where: { $0.id == id }) else { return false }
        nudges.nudge(elementID: id, stored: element.frame, directionX: dx, directionY: dy, shift: shift, canvasWidth: Double(size.width), canvasHeight: Double(size.height), layoutID: layout.id)
        return true
    }

    /// Called on every pass of `body`. Where a finished run is written (through the one commit, which registers the undo step), and what the app's key
    /// monitor may call when a button has keyboard focus but this canvas was clicked last (FIX-N item 8). Closures made on an earlier pass would hold that
    /// pass's layout (a stale frame to nudge from), so every pass makes them again.
    private func refreshHandlers() {
        let stage = stage, layoutID = layout.id, undoManager = undoManager
        nudges.onCommit = { c in
            StageCanvasEditing.commit(stage: stage, layoutID: c.layoutID ?? layoutID, elementID: c.elementID, from: c.from, to: c.to, undoManager: undoManager)
        }
        let ui = AppModel.shared.ui
        ui.stageTakesArrows = takesArrows
        ui.stageArrow = { dx, dy, shift in nudge(dx: dx, dy: dy, shift: shift) }
        ui.stageArrowReleased = { nudges.keyReleased() }
        #if DEBUG || WF_MEASURE
        StageCanvasDebug.register(press: { point, size in pressBegan(at: point, in: size) }, move: { dx, dy, size in pressMoved(dx: dx, dy: dy, in: size) },
                                  release: { pressEnded() })
        #endif
    }
}

/// An element's outline and its name, drawn from the frame it is given. Not a hit target: the canvas's pointer layer picks.
private struct StageElementOutline: View {
    let stage: StageModel
    let element: StageElement
    let index: Int
    let canvas: CGSize
    let selected: Bool

    var body: some View {
        let f = element.frame
        let size = CGSize(width: f.width * canvas.width, height: f.height * canvas.height)
        Rectangle().fill(Color.clear)
            .overlay(Rectangle().strokeBorder(selected ? Tok.blue : Color.white.opacity(element.isHidden ? 0.1 : 0.22),
                                              style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: selected ? [] : [4, 3])))
            .frame(width: size.width, height: size.height)
            .wfRect("st.cv.el.\(index)")
            .overlay(alignment: .topLeading) {
                Text(StageElementNames.canvasLabel(of: element, in: stage).uppercased())
                    .font(.wf(10, .semibold)).tracking(0.7).foregroundStyle(selected ? Tok.blue : Tok.muted)
                    .lineLimit(1).fixedSize().frame(height: 14)
                    .wfRect("st.cv.el.\(index).label", size: 10, weight: 600)
                    .offset(x: 1, y: -16)
            }
            .offset(x: f.x * canvas.width, y: f.y * canvas.height)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Element: \(StageElementNames.title(of: element, in: stage))")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One of the eight handles: an 8 pt white square with a 1.5 pt selection-blue edge, radius 1 (the slide editor's handle).
private struct StageHandleView: View {
    var body: some View {
        Rectangle().fill(Color.white)
            .overlay(Rectangle().strokeBorder(Tok.blue, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

// MARK: Keyboard

/// Holds the key-catching view so the pointer layer can give it focus.
final class StageKeyBox {
    weak var view: StageKeyView?
    @MainActor func takeFocus() { if let view, let window = view.window, window.firstResponder !== view { window.makeFirstResponder(view) } }
}

/// An invisible view that takes the arrow keys while it is the first responder (the pointer layer gives it focus on a press). It never takes a
/// mouse event. While it has focus it reports itself to the key router as a canvas (`.canvas`, FIX-N item 1): with a box selected the router
/// hands it the arrow keys, so the show's own arrow keys do not also move the slide selection; every other key (Space, Return, B, Escape...) is
/// routed as if the slide grid had focus. (It used to report `.slider`, which kept every key but Escape and swallowed the show's keys.)
final class StageKeyView: NSView {
    var onArrow: ((Int, Int, Bool) -> Bool)?
    /// FIX-N item 5: an arrow key came up.
    var onRelease: (() -> Void)?
    /// True while an editable layout has a box selected: the router gives this view the arrow keys only then.
    var takesArrows = false
    private let identity = UUID()
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func becomeFirstResponder() -> Bool { AppModel.shared.ui.controlFocus(id: identity, .canvas, true); return true }
    override func resignFirstResponder() -> Bool { AppModel.shared.ui.controlFocus(id: identity, .canvas, false); return true }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { AppModel.shared.ui.controlFocus(id: identity, .canvas, false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func keyUp(with event: NSEvent) {
        if [123, 124, 125, 126].contains(event.keyCode) { onRelease?() } else { super.keyUp(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        let direction: (Int, Int)? = switch event.keyCode { case 123: (-1, 0); case 124: (1, 0); case 125: (0, 1); case 126: (0, -1); default: nil }
        if let direction, onArrow?(direction.0, direction.1, event.modifierFlags.contains(.shift)) == true { return }
        super.keyDown(with: event)
    }
}

private struct StageKeyCatcher: NSViewRepresentable {
    let box: StageKeyBox
    let takesArrows: Bool
    let onArrow: (Int, Int, Bool) -> Bool
    let onRelease: () -> Void
    func makeNSView(context: Context) -> StageKeyView { let v = StageKeyView(); box.view = v; return v }
    func updateNSView(_ view: StageKeyView, context: Context) { view.onArrow = onArrow; view.onRelease = onRelease; view.takesArrows = takesArrows; box.view = view }
}

#if DEBUG || WF_MEASURE
/// FIX-N (debug builds only): the Stage canvas's press, move and release handlers, for the real-key run in a session whose screen is locked (the app
/// cannot become active, and the window swallows a synthetic click as the activating click). The hook calls the very functions the gesture calls; the keys
/// that follow are real events through the app's own key monitor and responder chain.
@MainActor enum StageCanvasDebug {
    private static var pressHandler: ((CGPoint, CGSize) -> Void)?
    private static var moveHandler: ((Double, Double, CGSize) -> Void)?
    private static var releaseHandler: (() -> Void)?
    static func register(press: @escaping (CGPoint, CGSize) -> Void, move: @escaping (Double, Double, CGSize) -> Void, release: @escaping () -> Void) {
        pressHandler = press; moveHandler = move; releaseHandler = release
    }
    static func unregister() { pressHandler = nil; moveHandler = nil; releaseHandler = nil }
    static var isRegistered: Bool { pressHandler != nil }
    /// FIX-P item 4: how many events of a press that was ended early still reached the gesture (and were ignored).
    static var ignoredEvents = 0
    static func press(at point: CGPoint, in size: CGSize) { pressHandler?(point, size) }
    static func move(dx: Double, dy: Double, in size: CGSize) { moveHandler?(dx, dy, size) }
    static func release() { releaseHandler?() }
}
#endif
