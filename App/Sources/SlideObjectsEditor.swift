// SLIDE-001b (PRES-01, MEDIA-07) and UI-005c: the Edit mode's canvas area: the slide drawn by the same compositor as the audience screen,
// 800 points wide and centred in the `bg` area, with the title-safe guide, a selection box with eight handles over it, and the caption.
// The rules (clamping, undo, saving, free space) live in `SlideEditorModel`; this file only draws and forwards gestures. The inspector
// is `EditInspector.swift`.
import SwiftUI
import AppKit
import Domain
import OperatorCore

/// The legacy entry point (still named by `SlideEditor` in CentrePane.swift, which Edit no longer uses): the canvas area.
struct SlideObjectsEditor: View {
    let app: AppModel
    @Bindable var editor: SlideEditorModel

    var body: some View {
        if let workspace = app.workspace { EditCanvasArea(app: app, workspace: workspace, editor: editor) }
    }
}

// MARK: Canvas area (`.canvaswrap`)

struct EditCanvasArea: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Bindable var editor: SlideEditorModel
    @State private var editingTextID: UUID?

    var body: some View {
        GeometryReader { geo in
            // 02-editor: an 800 pt canvas centred in the area; smaller windows scale it down.
            let width = max(220, min(800, geo.size.width - 80, (geo.size.height - 120) * 16 / 9))
            ZStack(alignment: .bottomLeading) {
                Tok.bg
                    .contentShape(Rectangle())
                    .onTapGesture { editor.select(nil); editingTextID = nil }
                    .wfRect("ed.wrap")
                if let slide = editor.slide {
                    SlideCanvas(app: app, editor: editor, content: slide.content, editingTextID: $editingTextID)
                        .frame(width: width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select a slide to edit its objects.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                caption.padding(.leading, 14).padding(.bottom, 10)
            }
            .onChange(of: editor.selectedObjectID) { _, new in if new != editingTextID { editingTextID = nil } }
        }
    }

    /// 1920 x 1080 · theme "..." · slide n of m: what the app knows (the output size is the compositor's fixed canvas).
    private var caption: some View {
        let theme = workspace.openThemeID.flatMap { id in app.themes.first { $0.id == id }?.name } ?? "Default"
        let text = "1920 × 1080 · theme “\(theme)” · slide \(workspace.showParts.selectedIndex + 1) of \(workspace.slides.count)"
        return Text(text).font(.wfMono(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
            .wfRect("ed.caption", size: 11, weight: 400)
            .allowsHitTesting(false)
    }
}

// MARK: Canvas

/// The slide as the audience screen draws it, with a box over each object that can be dragged and resized.
struct SlideCanvas: View {
    let app: AppModel
    let editor: SlideEditorModel
    let content: SlideContent
    @Binding var editingTextID: UUID?
    @Environment(\.colorScheme) private var scheme

    /// UI-004: while an object is dragged the scene is drawn from the editor's transient frames, at once and as fast as the pointer moves.
    /// The presentation, the grid's thumbnails and the live output are not involved: they change once, when the pointer is released.
    /// FIX-K: the same for a lyric box (its transient frame becomes the slide's text frame in the drawn copy only).
    private var shownContent: SlideContent {
        guard !editor.dragFrames.isEmpty || !editor.lyricDragFrames.isEmpty else { return content }
        var shown = content
        if !editor.dragFrames.isEmpty { shown.objects = editor.objects }
        if !editor.lyricDragFrames.isEmpty {
            var frames = content.textFrames ?? SlideTextFrames()
            for (box, frame) in editor.lyricDragFrames { frames[box] = frame }
            shown.textFrames = frames
        }
        return shown
    }

    var body: some View {
        let _ = app.sceneRevision          // follows theme and Look changes
        ScenePreview(scene: app.thumbnailScene(for: shownContent), width: 880, cached: false, follow: !editor.dragFrames.isEmpty || !editor.lyricDragFrames.isEmpty)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { editor.select(nil); editingTextID = nil }
                        // The title-safe guide (`.safe`): a dashed line 5 % in from every edge, with its label above the top left corner.
                        Rectangle().strokeBorder(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.9)
                            .wfRect("ed.safe")
                            .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.05)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        Text("Title-safe 90%").font(.wf(10)).foregroundStyle(Tok.muted).wfLine()
                            .wfRect("ed.safeLabel", size: 10, weight: 400)
                            .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.05 - 16 * 1.3)
                            .allowsHitTesting(false).accessibilityHidden(true)
                        // FIX-K: the lyric boxes (first and second language) below the objects, so an object over the words is hit first.
                        let lyric = editor.lyricBoxes
                        ForEach(LyricBox.allCases, id: \.self) { box in
                            if let frame = lyric[box] {
                                LyricBoxView(editor: editor, box: box, frame: frame, canvas: geo.size,
                                             selected: editor.selectedLyricBox == box, own: editor.hasOwnFrame(box))
                            }
                        }
                        ForEach(content.objects) { object in
                            ObjectBox(editor: editor, object: object, canvas: geo.size,
                                      selected: editor.selectedObjectID == object.id,
                                      editing: editingTextID == object.id,
                                      beginEditing: { editingTextID = object.id },
                                      endEditing: { editingTextID = nil })
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    // FIX-K: every drag on the canvas is measured in THIS space, which does not move. A box that follows the pointer moves its own
                    // local space, and a gesture measured there sees the pointer cover only half the distance (the cause of "cannot be dragged").
                    .coordinateSpace(name: SlideCanvasSpace.name)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .wfRect("ed.canvas", radius: 2)
            // FIX-N item 6: a drag SwiftUI never ended (the window resigned key, the slide or the mode changed, the view went) is ended here, once, so the
            // inspector's fields keep writing and no box is left "pressed".
            .onDisappear { editor.endInteraction() }
            .onChange(of: editor.slide?.id) { _, _ in editor.endInteraction() }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in editor.endInteraction() }
            // `--shadow`: 0 12 40, 50 % black (18 % of the ink in light); the only shadow the design allows beside sheets and popovers.
            .shadow(color: scheme == .light ? Color(red: 0.075, green: 0.157, blue: 0.239).opacity(0.18) : .black.opacity(0.5), radius: 20, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Slide canvas")
    }
}

/// FIX-K: the one coordinate space every drag gesture of the Edit canvas is measured in (see `SlideCanvas`).
enum SlideCanvasSpace { static let name = "slideCanvas" }

func slideObjectTitle(_ object: SlideObject) -> String {
    switch object.content {
    case .text: "Text box"
    case .image: "Image"
    case .shape(let s):
        switch s.shape {
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .roundedRectangle: "Rounded rectangle"
        }
    }
}

private struct ObjectBox: View {
    let editor: SlideEditorModel
    let object: SlideObject
    let canvas: CGSize
    let selected: Bool
    let editing: Bool
    let beginEditing: () -> Void
    let endEditing: () -> Void
    /// The frame when the current drag began, so a drag is measured from there and clamped by the model.
    @State private var dragStart: NormalizedRect?
    /// True from the press until the release, so the object is selected on the press and not only on the release.
    /// FIX-P item 4: a press ended early (an interaction closed by another write) is not started again by the gesture's later events.
    @State private var press = PressGuard()
    @FocusState private var textFocused: Bool

    private var handleHit: CGFloat { 16 }

    private var isText: Bool { if case .text = object.content { true } else { false } }
    private var text: String { if case .text(let t) = object.content { t.text } else { "" } }

    var body: some View {
        // UI-004: while the pointer is down the model keeps the dragged frame apart (nothing is saved or redrawn per event), and this
        // box follows it at once; the picture under it is redrawn once, when the pointer is released.
        let f = editor.dragFrames[object.id] ?? object.frame
        let size = CGSize(width: f.width * canvas.width, height: f.height * canvas.height)
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(Color.clear)
                .overlay(Rectangle().strokeBorder(selected ? Tok.blue : Color.white.opacity(0.25),
                                                  style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: selected ? [] : [4, 3])))
                .overlay(Rectangle().fill(Tok.blue.opacity(dragStart == nil ? 0 : 0.12)))
                .contentShape(Rectangle())
                .wfRect(selected ? "ed.box" : "")
                // One gesture does the press, the click and the drag. Separate single- and double-tap gestures on the same view made
                // the drag wait for them to fail, so it started late or not at all. The press selects at once; the drag starts on the
                // first movement past a few points; a press that does not move is a click.
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(SlideCanvasSpace.name)).onChanged { value in
                    switch press.event(startedAt: .init(x: Double(value.startLocation.x), y: Double(value.startLocation.y))) {
                    case .ignored: return
                    case .began:
                        AppModel.shared.ui.canvasLastClicked = true        // FIX-N item 8
                        if editor.selectedObjectID != object.id { editor.select(object.id) }
                    case .continuing: break
                    }
                    if dragStart == nil, !editing,
                       SlideEditing.dragHasStarted(dx: value.translation.width, dy: value.translation.height) {
                        dragStart = object.frame
                        editor.beginInteraction()
                    }
                    if let start = dragStart {
                        editor.move(object.id, from: start,
                                    dx: value.translation.width / canvas.width, dy: value.translation.height / canvas.height)
                    }
                }.onEnded { _ in
                    press.ended()
                    if dragStart != nil {
                        dragStart = nil
                        editor.endInteraction()
                    }
                })
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    editor.select(object.id)
                    if isText { beginEditing() }
                })
                .onChange(of: editor.interactionEpoch) { _, _ in dragStart = nil; press.interrupt() }      // FIX-N item 6, FIX-P item 4: an interaction ended elsewhere
            if editing, isText {
                TextField("Text", text: Binding(get: { text }, set: { editor.setText(object.id, $0) }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.wf(13))
                    .padding(4)
                    .background(Color.black.opacity(0.75))
                    .foregroundStyle(.white)
                    .focused($textFocused)
                    .onSubmit { endEditing() }
                    .onExitCommand { endEditing() }
                    .onAppear { textFocused = true }
                    .onChange(of: textFocused) { _, focused in if !focused { endEditing() } }
                    .accessibilityLabel("Text of the text box")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if selected {
                CanvasHandles(size: size, canvas: canvas, frame: object.frame, epoch: editor.interactionEpoch,
                              begin: { editor.beginInteraction() }, change: { editor.dragFrame(object.id, to: $0) }, end: { editor.endInteraction() })
            }
        }
        .offset(x: f.x * canvas.width, y: f.y * canvas.height)
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel("Object: \(slideObjectTitle(object))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { editor.select(object.id) }
        .accessibilityAction(named: "Delete") { editor.delete(object.id) }
        .accessibilityAction(named: "Duplicate") { editor.duplicate(object.id) }
    }
}

