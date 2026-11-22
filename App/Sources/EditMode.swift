// UI-001 / ADR-0007 and UI-005c: the Edit mode, laid out as docs/UI/mockups/02-editor.html draws it: a 200 pt filmstrip, a centre with the object
// bar, the live strip and the canvas, and a 320 pt inspector with the tabs Object, Slide and Theme (no transport bar in this mode).
// UI-006c added Align, the Audience / Stage / Broadcast preview, the zoom field and the "Saved ... ago" words. The control whose feature still
// does not exist (Video) keeps its room; see AI/reports/UI-005c-report.md and AI/reports/UI-006c-report.md.
import SwiftUI
import Domain
import OperatorCore

struct EditModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    /// UI-006c: which screen's composition the canvas draws (view state only: nothing stored, nothing live), the canvas zoom, and the
    /// width the canvas really has now (so the zoom field can say the true percentage while it is on Fit).
    @State private var previewRole: EditPreviewRole = .audience
    @State private var zoom: EditZoom = .fit
    @State private var shownCanvasWidth: Double = 800

    var body: some View {
        if workspace.openPresentationID == nil {
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.list.clipboard").font(.wfLargeTitle).foregroundStyle(Tok.muted)
                Text("Open a song to edit it").font(.wfTitle3)
                Text("Choose one in Show (Command-1), or press Command-N for a new presentation.")
                    .font(.wfSmall).foregroundStyle(Tok.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                filmstrip.frame(width: 200)
                VStack(spacing: 0) {
                    objectBar
                    status
                    if let editor = app.slideEditor, workspace.slides.indices.contains(workspace.showParts.selectedIndex) {
                        EditCanvasArea(app: app, workspace: workspace, editor: editor, role: previewRole, zoom: zoom, shownWidth: $shownCanvasWidth)
                    } else {
                        Text("Select a slide to edit it.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
                .wfRect("ed.main")
                if let editor = app.slideEditor { EditInspector(app: app, workspace: workspace, editor: editor).frame(width: 320) }
            }
            #if DEBUG || WF_MEASURE
            // UI-006c debug hook (the screen may be locked, so clicks cannot drive these): "stage", "broadcast", "audience" and "zoom:100" etc.
            .onReceive(NotificationCenter.default.publisher(for: .init("wf.debug.editPreview"))) { note in
                guard let word = note.object as? String else { return }
                if let role = EditPreviewRole(rawValue: word) { previewRole = role }
                if word.hasPrefix("zoom:"), let z = EditZoom.allCases.first(where: { $0.title == String(word.dropFirst(5)) }) { zoom = z }
            }
            #endif
        }
    }

    // MARK: Filmstrip (`.side` 200: a header row, then the strip)

    private var filmstrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text((workspace.presentations.first { $0.id == workspace.openPresentationID }?.title ?? "Slides").uppercased())
                    .font(.wfSectionLabel).tracking(0.66).foregroundStyle(Tok.muted).lineLimit(1).wfLine()
                    .wfRect("ed.fs.title", size: 11, weight: 600)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button { Task { await workspace.addSlide(SlideContent(primary: "")) } } label: {
                    Image(systemName: "plus").font(.wf(11)).frame(width: 12, height: 12).foregroundStyle(Tok.muted)
                        .wfRect("ed.fs.plus")
                }
                .buttonStyle(.plain).help("Add slide").accessibilityLabel("Add slide")
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .wfRect("ed.fs.head")
            // FIX-S (KI-193): one snapshot of the slides; the cells carry their slide (`CellSlot`) and never index the model's list.
            let slides = workspace.slides
            let keys = SlideCellKey.keys(for: slides.map(\.id))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sectionRuns(workspace).enumerated()), id: \.element.id) { runIndex, run in
                        if let name = run.name {
                            Text(name.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(run.tone.color).wfLine()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .wfRect("ed.fs.sec.\(runIndex)", size: 11, weight: 600)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(run.indices.compactMap { CellSlot(at: $0, slides: slides, keys: keys) }) { slot in filmCell(slot) }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .scrollIndicators(.never)          // the design's strip has no bar, and a classic one would take 15 pt of the 175 pt thumbnails
        }
        .padding(.trailing, 1)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Tok.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Tok.border).frame(width: 1) }
        .wfRect("ed.fs")
    }

    private func filmCell(_ slot: CellSlot) -> some View {
        let (i, slide) = (slot.index, slot.slide)
        let selected = workspace.showParts.selectedIndex == i
        let live = app.showParts.liveDeckID == workspace.openPresentationID && app.showParts.liveIndex == i
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(i + 1)").font(.wf(11, .semibold)).foregroundStyle(Tok.text).wfLine()
                .wfRect("ed.fs.num.\(i)", size: 11, weight: 600)
            SlideThumbnail(app: app, slide: slide.content)
                .overlay(alignment: .bottomTrailing) { OwnBackgroundMark(content: slide.content, available: app.media.map { Set($0.allAssets.map(\.id)) }).padding(4) }
                .wfRect("ed.fs.thumb.\(i)", radius: 4)
                .wfThumbState(preview: selected && !live, live: live, liveColor: app.mode == .live ? Tok.liveFill : Tok.warning)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wfRect("ed.fs.cell.\(i)")
        .contentShape(Rectangle())
        .onTapGesture { workspace.selectSlide(i) }
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let mediaID = SlideBackgroundDrop.mediaID(fromDragText: text) else { return false }
            return app.setSlideBackground(mediaID: mediaID, slideID: slide.id)
        }
        .dropDestination(for: URL.self) { urls, _ in app.setSlideBackground(fileURLs: urls, slideID: slide.id) }
        .contextMenu { SlideBackgroundMenuItems(app: app, slide: slide) }        // FIX-I item 6
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)\(SlideBackgroundDrop.hasOwnBackground(slide.content) ? ", has its own background" : "")")
        .accessibilityValue(live ? "live" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Object bar (`.bar`: padding 8 x 14, 47 pt with its line)

    /// Text, Shape, Image, then (design) Video, a divider and Align, which are left out with their room kept, then Arrange. Undo, Redo,
    /// Duplicate and Delete (the app's, not the design's) sit at the right where the preview switch and Zoom would be.
    private var objectBar: some View {
        HStack(spacing: 8) {
            Button { app.insertObject(.textBox) } label: { barLabel("textformat", "Text") }
                .buttonStyle(HeaderButtonStyle()).disabled(!previewRole.isEditable).help("Add a text box to the selected slide").wfRect("ed.bar.text", size: 12, weight: 500, radius: 6)
            Menu {
                Button("Rectangle") { app.insertObject(.rectangle) }
                Button("Ellipse") { app.insertObject(.ellipse) }
                Button("Rounded Rectangle") { app.insertObject(.roundedRectangle) }
            } label: { barLabel("square.on.circle", "Shape") }
                .menuStyle(.button).buttonStyle(HeaderButtonStyle()).menuIndicator(.hidden).fixedSize().disabled(!previewRole.isEditable)
                .help("Add a shape to the selected slide").wfRect("ed.bar.shape", size: 12, weight: 500, radius: 6)
            Button { app.insertImage() } label: { barLabel("photo", "Image") }
                .buttonStyle(HeaderButtonStyle()).disabled(!previewRole.isEditable).help("Add an image to the selected slide").wfRect("ed.bar.image", size: 12, weight: 500, radius: 6)
            // The room of Video (76.1): a feature that does not exist yet (no video object in `SlideObject`). See the report.
            Color.clear.frame(width: 76.1, height: 1)
            Rectangle().fill(Tok.border).frame(width: 1, height: 20).wfRect("ed.bar.div").accessibilityHidden(true)
            // UI-006c: Align (to the slide), one undo step each.
            Menu {
                ForEach([ObjectAlignment.left, .centerHorizontally, .right], id: \.self) { alignItem($0) }
                Divider()
                ForEach([ObjectAlignment.top, .centerVertically, .bottom], id: \.self) { alignItem($0) }
                Divider()
                alignItem(.center)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "align.horizontal.center").frame(width: 15, height: 15)
                    Text("Align")
                    Image(systemName: "chevron.down").font(.wf(9, .semibold)).foregroundStyle(Tok.muted).frame(width: 12, height: 12)
                }
            }
            .menuStyle(.button).buttonStyle(HeaderButtonStyle()).menuIndicator(.hidden).fixedSize()
            .disabled(app.slideEditor?.selectedObjectID == nil || !previewRole.isEditable)
            .help("Align the selected object to the slide").accessibilityLabel("Align")
            .wfRect("ed.bar.align", size: 12, weight: 500, radius: 6)
            Menu {
                Button("Bring to front") { orderSelected { $0.bringToFront($1) } }
                Button("Bring forward") { orderSelected { $0.bringForward($1) } }
                Button("Send backward") { orderSelected { $0.sendBackward($1) } }
                Button("Send to back") { orderSelected { $0.sendToBack($1) } }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.3.layers.3d").frame(width: 15, height: 15)
                    Text("Arrange")
                    Image(systemName: "chevron.down").font(.wf(9, .semibold)).foregroundStyle(Tok.muted).frame(width: 12, height: 12)
                }
            }
            .menuStyle(.button).buttonStyle(HeaderButtonStyle()).menuIndicator(.hidden).fixedSize()
            .disabled(app.slideEditor?.selectedObjectID == nil || !previewRole.isEditable)
            .help("Change the stacking order of the selected object").accessibilityLabel("Arrange")
            .wfRect("ed.bar.arrange", size: 12, weight: 500, radius: 6)
            Spacer(minLength: 0)
            // UI-006c: the screen whose composition the canvas draws, and the zoom. The preview is read-only except on Audience.
            EditSegmented(items: EditPreviewRole.allCases.map { .init(value: $0, title: $0.title, label: "Preview as the \($0.title) screen") },
                          selection: $previewRole, accessibilityName: "Preview as screen", rectID: "ed.bar.role")
                .help("Draw the slide as the Audience, Stage or Broadcast screen composes it. Only Audience can be edited here.")
                .onChange(of: previewRole) { _, role in if !role.isEditable { app.slideEditor?.select(nil) } }
            EditPopup(title: "\(EditZoom.percent(forCanvasWidth: shownCanvasWidth))%", accessibilityName: "Zoom", rectID: "ed.bar.zoom") {
                ForEach(EditZoom.allCases, id: \.self) { z in
                    Button { zoom = z } label: { if z == zoom { Label(z.title, systemImage: "checkmark") } else { Text(z.title) } }
                }
            }
            .frame(minWidth: 62.2).fixedSize()
            .help("Canvas zoom, as a share of the 1920 × 1080 output")
        }
        .padding(.horizontal, 14)
        .frame(height: 46)                      // the design's bar is as tall as its Audience / Stage / Broadcast switch (30) plus 8 above and below
        .padding(.bottom, 1)                    // and its 1 pt line
        .background(Tok.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
        .wfRect("ed.bar")
    }

    private func alignItem(_ alignment: ObjectAlignment) -> some View {
        Button(alignment.title) { app.slideEditor?.alignSelected(alignment) }
    }

    private func barLabel(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 15, height: 15)
            Text(title)
        }
    }

    private func orderSelected(_ action: (SlideEditorModel, UUID) -> Void) {
        guard let editor = app.slideEditor, let id = editor.selectedObjectID else { return }
        action(editor, id)
    }

    private func historyButtons(_ editor: SlideEditorModel) -> some View {
        HStack(spacing: 4) {
            iconButton("arrow.uturn.backward", "Undo", help: "Undo (Command-Z)", enabled: editor.canUndo) { editor.undo() }
            iconButton("arrow.uturn.forward", "Redo", help: "Redo (Shift-Command-Z)", enabled: editor.canRedo) { editor.redo() }
            iconButton("plus.square.on.square", "Duplicate", help: "Duplicate (Command-D)", enabled: editor.selectedObjectID != nil) { editor.duplicateSelected() }
            iconButton("trash", "Delete", help: "Delete the selected object (Delete key)", enabled: editor.selectedObjectID != nil) { editor.deleteSelected() }
        }
    }

    private func iconButton(_ symbol: String, _ label: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        // UI-006c: the four history and object buttons moved from the bar (whose room the preview switch and zoom now take) to the strip's right,
        // as plain 12 pt icons so the strip stays the design's 29 pt.
        Button(action: action) { Image(systemName: symbol).font(.wf(12)).frame(width: 22, height: 16).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(enabled ? Tok.text : Tok.muted.opacity(0.5))
            .disabled(!enabled).help(help).accessibilityLabel(label)
    }

    // MARK: Live strip (`surface-2`, padding 6 x 14, 12 pt)

    private var status: some View {
        let editing = workspace.showParts.selectedIndex + 1
        let liveSame = app.showParts.liveDeckID == workspace.openPresentationID
        return HStack(spacing: 8) {
            Image(systemName: "lock").font(.wf(11)).frame(width: 12, height: 12).foregroundStyle(Tok.muted).wfRect("ed.strip.lock")
            if liveSame, let live = app.showParts.liveIndex {
                Text("Slide \(live + 1) is live.").font(.wf(12, .bold)).wfLine().wfRect("ed.strip.live", size: 12, weight: 700)
                Text("You are editing slide \(editing). Nothing on the screens changes until it is triggered again.")
                    .foregroundStyle(Tok.muted).wfLine().wfRect("ed.strip.note", size: 12, weight: 400)
            } else {
                Text("Nothing from this song is live.").font(.wf(12, .bold)).wfLine().wfRect("ed.strip.live", size: 12, weight: 700)
                Text("Editing changes the preview only.").foregroundStyle(Tok.muted).wfLine().wfRect("ed.strip.note", size: 12, weight: 400)
            }
            Spacer(minLength: 0)
            if let editor = app.slideEditor { historyButtons(editor) }
            EditSaveText(workspace: workspace)
        }
        .font(.wf(12)).lineLimit(1)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .padding(.bottom, 1)
        .background(Tok.surface2)
        .overlay(alignment: .bottom) { Rectangle().fill(Tok.border).frame(height: 1) }
        .wfRect("ed.strip")
    }
}
