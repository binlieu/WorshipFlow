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
    @State private var drag: StageCanvasEditing.Drag?
    @State private var pressed = false
    @State private var size = CGSize(width: 820, height: 461.25)
    @State private var keys = StageKeyBox()

    /// The layout as drawn now: the dragged element at the pointer's frame, everything else as stored.
    private var shown: StageLayout {
        guard let drag, let i = layout.elements.firstIndex(where: { $0.id == drag.elementID }) else { return layout }
        var copy = layout
        copy.elements[i].frame = drag.current
        return copy
    }

    var body: some View {
        let layout = shown
        ScenePreview(scene: stage.sampleScene(for: layout), width: 1280, cached: false, follow: drag != nil)
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
            .background(StageKeyCatcher(box: keys) { dx, dy, shift in nudge(dx: dx, dy: dy, shift: shift) })
    }

    // MARK: Pointer

    private func pointer(in canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0).onChanged { value in
            if !pressed {
                pressed = true
                keys.takeFocus()      // the arrow keys are the canvas's from here on
                begin(at: value.startLocation, in: canvas)
            }
            if drag != nil { drag?.update(dx: Double(value.translation.width / canvas.width), dy: Double(value.translation.height / canvas.height)) }
        }.onEnded { _ in
            pressed = false
            guard let finished = drag else { return }
            drag = nil
            if let change = finished.finish() {
                StageCanvasEditing.commit(stage: stage, layoutID: layout.id, elementID: finished.elementID, from: change.from, to: change.to, undoManager: undoManager)
            }
        }
    }

    private func begin(at point: CGPoint, in canvas: CGSize) {
        let hit = StageCanvasEditing.hit(x: Double(point.x), y: Double(point.y), canvasWidth: Double(canvas.width), canvasHeight: Double(canvas.height),
                                         elements: layout.elements.map { ($0.id, $0.frame) }, selected: selection, editable: editable)
        switch hit {
        case .none:
            selection = nil
        case .element(let id):
            selection = id
            if editable, let e = layout.elements.first(where: { $0.id == id }) { drag = .init(elementID: id, mode: .move, start: e.frame) }
        case .handle(let id, let handle):
            if let e = layout.elements.first(where: { $0.id == id }) { drag = .init(elementID: id, mode: .resize(handle), start: e.frame) }
        }
    }

    // MARK: Keys

    private func nudge(dx: Int, dy: Int, shift: Bool) -> Bool {
        guard editable, let id = selection, let element = layout.elements.first(where: { $0.id == id }) else { return false }
        let to = StageCanvasEditing.nudged(element.frame, directionX: dx, directionY: dy, points: StageCanvasEditing.nudgeDistance(shift: shift),
                                           canvasWidth: Double(size.width), canvasHeight: Double(size.height))
        StageCanvasEditing.commit(stage: stage, layoutID: layout.id, elementID: id, from: element.frame, to: to, undoManager: undoManager)
        return true
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
            .overlay(Rectangle().strokeBorder(selected ? Tok.blue : Color.white.opacity(0.22),
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
/// mouse event. While it has focus it reports itself to the key router as a control that keeps the arrows (`.slider`), so the show's own arrow
/// keys do not also move the slide selection; Escape or another control's focus hands them back.
final class StageKeyView: NSView {
    var onArrow: ((Int, Int, Bool) -> Bool)?
    private let identity = UUID()
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }
    override func becomeFirstResponder() -> Bool { AppModel.shared.ui.controlFocus(id: identity, .slider, true); return true }
    override func resignFirstResponder() -> Bool { AppModel.shared.ui.controlFocus(id: identity, .slider, false); return true }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { AppModel.shared.ui.controlFocus(id: identity, .slider, false) }
        super.viewWillMove(toWindow: newWindow)
    }
    override func keyDown(with event: NSEvent) {
        let direction: (Int, Int)? = switch event.keyCode { case 123: (-1, 0); case 124: (1, 0); case 125: (0, 1); case 126: (0, -1); default: nil }
        if let direction, onArrow?(direction.0, direction.1, event.modifierFlags.contains(.shift)) == true { return }
        super.keyDown(with: event)
    }
}

private struct StageKeyCatcher: NSViewRepresentable {
    let box: StageKeyBox
    let onArrow: (Int, Int, Bool) -> Bool
    func makeNSView(context: Context) -> StageKeyView { let v = StageKeyView(); box.view = v; return v }
    func updateNSView(_ view: StageKeyView, context: Context) { view.onArrow = onArrow; box.view = view }
}
