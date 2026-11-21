// SLIDE-001b (PRES-01, MEDIA-07): the objects editor under the slide grid: a canvas drawn by the same compositor as
// the audience screen, selection outlines and handles over it, and an inspector. The rules (clamping, undo, saving,
// free space) live in `SlideEditorModel`; this file only draws and forwards gestures.
import SwiftUI
import AppKit
import Domain
import OperatorCore

private typealias HorizontalAlign = Domain.TextAlignment

struct SlideObjectsEditor: View {
    let app: AppModel
    @Bindable var editor: SlideEditorModel
    @State private var editingTextID: UUID?

    var body: some View {
        GeometryReader { geo in
            // The canvas takes about half the width (at most 440 points) and the inspector the rest.
            let canvasWidth = max(220, min(860, geo.size.width * 0.58, (geo.size.height - 90) * 16 / 9))
            HStack(alignment: .top, spacing: 12) {
                canvasColumn(width: canvasWidth)
                Divider()
                SlideInspector(app: app, editor: editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onChange(of: editor.selectedObjectID) { _, new in if new != editingTextID { editingTextID = nil } }
        }
    }

    private func canvasColumn(width: CGFloat) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                if let slide = editor.slide {
                    SlideCanvas(app: app, editor: editor, content: slide.content, editingTextID: $editingTextID)
                        .frame(width: width)
                } else {
                    Text("Select a slide to edit its objects.").foregroundStyle(.secondary)
                }
                toolbar
                Text("Drag to move, drag the corner square to resize, double-click a text box to type in it.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: width)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Text box") { app.insertObject(.textBox) }
                Button("Rectangle") { app.insertObject(.rectangle) }
                Button("Ellipse") { app.insertObject(.ellipse) }
                Button("Rounded rectangle") { app.insertObject(.roundedRectangle) }
                Button("Image…") { app.insertImage() }
            } label: { Label("Insert", systemImage: "plus.square") }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(editor.slide == nil)
                .accessibilityLabel("Insert object")
            Button { editor.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!editor.canUndo)
                .help("Undo (Command-Z)")
            Button { editor.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!editor.canRedo)
                .help("Redo (Shift-Command-Z)")
            Button { editor.duplicateSelected() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                .disabled(editor.selectedObjectID == nil)
                .help("Duplicate (Command-D)")
            Button(role: .destructive) { editor.deleteSelected() } label: { Label("Delete", systemImage: "trash") }
                .disabled(editor.selectedObjectID == nil)
                .help("Delete the selected object (Delete key)")
        }
        .labelStyle(.iconOnly)           // titles were clipped at this width; help text and accessibility labels keep the names
        .controlSize(.small)
    }
}

// MARK: Canvas

/// The slide as the audience screen draws it, with a box over each object that can be dragged and resized.
struct SlideCanvas: View {
    let app: AppModel
    let editor: SlideEditorModel
    let content: SlideContent
    @Binding var editingTextID: UUID?

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
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
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
    /// True from the press until the release, so the object is selected on the press and not only on the release.
    @State private var pressed = false
    @FocusState private var textFocused: Bool

    private let handle: CGFloat = 12
    private var handleHit: CGFloat { CGFloat(SlideEditing.handleHitSize) }

    private var isText: Bool { if case .text = object.content { true } else { false } }
    private var text: String { if case .text(let t) = object.content { t.text } else { "" } }