// MARK: Handles (FIX-K: shared by objects and lyric boxes)

/// The eight 8 pt handles (white, 1.5 pt selection-blue edge, radius 1), centred 1 pt inside the box's own edge at the corners and midpoints; the grab area is 16 pt.
/// A drag works through the editor's interaction (the transient frame follows the pointer, one write and one undo step on release), in the canvas's own space.
private struct CanvasHandles: View {
    let size: CGSize
    let canvas: CGSize
    /// The stored frame of the box (not the dragged one): a drag is measured from where it was when the pointer went down.
    let frame: NormalizedRect
    /// FIX-N item 6: changes when an interaction ended somewhere else (an interrupted drag), so a stale `start` is dropped.
    let epoch: Int
    let begin: () -> Void
    let change: (NormalizedRect) -> Void
    let end: () -> Void
    @State private var start: NormalizedRect?
    @State private var press = PressGuard()

    private var hit: CGFloat { 16 }

    /// `u` order of the mockup: corners and edge midpoints, row by row.
    private static let handles: [(px: Double, py: Double)] = [(0, 0), (0.5, 0), (1, 0), (0, 0.5), (1, 0.5), (0, 1), (0.5, 1), (1, 1)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.handles.enumerated()), id: \.offset) { index, h in handle(index, h.px, h.py) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .onChange(of: epoch) { _, _ in start = nil; press.interrupt() }
    }

    private func handle(_ index: Int, _ px: Double, _ py: Double) -> some View {
        let cx = 1 + px * (Double(size.width) - 2), cy = 1 + py * (Double(size.height) - 2)
        return Rectangle().fill(Color.white)
            .overlay(Rectangle().strokeBorder(Tok.blue, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .frame(width: 8, height: 8)
            .wfRect("ed.handle.\(index)", radius: 1)
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named(SlideCanvasSpace.name)).onChanged { value in
                switch press.event(startedAt: .init(x: Double(value.startLocation.x), y: Double(value.startLocation.y))) {
                case .ignored: return
                case .began: start = frame; begin(); AppModel.shared.ui.canvasLastClicked = true        // FIX-N item 8
                case .continuing: break
                }
                guard let s = start else { return }
                change(SlideEditing.resizedFrame(from: s, handleX: px, handleY: py,
                                                 dx: Double(value.translation.width / canvas.width), dy: Double(value.translation.height / canvas.height)))
            }.onEnded { _ in
                press.ended()
                if start != nil { start = nil; end() }
            })
            .offset(x: cx - hit / 2, y: cy - hit / 2)
            .accessibilityHidden(true)
    }
}

