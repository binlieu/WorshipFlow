// STAGE-001b (LIVE-01, SCRN-03) / UI-001: the stage layout editor, now the Stage mode (it was a sheet). The built-in layout is read-only (Duplicate it to edit).
// Every change is saved at once; the canvas is drawn by the same compositor the screens use. The rules (clamping,
// read-only, saving) live in `StageModel`; this file only draws and forwards gestures.
import SwiftUI
import AppKit
import Domain
import OperatorCore

private typealias StageAlignment = Domain.TextAlignment

struct StageEditorView: View {
    let app: AppModel
    @Bindable var stage: StageModel
    @State private var layoutID = StageLayout.standardID
    @State private var elementID: UUID?
    @State private var nameText = ""
    @State private var pendingDelete = false

    private var layout: StageLayout { stage.layout(withID: layoutID) ?? StageLayout.standard }
    private var editable: Bool { stage.isEditable(layoutID) }
    private var element: StageElement? { layout.elements.first { $0.id == elementID } }

    var body: some View {
        VStack(spacing: 0) {
            if let error = stage.lastError { ErrorBar(message: error) { stage.dismissError() } }
            HStack(alignment: .top, spacing: 0) {
                layoutList.frame(width: 240)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    Divider()
                    VStack(alignment: .leading, spacing: Space.s4) {
                        header
                        StageCanvas(stage: stage, layout: layout, editable: editable, selection: $elementID)
                            .frame(maxWidth: 900)
                        Text("Sample words, clock, message and notes are shown here. Drag a box to move it, drag its corner to resize.")
                            .font(.wfMonoData).foregroundStyle(Tok.muted)
                    }
                    .padding(Space.s5)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                Divider()
                rightColumn.frame(width: 320)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { nameText = layout.name }
        .onChange(of: layoutID) { _, _ in
            elementID = nil
            nameText = layout.name
        }
        .confirmationDialog("Delete the layout \"\(layout.name)\"?", isPresented: $pendingDelete, titleVisibility: .visible) {
            Button("Delete layout", role: .destructive) {
                let id = layoutID
                layoutID = StageLayout.standardID
                stage.deleteLayout(id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Stage screens that used it go back to the built-in layout.") }
    }

    // MARK: List

    private var layoutList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Stage layouts")
                Spacer()
                Button { if let made = stage.createLayout(name: nextName("My layout")) { layoutID = made.id } } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("A new layout that starts as a copy of Standard").accessibilityLabel("New layout")
            }
            .padding(.horizontal, Space.s4).frame(height: Space.headerHeight)
            Rectangle().fill(Tok.border).frame(height: 1)
            ScrollView {
                VStack(spacing: Space.s3) {
                    layoutRow(StageLayout.standard, caption: "built in")
                    ForEach(stage.customLayouts) { layoutRow($0, caption: "yours") }
                }
                .padding(Space.s4)
            }
            .accessibilityLabel("Layouts")
            HStack {
                Button { if let made = stage.duplicateLayout(layoutID) { layoutID = made.id } } label: { Text("Duplicate") }
                    .buttonStyle(HeaderButtonStyle())
                Button { pendingDelete = true } label: { Text("Delete…") }.buttonStyle(HeaderButtonStyle()).disabled(!editable)
            }
            .padding(Space.s4)
            // UI-003: the stage message composer is here too (the design's Stage mode), the same one the Show inspector has.
            Rectangle().fill(Tok.border).frame(height: 1)
            StageMessageView(stage: stage).padding(Space.s4)
        }
        .background(Tok.surface)
    }

    private func layoutRow(_ l: StageLayout, caption: String) -> some View {
        let selected = l.id == layoutID
        return Button { layoutID = l.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                ScenePreview(scene: stage.sampleScene(for: l), width: 320, cached: true)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                HStack(spacing: 6) {
                    Text(l.name).font(.wf(13, .semibold)).lineLimit(1)
                    Text(caption).font(.wf(12)).foregroundStyle(Tok.muted)
                }
            }
            .padding(Space.s3)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(selected ? Tok.borderStrong : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(l.name), \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The layout name with its role chip, and the element buttons (the design's header).
    private var topBar: some View {
        HStack(spacing: Space.s3) {
            Text(layout.name).font(.wf(18, .bold)).lineLimit(1)
            Badge(text: "STAGE", style: .outline(Tok.roleStage))
            Spacer()
            ForEach(NewStageElement.allCases) { template in
                Button { elementID = stage.addElement(template, to: layoutID) ?? elementID } label: {
                    Label(template.title, systemImage: Self.symbol(template))
                }
                .buttonStyle(HeaderButtonStyle()).disabled(!editable)
                .accessibilityLabel("Add \(template.title)")
            }
        }
        .padding(.horizontal, Space.s5).frame(height: Space.headerHeight)
    }

    private static func symbol(_ t: NewStageElement) -> String {
        switch t.title {
        case "Clock": "clock"
        case "Timer": "timer"
        case "Message": "bubble.left"
        case "Notes": "note.text"
        default: "textformat"
        }
    }

    // MARK: Right column

    private var rightColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspector.padding(Space.s5).frame(minHeight: 120, alignment: .topLeading)
                Rectangle().fill(Tok.border).frame(height: 1)
                VStack(alignment: .leading, spacing: Space.s3) {
                    SectionLabel("Elements")
                    ForEach(layout.elements) { e in
                        Button { elementID = e.id } label: {
                            Text(StageCanvas.title(of: e, in: stage)).font(.wf(13)).frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Space.s3).frame(height: 28)
                                .background(e.id == elementID ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(e.id == elementID ? .isSelected : [])
                    }
                }.padding(Space.s5)
                Rectangle().fill(Tok.border).frame(height: 1)
                VStack(alignment: .leading, spacing: Space.s3) {
                    SectionLabel("Assigned to")
                    let assigned = app.profiles.filter { $0.role == .stage && stage.layoutID(forScreen: $0.id) == layoutID }
                    if assigned.isEmpty {
                        Text("No stage screen uses this layout. Choose it for a stage screen in Screens.").font(.wf(12)).foregroundStyle(Tok.muted)
                    }
                    ForEach(assigned) { p in
                        HStack(spacing: 6) {
                            Circle().fill(Tok.roleStage).frame(width: 8, height: 8)
                            Text("\(p.name) · \(app.destinationName(p.destination))").font(.wf(13)).lineLimit(2)
                        }
                    }
                    Text("Speaker notes and stage messages never appear on Audience or Broadcast screens. Themes, Looks and props do not apply to stage layouts.")
                        .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(Space.s5)
                Rectangle().fill(Tok.border).frame(height: 1)
                TimersPanel(app: app, stage: stage).padding(Space.s5)
            }
        }
        .background(Tok.surface)
    }

    private func nextName(_ base: String) -> String {
        let used = Set(stage.layouts.map { $0.name.lowercased() })
        if !used.contains(base.lowercased()) { return base }
        var n = 2
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    @ViewBuilder private var header: some View {
        if editable {
            HStack {
                Text("Name").font(.wfSmall).foregroundStyle(.secondary)
                TextField("Name", text: $nameText).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                    .onSubmit { stage.renameLayout(layoutID, to: nameText) }
                Button("Rename") { stage.renameLayout(layoutID, to: nameText) }.disabled(nameText == layout.name)
            }
        } else {
            HStack {
                Text("\"\(layout.name)\" is built in and cannot be changed.").foregroundStyle(.secondary)
                Button("Duplicate to edit") { if let made = stage.duplicateLayout(layoutID) { layoutID = made.id } }
            }
        }
    }

    // MARK: Inspector

    @ViewBuilder private var inspector: some View {
        if let e = element {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(StageCanvas.title(of: e, in: stage)).font(.wfHeadline)
                    if case .timer(let current) = e.kind {
                        Picker("Timer", selection: Binding(get: { current }, set: { stage.setTimer($0, for: e.id, in: layoutID) })) {
                            ForEach(stage.timers) { Text($0.name).tag($0.id) }
                            if !stage.timers.contains(where: { $0.id == current }) { Text("(deleted timer)").tag(current) }
                        }.accessibilityLabel("Timer shown")
                    }
                    Stepper(value: Binding(get: { e.style.fontSize }, set: { stage.setFontSize($0, for: e.id, in: layoutID) }),
                            in: StageEditing.fontSizeRange, step: 4) {
                        Text("Font size \(Int(e.style.fontSize))")
                    }.accessibilityLabel("Font size")
                    ColorPicker("Colour", selection: Binding(get: { Color(e.style.color) },
                                                             set: { stage.setColor($0.rgba, for: e.id, in: layoutID) }))
                    Picker("Alignment", selection: Binding(get: { e.alignment }, set: { stage.setAlignment($0, for: e.id, in: layoutID) })) {
                        Text("Left").tag(StageAlignment.leading)
                        Text("Centre").tag(StageAlignment.center)
                        Text("Right").tag(StageAlignment.trailing)
                    }.pickerStyle(.segmented).accessibilityLabel("Alignment")
                    if e.kind == .currentSlide || e.kind == .nextSlide {
                        Toggle("Show second language", isOn: Binding(get: { e.showsSecondLanguage },
                                                                     set: { stage.setShowsSecondLanguage($0, for: e.id, in: layoutID) }))
                            .toggleStyle(.wfCheckbox)
                    }
                    Text("Position and size, in percent of the screen").font(.wfSmall).foregroundStyle(.secondary)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                        GridRow { percent("Left", e, \.x); percent("Top", e, \.y) }
                        GridRow { percent("Width", e, \.width); percent("Height", e, \.height) }
                    }
                    Button("Delete element", role: .destructive) {
                        stage.removeElement(e.id, from: layoutID)
                        elementID = nil
                    }
                }
                .disabled(!editable)
                .padding(.trailing, 8)
            }
        } else {
            Text(editable ? "Choose an element on the canvas, or add one." : "Choose an element to see its settings.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func percent(_ label: String, _ e: StageElement, _ keyPath: WritableKeyPath<NormalizedRect, Double>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.wfSmall).frame(width: 44, alignment: .leading)
            TextField(label, value: Binding(get: { e.frame[keyPath: keyPath] * 100 }, set: { value in
                var f = e.frame
                f[keyPath: keyPath] = value / 100
                stage.setFrame(e.id, in: layoutID, x: f.x, y: f.y, width: f.width, height: f.height)
            }), format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder).frame(width: 58)
                .accessibilityLabel("\(label) percent")
        }
    }
}

/// The layout drawn by the compositor with sample content, and a box over each element that can be dragged and resized.
struct StageCanvas: View {
    let stage: StageModel
    let layout: StageLayout
    let editable: Bool
    @Binding var selection: UUID?

    static func title(of element: StageElement, in stage: StageModel) -> String {
        switch element.kind {
        case .currentSlide: "Current slide"
        case .nextSlide: "Next slide"
        case .timeOfDay: "Clock"
        case .message: "Message"
        case .notes: "Notes"
        case .timer(let id): "Timer: " + (stage.timers.first { $0.id == id }?.name ?? "deleted timer")
        case .firstCountdown: "Timer: first countdown"
        }
    }

    var body: some View {
        ScenePreview(scene: stage.sampleScene(for: layout), width: 720, cached: false)
            .overlay {
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(layout.elements) { element in
                            ElementBox(stage: stage, layoutID: layout.id, element: element, editable: editable,
                                       canvas: geo.size, selected: selection == element.id) { selection = element.id }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { selection = nil }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
    }
}

private struct ElementBox: View {
    let stage: StageModel
    let layoutID: UUID
    let element: StageElement
    let editable: Bool
    let canvas: CGSize
    let selected: Bool
    let select: () -> Void
    /// The frame when the current drag began, so a drag is measured from there and clamped by the model.
    @State private var dragStart: NormalizedRect?
    @State private var resizeStart: NormalizedRect?

    private let handle: CGFloat = 12

    var body: some View {
        let f = element.frame
        let size = CGSize(width: f.width * canvas.width, height: f.height * canvas.height)
        ZStack(alignment: .bottomTrailing) {
            Rectangle()
                .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay(Rectangle().stroke(selected ? Color.accentColor : Color.white.opacity(0.45),
                                            style: StrokeStyle(lineWidth: selected ? 2 : 1, dash: selected ? [] : [4, 3])))
                .contentShape(Rectangle())
                .onTapGesture(perform: select)
                .gesture(DragGesture(minimumDistance: 3).onChanged { value in
                    guard editable else { return }
                    if dragStart == nil { dragStart = element.frame; select() }
                    stage.moveElement(element.id, in: layoutID, from: dragStart ?? element.frame,
                                      dx: value.translation.width / canvas.width, dy: value.translation.height / canvas.height)
                }.onEnded { _ in dragStart = nil })
            if selected && editable {
                Rectangle().fill(Color.accentColor).frame(width: handle, height: handle)
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        if resizeStart == nil { resizeStart = element.frame }
                        stage.resizeElement(element.id, in: layoutID, from: resizeStart ?? element.frame,
                                            dWidth: value.translation.width / canvas.width,
                                            dHeight: value.translation.height / canvas.height)
                    }.onEnded { _ in resizeStart = nil })
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size.width, height: size.height)
        .offset(x: f.x * canvas.width, y: f.y * canvas.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Element: \(StageCanvas.title(of: element, in: stage))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select() }
    }
}