    var body: some View {
        // UI-004: while the pointer is down the model keeps the dragged frame apart (nothing is saved or redrawn per event), and this
        // box follows it at once; the picture under it is redrawn once, when the pointer is released.
        let f = editor.dragFrames[object.id] ?? object.frame
        let size = CGSize(width: f.width * canvas.width, height: f.height * canvas.height)
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(selected ? Color.accentColor.opacity(0.10) : Color.clear)
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color.white.opacity(0.35),
                                            style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [4, 3])))
                .overlay(Rectangle().fill(Color.accentColor.opacity(dragStart == nil ? 0 : 0.18)))
                .contentShape(Rectangle())
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
                    .font(.system(size: 13))
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
            if selected {
                Rectangle().fill(Color.accentColor).frame(width: handle, height: handle)
                    .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1))
                    .frame(width: handleHit, height: handleHit, alignment: .bottomTrailing)     // a bigger area than the square to grab it by
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        if resizeStart == nil {
                            resizeStart = object.frame
                            editor.beginInteraction()
                        }
                        editor.resize(object.id, from: resizeStart ?? object.frame,
                                      dWidth: value.translation.width / canvas.width,
                                      dHeight: value.translation.height / canvas.height)
                    }.onEnded { _ in
                        resizeStart = nil
                        editor.endInteraction()
                    })
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: f.x * canvas.width, y: f.y * canvas.height)
        .accessibilityElement(children: editing ? .contain : .ignore)
        .accessibilityLabel("Object: \(slideObjectTitle(object))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { editor.select(object.id) }
        .accessibilityAction(named: "Delete") { editor.delete(object.id) }
        .accessibilityAction(named: "Duplicate") { editor.duplicate(object.id) }
    }
}

// MARK: Inspector

/// Colours the inspector offers as buttons, so a colour can be chosen without opening the colour panel.
private let swatches: [(name: String, color: ColorRGBA)] = [
    ("Blue", ColorRGBA(red: 0.2, green: 0.5, blue: 0.95)), ("Red", ColorRGBA(red: 0.9, green: 0.2, blue: 0.2)),
    ("Green", ColorRGBA(red: 0.2, green: 0.7, blue: 0.3)), ("Gold", ColorRGBA(red: 0.95, green: 0.75, blue: 0.2)),
    ("White", .white), ("Black", .black),
]

struct SlideInspector: View {
    let app: AppModel
    @Bindable var editor: SlideEditorModel