// MARK: Lyric boxes (FIX-K)

/// The box of one language's words, drawn where the slide's own frame (or else the theme's) puts them. Pressing selects it; dragging moves it, the handles
/// resize it, and either gives THIS slide its own text frame. The theme and the other slides are not touched, and nothing reaches the live output.
private struct LyricBoxView: View {
    let editor: SlideEditorModel
    let box: LyricBox
    let frame: NormalizedRect
    let canvas: CGSize
    let selected: Bool
    let own: Bool
    @State private var dragStart: NormalizedRect?
    /// FIX-P item 4: a press ended early (an interaction closed by another write) is not started again by the gesture's later events.
    @State private var press = PressGuard()

    var body: some View {
        let size = CGSize(width: frame.width * canvas.width, height: frame.height * canvas.height)
        Rectangle()
            .fill(Color.clear)
            .overlay(Rectangle().strokeBorder(selected ? Tok.blue : Color.white.opacity(0.25),
                                              style: StrokeStyle(lineWidth: selected ? 1.5 : 1, dash: selected ? [] : [4, 3])))
            .overlay(Rectangle().fill(Tok.blue.opacity(dragStart == nil ? 0 : 0.12)))
            .contentShape(Rectangle())
            .wfRect(selected ? "ed.lyric.\(box.rawValue)" : "ed.lyricbox.\(box.rawValue)")
            .onChange(of: editor.interactionEpoch) { _, _ in dragStart = nil; press.interrupt() }      // FIX-N item 6, FIX-P item 4
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(SlideCanvasSpace.name)).onChanged { value in
                switch press.event(startedAt: .init(x: Double(value.startLocation.x), y: Double(value.startLocation.y))) {
                case .ignored: return
                case .began:
                    AppModel.shared.ui.canvasLastClicked = true        // FIX-N item 8
                    if editor.selectedLyricBox != box { editor.selectLyric(box) }
                case .continuing: break
                }
                if dragStart == nil, SlideEditing.dragHasStarted(dx: value.translation.width, dy: value.translation.height) {
                    dragStart = frame
                    editor.beginInteraction()
                }
                if let start = dragStart {
                    editor.moveLyric(box, from: start, dx: value.translation.width / canvas.width, dy: value.translation.height / canvas.height)
                }
            }.onEnded { _ in
                press.ended()
                if dragStart != nil { dragStart = nil; editor.endInteraction() }
            })
            .overlay(alignment: .topLeading) {
                if selected {
                    CanvasHandles(size: size, canvas: canvas, frame: editor.slide?.content.textFrames?[box] ?? frame, epoch: editor.interactionEpoch,
                                  begin: { editor.beginInteraction() }, change: { editor.dragLyricFrame(box, to: $0) }, end: { editor.endInteraction() })
                }
            }
            .frame(width: size.width, height: size.height)
            .offset(x: frame.x * canvas.width, y: frame.y * canvas.height)
            .contextMenu {
                Button("Reset to theme position") { editor.resetLyricFrame(box) }.disabled(!own)
                Button("Apply to all slides in this song") { AppModel.shared.ui.applyLyricToAll = box }        // FIX-N item 7: asks first
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lyric box: \(box.title)")
            .accessibilityHint(own ? "This slide has its own position" : "Uses the theme's position")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { editor.selectLyric(box) }
            .accessibilityAction(named: "Reset to theme position") { editor.resetLyricFrame(box) }
    }
}
