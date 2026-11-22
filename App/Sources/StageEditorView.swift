// STAGE-001b (LIVE-01, SCRN-03) / UI-001 / UI-005e: the stage layout editor, the Stage mode, drawn to `docs/UI/screens/04-stage.png`:
// the layout list and the stage message on the left, the bar, the canvas and its caption in the middle, the element inspector, the
// element list and the screens that use the layout on the right (`StageInspector.swift`). Every change is saved at once; the canvas is
// drawn by the same compositor the screens use. The rules (clamping, read-only, saving) live in `StageModel`; this file only draws and
// forwards gestures. A layout is edited only when it is the operator's own (the built-in one is read-only: Duplicate it to edit).
import SwiftUI
import AppKit
import Domain
import OperatorCore

struct StageEditorView: View {
    let app: AppModel
    @Bindable var stage: StageModel
    @State private var layoutID = StageLayout.standardID
    @State private var elementID: UUID?
    @State private var nameText = ""
    @State private var pendingDelete = false
    @State private var showTimers = false
    @FocusState private var nameFocused: Bool

    private var layout: StageLayout { stage.layout(withID: layoutID) ?? StageLayout.standard }
    private var editable: Bool { stage.isEditable(layoutID) }
    private var element: StageElement? { layout.elements.first { $0.id == elementID } }
    /// The operator's layouts first, then the built-in one (the fallback every stage screen starts on).
    private var listed: [(layout: StageLayout, caption: String)] {
        stage.customLayouts.map { ($0, "yours") } + [(StageLayout.standard, "built in")]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = stage.lastError { ErrorBar(message: error) { stage.dismissError() } }
            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 0) { sidebar.frame(width: 229); Rectangle().fill(Tok.border).frame(width: 1) }.wfRect("st.side")
                VStack(spacing: 0) {
                    VStack(spacing: 0) { topBar; Rectangle().fill(Tok.border).frame(height: 1) }.wfRect("st.bar")
                    canvasArea
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 0) {
                    Rectangle().fill(Tok.border).frame(width: 1)
                    StageInspector(app: app, stage: stage, layout: layout, editable: editable, elementID: $elementID, layoutID: layoutID).frame(width: 299)
                }.wfRect("st.insp")
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Tok.bg)
        .onAppear {
            #if DEBUG || WF_MEASURE
            if let name = StageDesignSeed.openLayoutName, let match = stage.customLayouts.first(where: { $0.name == name }) { layoutID = match.id }
            #endif
            nameText = layout.name
            if elementID == nil { elementID = layout.elements.first?.id }
        }
        .onChange(of: layoutID) { _, _ in
            elementID = layout.elements.first?.id
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
        .sheet(isPresented: $showTimers) {
            VStack(alignment: .leading, spacing: 12) {
                TimersPanel(app: app, stage: stage)
                HStack { Spacer(); Button("Done") { showTimers = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(Space.s6).frame(width: 460)
        }
    }

    // MARK: Left column

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                SectionLabel("Stage layouts", rectID: "st.side.h")
                Spacer()
                Button { if let made = stage.createLayout(name: nextName("My layout")) { layoutID = made.id } } label: {
                    Image(systemName: "plus").font(.wf(11, .medium)).foregroundStyle(Tok.muted).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain).help("A new layout that starts as a copy of Standard").accessibilityLabel("New layout")
                .wfRect("st.side.plus")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Rectangle().fill(Tok.border).frame(height: 1)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(listed.enumerated()), id: \.element.layout.id) { index, row in layoutRow(row.layout, caption: row.caption, index: index) }
                    layoutActions.padding(.top, 8)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .accessibilityLabel("Layouts")
            Rectangle().fill(Tok.border).frame(height: 1)
            StageComposerView(stage: stage)
        }
        .background(Tok.surface)
    }

    private func layoutRow(_ l: StageLayout, caption: String, index: Int) -> some View {
        let selected = l.id == layoutID
        return Button { layoutID = l.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                ScenePreview(scene: stage.sampleScene(for: l), width: 400, cached: true)
                    .frame(width: 189)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(Tok.border, lineWidth: 1))
                    .wfRect("st.side.card.\(index).thumb", radius: Radius.sm)
                HStack(spacing: 6) {
                    Text(l.name).font(.wf(11, .semibold)).foregroundStyle(Tok.text).lineLimit(1)
                    Text(caption).font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1)
                }
                .wfLine().frame(maxWidth: .infinity, alignment: .leading)
                .wfRect("st.side.card.\(index).cap", size: 11, weight: 400).padding(.top, 5)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
            .wfRect("st.side.card.\(index)", radius: Radius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(l.name), \(caption)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The owner's extras that the design has no place for: they follow the last layout in the list, so no designed row moves.
    private var layoutActions: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button("Duplicate") { if let made = stage.duplicateLayout(layoutID) { layoutID = made.id } }.buttonStyle(HeaderButtonStyle()).fixedSize()
                Button("Delete…") { pendingDelete = true }.buttonStyle(HeaderButtonStyle()).disabled(!editable).fixedSize()
                Spacer(minLength: 0)
            }
            HStack {
                Button("Timers…") { showTimers = true }.buttonStyle(HeaderButtonStyle()).fixedSize().help("Add, start and stop the timers the Timer element shows")
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Middle

    /// The layout name (editable for the operator's own layouts) with its role chip, and the element buttons (the design's bar). The design's
    /// Video button is not drawn (no video element exists); its place at the right end is kept so the others line up. Notes, which the design
    /// does not draw, is the first button.
    private var topBar: some View {
        HStack(spacing: Space.s3) {
            title
            Badge(text: "STAGE", style: .outline(Tok.roleStage), rectID: "st.bar.badge")
            Spacer(minLength: 0)
            addButton(.notes, title: "Notes", symbol: "note.text", rectID: "st.bar.notes")
            addButton(.currentSlide, title: "Current", symbol: "textformat", rectID: "st.bar.current")
            addButton(.nextSlide, title: "Next", symbol: "textformat", rectID: "st.bar.next")
            addButton(.timeOfDay, title: "Clock", symbol: "clock", rectID: "st.bar.clock")
            addButton(.timer, title: "Timer", symbol: "timer", rectID: "st.bar.timer")
            addButton(.message, title: "Message", symbol: "bubble.left", rectID: "st.bar.message")
            Color.clear.frame(width: 76.1, height: Space.controlHeight)      // where the design's Video button is
        }
        .padding(.horizontal, Space.s5).padding(.vertical, 8)
        .frame(height: 42)
        .background(Tok.surface)
    }

    @ViewBuilder private var title: some View {
        if editable {
            Text(nameText.isEmpty ? " " : nameText).font(.wf(15, .bold)).lineLimit(1).opacity(0)
                .overlay(alignment: .leading) {
                    TextField("Layout name", text: $nameText).textFieldStyle(.plain).font(.wf(15, .bold)).focused($nameFocused)
                        .onSubmit { stage.renameLayout(layoutID, to: nameText) }
                        .onChange(of: nameFocused) { _, focused in if !focused, nameText != layout.name { stage.renameLayout(layoutID, to: nameText) } }
                        .accessibilityLabel("Layout name")
                }
                .fixedSize().frame(height: 16).wfRect("st.bar.title", size: 15, weight: 700)
        } else {
            Text(layout.name).font(.wf(15, .bold)).lineLimit(1).wfLine().fixedSize().wfRect("st.bar.title", size: 15, weight: 700)
        }
    }

    private func addButton(_ template: NewStageElement, title: String, symbol: String, rectID: String) -> some View {
        Button { elementID = stage.addElement(template, to: layoutID) ?? elementID } label: {
            HStack(spacing: 6) { Image(systemName: symbol).frame(width: 15, height: 15); Text(title) }
        }
        .buttonStyle(HeaderButtonStyle()).disabled(!editable)
        .wfRect(rectID, size: 12, weight: 500, radius: Radius.md)
        .help(editable ? "Add a \(template.title.lowercased()) element" : StageModel.readOnlyMessage)
        .accessibilityLabel("Add \(template.title)")
    }

    private var canvasArea: some View {
        ZStack {
            StageCanvas(stage: stage, layout: layout, editable: editable, selection: $elementID)
                .frame(maxWidth: 820).padding(.horizontal, Space.s6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 8) {
                // A built-in layout cannot be changed: say so quietly, with Duplicate one click away (a drag on it changes nothing).
                Text(editable ? "Sample words, clock, message and notes are shown here. Drag a box to move it, any of its eight handles to resize, arrow keys to nudge."
                              : "Built in. Duplicate to edit.")
                    .font(.wfMono(11)).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
                    .wfRect("st.cv.caption", size: 11, weight: 400)
                if !editable {
                    Button("Duplicate") { if let made = stage.duplicateLayout(layoutID) { layoutID = made.id } }
                        .buttonStyle(HeaderButtonStyle()).fixedSize().help("Make your own copy of this layout and edit that")
                }
            }
            .padding(.leading, Space.s5).padding(.bottom, 10)
        }
    }

    private func nextName(_ base: String) -> String {
        let used = Set(stage.layouts.map { $0.name.lowercased() })
        if !used.contains(base.lowercased()) { return base }
        var n = 2
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}

/// The names the editor gives an element: the canvas label, the element list and the inspector heading.
@MainActor enum StageElementNames {
    static func title(of element: StageElement, in stage: StageModel) -> String {
        switch element.kind {
        case .currentSlide: "Current slide"
        case .nextSlide: "Next slide"
        case .timeOfDay: "Clock"
        case .message: "Stage message"
        case .notes: "Notes"
        case .timer(let id): "Timer · " + (stage.timers.first { $0.id == id }?.name ?? "deleted timer")
        case .firstCountdown: "Timer · first countdown"
        }
    }
    /// The small label over the element on the canvas.
    static func canvasLabel(of element: StageElement, in stage: StageModel) -> String {
        if element.kind == .currentSlide { return "Current slide" + (element.showsSecondLanguage ? " · both languages" : "") }
        return title(of: element, in: stage)
    }
    static func symbol(of element: StageElement) -> String {
        switch element.kind {
        case .currentSlide, .nextSlide: "textformat"
        case .timeOfDay: "clock"
        case .timer, .firstCountdown: "timer"
        case .message: "bubble.left"
        case .notes: "note.text"
        }
    }
}

