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
        let text = "1920 × 1080 · theme “\(theme)” · slide \(workspace.show.selectedIndex + 1) of \(workspace.slides.count)"
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
    private var shownContent: SlideContent {
        guard !editor.dragFrames.isEmpty else { return content }
        var shown = content
        shown.objects = editor.objects
        return shown
    }

    var body: some View {
        let _ = app.sceneRevision          // follows theme and Look changes
        ScenePreview(scene: app.thumbnailScene(for: shownContent), width: 880, cached: false, follow: !editor.dragFrames.isEmpty)
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
                        ForEach(content.objects) { object in
                            ObjectBox(editor: editor, object: object, canvas: geo.size,
                                      selected: editor.selectedObjectID == object.id,
                                      editing: editingTextID == object.id,
                                      beginEditing: { editingTextID = object.id },
                                      endEditing: { editingTextID = nil })
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .wfRect("ed.canvas", radius: 2)
            // `--shadow`: 0 12 40, 50 % black (18 % of the ink in light); the only shadow the design allows beside sheets and popovers.
            .shadow(color: scheme == .light ? Color(red: 0.075, green: 0.157, blue: 0.239).opacity(0.18) : .black.opacity(0.5), radius: 20, y: 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Slide canvas")
    }
}

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
    @State private var resizeStart: NormalizedRect?
    /// UI-005c: the seven handles that are not the bottom right one resize from a local frame (the model's drag only knows the corner that
    /// does not move) and write it once when the pointer is released.
    @State private var handleStart: NormalizedRect?
    @State private var handleFrame: NormalizedRect?
    /// True from the press until the release, so the object is selected on the press and not only on the release.
    @State private var pressed = false
    @FocusState private var textFocused: Bool

    private var handleHit: CGFloat { 16 }

    private var isText: Bool { if case .text = object.content { true } else { false } }
    private var text: String { if case .text(let t) = object.content { t.text } else { "" } }

    /// `u` order of the mockup: corners and edge midpoints, row by row.
    private static let handles: [(px: Double, py: Double)] = [(0, 0), (0.5, 0), (1, 0), (0, 0.5), (1, 0.5), (0, 1), (0.5, 1), (1, 1)]

    var body: some View {
        // UI-004: while the pointer is down the model keeps the dragged frame apart (nothing is saved or redrawn per event), and this
        // box follows it at once; the picture under it is redrawn once, when the pointer is released.
        let f = handleFrame ?? editor.dragFrames[object.id] ?? object.frame
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
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    if !pressed {
                        pressed = true
                        if editor.selectedObjectID != object.id { editor.select(object.id) }
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
                    pressed = false
                    if dragStart != nil {
                        dragStart = nil
                        editor.endInteraction()
                    }
                })
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    editor.select(object.id)
                    if isText { beginEditing() }
                })
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
                ForEach(Array(Self.handles.enumerated()), id: \.offset) { index, h in handle(index, h.px, h.py, size: size) }
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

    /// One of the eight 8 pt handles (white, 1.5 pt selection-blue edge, radius 1), centred 1 pt inside the box's own edge at the
    /// corners and midpoints; the grab area is 16 pt.
    private func handle(_ index: Int, _ px: Double, _ py: Double, size: CGSize) -> some View {
        let cx = 1 + px * (Double(size.width) - 2), cy = 1 + py * (Double(size.height) - 2)
        return Rectangle().fill(Color.white)
            .overlay(Rectangle().strokeBorder(Tok.blue, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .frame(width: 8, height: 8)
            .wfRect("ed.handle.\(index)", radius: 1)
            .frame(width: handleHit, height: handleHit)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                resizeFromHandle(px: px, py: py, value.translation)
            }.onEnded { _ in finishHandleDrag(px: px, py: py) })
            .offset(x: cx - handleHit / 2, y: cy - handleHit / 2)
            .accessibilityHidden(true)
    }

    private func resizeFromHandle(px: Double, py: Double, _ translation: CGSize) {
        let dx = Double(translation.width / canvas.width), dy = Double(translation.height / canvas.height)
        if px == 1, py == 1 {
            // The bottom right corner is the model's own resize, which redraws the picture while the pointer moves.
            if resizeStart == nil { resizeStart = object.frame; editor.beginInteraction() }
            editor.resize(object.id, from: resizeStart ?? object.frame, dWidth: dx, dHeight: dy)
            return
        }
        if handleStart == nil { handleStart = object.frame }
        guard let s = handleStart else { return }
        let minimum = SlideObject.minimumSize
        var x = s.x, y = s.y, w = s.width, h = s.height
        if px == 0 { let right = s.x + s.width; x = min(s.x + dx, right - minimum); w = right - x }
        if px == 1 { w = max(s.width + dx, minimum) }
        if py == 0 { let bottom = s.y + s.height; y = min(s.y + dy, bottom - minimum); h = bottom - y }
        if py == 1 { h = max(s.height + dy, minimum) }
        handleFrame = NormalizedRect(x: x, y: y, width: w, height: h)
    }

    private func finishHandleDrag(px: Double, py: Double) {
        if px == 1, py == 1 {
            resizeStart = nil
            editor.endInteraction()
            return
        }
        if let f = handleFrame { editor.setFrame(object.id, x: f.x, y: f.y, width: f.width, height: f.height) }
        handleFrame = nil
        handleStart = nil
    }
}