    var body: some View {
        if let o = editor.selectedObject {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(slideObjectTitle(o)).font(.headline)
                        Spacer()
                        orderButtons(o)
                    }
                    switch o.content {
                    case .text(let t): textControls(o, t)
                    case .shape(let s): shapeControls(o, s)
                    case .image(let i): imageControls(o, i)
                    }
                    Divider()
                    HStack {
                        Text("Opacity").font(.caption).frame(width: 52, alignment: .leading)
                        Slider(value: Binding(get: { o.opacity }, set: { editor.setOpacity(o.id, $0) }), in: 0...1)
                            .accessibilityLabel("Opacity")
                        Text("\(Int((o.opacity * 100).rounded()))%").font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
                    }
                    Text("Position and size, in percent of the slide").font(.caption).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow { percent("Left", o, \.x); percent("Top", o, \.y) }
                        GridRow { percent("Width", o, \.width); percent("Height", o, \.height) }
                    }
                    Divider()
                    Text("Add another").font(.caption).foregroundStyle(.secondary)
                    insertButtons
                }
                .padding(.trailing, 8)
            }
        } else {
            VStack(spacing: 6) {
                Text("No object selected").font(.headline)
                Text("Choose an object on the slide, or add one:")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                insertButtons
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Add-an-object buttons, so objects can be added whatever is selected.
    private var insertButtons: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Text box") { app.insertObject(.textBox) }
                Button("Rectangle") { app.insertObject(.rectangle) }
                Button("Ellipse") { app.insertObject(.ellipse) }
            }
            HStack {
                Button("Rounded rectangle") { app.insertObject(.roundedRectangle) }
                Button("Image…") { app.insertImage() }
            }
        }
        .controlSize(.small)
    }

    private func orderButtons(_ o: SlideObject) -> some View {
        HStack(spacing: 2) {
            Button { editor.bringToFront(o.id) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                .help("Bring to front").accessibilityLabel("Bring to front")
            Button { editor.bringForward(o.id) } label: { Image(systemName: "square.2.layers.3d.top.filled") }
                .help("Bring forward").accessibilityLabel("Bring forward")
            Button { editor.sendBackward(o.id) } label: { Image(systemName: "square.2.layers.3d.bottom.filled") }
                .help("Send backward").accessibilityLabel("Send backward")
            Button { editor.sendToBack(o.id) } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                .help("Send to back").accessibilityLabel("Send to back")
        }
        .controlSize(.small)
    }

    // MARK: Text

    @ViewBuilder private func textControls(_ o: SlideObject, _ t: TextObject) -> some View {
        let id = o.id
        TextField("Text", text: Binding(get: { t.text }, set: { editor.setText(id, $0) }), axis: .vertical)
            .lineLimit(1...4).textFieldStyle(.roundedBorder)
            .accessibilityLabel("Text")
        VStack(alignment: .leading, spacing: 6) {
            TextField("Font", text: Binding(get: { t.style.fontName }, set: { editor.setFontName(id, $0) }))
                .textFieldStyle(.roundedBorder).accessibilityLabel("Font")
            Stepper(value: Binding(get: { t.style.fontSize }, set: { editor.setFontSize(id, $0) }),
                    in: SlideEditing.fontSizeRange, step: 4) {
                Text("Size \(Int(t.style.fontSize))").font(.caption.monospacedDigit())
            }.accessibilityLabel("Font size")
        }
        if NSFont(name: t.style.fontName, size: 12) == nil {
            Text("No font with that name is installed, so the default font is used.").font(.caption).foregroundStyle(.orange)
        }
        colorRow("Colour", color: t.style.color) { editor.setTextColor(id, $0) }
        HStack {
            Picker("Across", selection: Binding(get: { t.alignment }, set: { editor.setAlignment(id, $0) })) {
                Text("Left").tag(HorizontalAlign.leading)
                Text("Centre").tag(HorizontalAlign.center)
                Text("Right").tag(HorizontalAlign.trailing)
            }.pickerStyle(.menu).fixedSize().accessibilityLabel("Alignment")
            Picker("Down", selection: Binding(get: { t.verticalAlignment }, set: { editor.setVerticalAlignment(id, $0) })) {
                Text("Top").tag(VerticalAlignment.top)
                Text("Middle").tag(VerticalAlignment.center)
                Text("Bottom").tag(VerticalAlignment.bottom)
            }.pickerStyle(.menu).fixedSize().accessibilityLabel("Vertical alignment")
        }
        HStack {
            Stepper(value: Binding(get: { t.style.outlineWidth }, set: { editor.setOutline(id, width: $0) }),
                    in: SlideEditing.outlineRange, step: 1) {
                Text("Outline \(Int(t.style.outlineWidth))").font(.caption.monospacedDigit())
            }.accessibilityLabel("Outline width")
            ColorPicker("Outline colour", selection: Binding(get: { Color(t.style.outlineColor) },
                                                              set: { editor.setOutline(id, color: $0.rgba) }))
                .labelsHidden().accessibilityLabel("Outline colour")
        }
        Toggle("Shadow", isOn: Binding(get: { t.style.shadow != nil }, set: { on in
            editor.setShadow(id, on ? TextShadow(offsetX: 4, offsetY: 4, blur: 8) : nil)
        })).toggleStyle(.wfCheckbox)
        if let shadow = t.style.shadow {
            VStack(alignment: .leading, spacing: 4) {
                number("Across", shadow.offsetX) { editor.setShadow(id, TextShadow(color: shadow.color, offsetX: $0, offsetY: shadow.offsetY, blur: shadow.blur)) }
                number("Down", shadow.offsetY) { editor.setShadow(id, TextShadow(color: shadow.color, offsetX: shadow.offsetX, offsetY: $0, blur: shadow.blur)) }
                number("Blur", shadow.blur) { editor.setShadow(id, TextShadow(color: shadow.color, offsetX: shadow.offsetX, offsetY: shadow.offsetY, blur: $0)) }
                ColorPicker("Shadow colour", selection: Binding(get: { Color(shadow.color) }, set: {
                    editor.setShadow(id, TextShadow(color: $0.rgba, offsetX: shadow.offsetX, offsetY: shadow.offsetY, blur: shadow.blur))
                })).labelsHidden().accessibilityLabel("Shadow colour")
            }
        }
        Text("Size, outline and shadow are in points on a 1080-line screen.").font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Shape

    @ViewBuilder private func shapeControls(_ o: SlideObject, _ s: ShapeObject) -> some View {
        let id = o.id
        Toggle("Fill", isOn: Binding(get: { s.fill != nil }, set: { on in
            editor.setFill(id, on ? SlideEditing.defaultShapeFill : nil)
        })).toggleStyle(.wfCheckbox)
        if let fill = s.fill { colorRow("Fill colour", color: fill) { editor.setFill(id, $0) } }
        Toggle("Outline", isOn: Binding(get: { s.strokeColor != nil && s.strokeWidth > 0 }, set: { on in
            if on {
                editor.setStrokeColor(id, s.strokeColor ?? .white)
                editor.setStrokeWidth(id, max(s.strokeWidth, 6))
            } else {
                editor.setStrokeWidth(id, 0)
            }
        })).toggleStyle(.wfCheckbox)
        if s.strokeColor != nil, s.strokeWidth > 0 {
            colorRow("Outline colour", color: s.strokeColor ?? .white) { editor.setStrokeColor(id, $0) }
            Stepper(value: Binding(get: { s.strokeWidth }, set: { editor.setStrokeWidth(id, $0) }),
                    in: SlideEditing.strokeRange, step: 1) {
                Text("Outline width \(Int(s.strokeWidth))").font(.caption.monospacedDigit())
            }.accessibilityLabel("Outline width")
        }
        if case .roundedRectangle(let radius) = s.shape {
            HStack {
                Text("Corners").font(.caption).frame(width: 52, alignment: .leading)
                Slider(value: Binding(get: { radius }, set: { editor.setCornerRadius(id, $0) }), in: 0...0.5)
                    .accessibilityLabel("Corner radius")
            }
        }
    }

    // MARK: Image

    @ViewBuilder private func imageControls(_ o: SlideObject, _ i: ImageObject) -> some View {
        Text(i.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
        if !FileManager.default.isReadableFile(atPath: i.path) {
            Text("That file cannot be read, so nothing is drawn. Delete this object and insert the image again.")
                .font(.caption).foregroundStyle(.orange)
        }
        Picker("Show", selection: Binding(get: { i.contentMode }, set: { editor.setImageContentMode(o.id, $0) })) {
            Text("Fit (whole picture)").tag(ImageContentMode.fit)
            Text("Fill (crop to the box)").tag(ImageContentMode.fill)
        }.pickerStyle(.menu).fixedSize().accessibilityLabel("Image mode")
    }

    // MARK: Pieces

    private func colorRow(_ label: String, color: ColorRGBA, set: @escaping (ColorRGBA) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(swatches, id: \.name) { swatch in
                    Button { set(swatch.color) } label: {
                        RoundedRectangle(cornerRadius: 3).fill(Color(swatch.color)).frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color == swatch.color ? Color.accentColor : Color.gray.opacity(0.6),
                                                                              lineWidth: color == swatch.color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel("\(label) \(swatch.name)")
                }
                ColorPicker(label, selection: Binding(get: { Color(color) }, set: { set($0.rgba) }))
                    .labelsHidden().accessibilityLabel("\(label) custom")
            }
        }
    }

    private func number(_ label: String, _ value: Double, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption)
            TextField(label, value: Binding(get: { value }, set: { set($0) }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 46).accessibilityLabel("Shadow \(label.lowercased())")
        }
    }

    private func percent(_ label: String, _ o: SlideObject, _ keyPath: WritableKeyPath<NormalizedRect, Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).frame(width: 44, alignment: .leading)
            TextField(label, value: Binding(get: { o.frame[keyPath: keyPath] * 100 }, set: { value in
                var f = o.frame
                f[keyPath: keyPath] = value / 100
                editor.setFrame(o.id, x: f.x, y: f.y, width: f.width, height: f.height)
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 58)
                .accessibilityLabel("\(label) percent")
        }
    }
}
