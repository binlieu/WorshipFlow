// OUT-004 / PRES-02 / PRES-07 / PRES-08: the open presentation (slide grid and editor) or the search results.
import SwiftUI
import Domain
import OperatorCore

struct CentrePane: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        // Search lives at the top of the sidebar's Libraries section (UI-003); this pane is the open presentation only.
        if workspace.openPresentationID == nil {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(Tok.muted)
                Text("Choose a song from the library or the playlist").font(.title3)
                Text("Command-N makes a new presentation. Command-I imports lyrics. Command-F searches.")
                    .font(.caption).foregroundStyle(Tok.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                ShowHeader(app: app, workspace: workspace)
                Divider()
                if app.ui.gridAsList { SlideList(app: app, workspace: workspace) } else { SlideGrid(app: app, workspace: workspace) }
            }
        }
    }
}

/// The Show mode's header: title, arrangement, language marker, Add slide, Re-flow, Quick edit, grid or list.
struct ShowHeader: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    private var presentation: Presentation? { workspace.presentations.first { $0.id == workspace.openPresentationID } }

    var body: some View {
        AdaptiveHeader(labelledWidth: 660) { compact in header(compact: compact) }
            .padding(.horizontal, Space.s5)
            .onAppear { title = presentation?.title ?? "" }
            .onChange(of: workspace.openPresentationID) { _, _ in title = presentation?.title ?? "" }
            .onChange(of: presentation?.title) { _, new in if !titleFocused { title = new ?? "" } }
            .onChange(of: app.ui.focusTitle) { _, _ in titleFocused = true }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: Space.s3) {
            TextField("Title", text: $title)
                .textFieldStyle(.plain).font(.system(size: 20, weight: .bold)).frame(minWidth: 80, maxWidth: 300)
                .focused($titleFocused)
                .layoutPriority(-1)
                .onSubmit { commitTitle() }
                .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
                .accessibilityLabel("Presentation title")
            if let itemID = workspace.selectedPlaylistItemID, let item = workspace.playlistItems.first(where: { $0.id == itemID }), item.kind == .presentation {
                Menu {
                    Button("Natural order") { Task { await workspace.setArrangement(nil, forPlaylistItem: itemID) } }
                    ForEach(workspace.arrangements) { a in
                        Button(a.name) { Task { await workspace.setArrangement(a.id, forPlaylistItem: itemID) } }
                    }
                } label: {
                    Text("Arrangement: \(workspace.arrangements.first { $0.id == item.arrangementID }?.name ?? "Natural order")")
                        .lineLimit(1)
                }
                .menuStyle(.button).fixedSize()
                .help("The section order this playlist item plays")
            }
            if let id = workspace.openPresentationID, workspace.bilingualPresentationIDs.contains(id) {
                Badge(text: "EN + VI", style: .outline(Tok.borderStrong)).foregroundStyle(Tok.muted)
                    .accessibilityLabel("Two languages")
            }
            Spacer(minLength: 4)
            controls(compact: compact).fixedSize()
        }
    }

    /// The header buttons with words, or (when the window is narrow) as icons with help text.
    private func controls(compact: Bool) -> some View {
        HStack(spacing: Space.s3) {
            HeaderControlButton(control: .addSlide, symbol: "plus", compact: compact) { Task { await workspace.addSlide(SlideContent(primary: "")) } }
            HeaderControlButton(control: .reflow, symbol: "text.alignleft", compact: compact) {
                if let id = workspace.openPresentationID { app.openImport(existing: id) }
            }
            HeaderControlButton(control: .addToPlaylist, symbol: "text.badge.plus", compact: true) {
                if let id = workspace.openPresentationID { Task { await workspace.addToPlaylist(id) } }
            }
            HeaderControlButton(control: .quickEdit, symbol: "pencil", compact: compact) { app.openQuickEdit() }
                .disabled(workspace.slides.isEmpty)
            Picker("View", selection: Binding(get: { app.ui.gridAsList }, set: { app.ui.gridAsList = $0 })) {
                Image(systemName: "square.grid.2x2").tag(false).accessibilityLabel("Grid")
                Image(systemName: "list.bullet").tag(true).accessibilityLabel("List")
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize().accessibilityLabel("Slide view")
        }
    }

    private func commitTitle() {
        guard let p = presentation else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { title = p.title; return }
        if trimmed != p.title { Task { await workspace.renamePresentation(id: p.id, to: trimmed) } }
    }
}

// MARK: Slide grid

/// Shared by the grid and the list: the sections of the open presentation, repeats counted.
@MainActor func sectionRuns(_ workspace: WorkspaceModel) -> [SectionRun] {
    SectionRuns.runs(slideGroupIDs: workspace.slides.map(\.groupID), groups: workspace.groups,
                     groupSlideCounts: workspace.groupSlideCounts)
}

private struct SectionHeader: View {
    let run: SectionRun
    var body: some View {
        if let name = run.name {
            HStack(spacing: 6) {
                Circle().fill(run.tone.color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(run.tone.color)
                if run.repeatCount > 1 { Text("× \(run.repeatCount)").font(.system(size: 12)).foregroundStyle(Tok.muted) }
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(run.repeatCount > 1 ? "\(name), played \(run.repeatCount) times" : name)
            .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The live slide's index, only while what is live is the presentation that is open.
@MainActor private func liveIndex(_ app: AppModel, _ workspace: WorkspaceModel) -> Int? {
    guard app.show.liveDeck?.presentationID == workspace.openPresentationID else { return nil }
    return app.show.liveIndex
}

struct SlideGrid: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var pendingDelete: Int?

    /// Red means on screen now: while cleared or blacked out the live place is marked in the warning colour instead.
    private var ringColor: Color { app.mode == .live ? Tok.liveFill : Tok.warning }

    var body: some View {
        GeometryReader { geo in grid(width: geo.size.width) }
            .frame(minHeight: 140)
            .background(Tok.bg)
            .confirmationDialog("Delete this slide?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete slide", role: .destructive) {
                    if let i = pendingDelete { Task { await workspace.deleteSlide(at: i) } }
                }
                Button("Cancel", role: .cancel) {}
            }
    }

    /// Five thumbnails across at the design's window size, more when wider, never fewer than one (`SlideGridLayout`).
    private func columns(for width: CGFloat) -> [GridItem] {
        let count = SlideGridLayout.columnCount(width: Double(width))
        return Array(repeating: GridItem(.flexible(minimum: 100, maximum: 300), spacing: SlideGridLayout.spacing, alignment: .top), count: count)
    }

    @ViewBuilder private func grid(width: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if workspace.slides.isEmpty {
                    Text("This presentation has no slides. Use Add slide, or Reflow to paste the words.")
                        .foregroundStyle(Tok.muted).padding(24)
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(sectionRuns(workspace)) { run in
                        SectionHeader(run: run)
                        LazyVGrid(columns: columns(for: width), alignment: .leading, spacing: SlideGridLayout.spacing) {
                            ForEach(run.indices, id: \.self) { i in
                                cell(i, color: run.tone.color).id(i)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.s5)
            }
            .onChange(of: workspace.show.selectedIndex) { _, new in withAnimation { proxy.scrollTo(new) } }
        }
    }

    private func cell(_ i: Int, color: Color) -> some View {
        let slide = workspace.slides[i]
        let selected = workspace.show.selectedIndex == i
        let live = liveIndex(app, workspace) == i
        return VStack(alignment: .leading, spacing: 4) {
            // The rings are drawn outside the picture (never over the words): blue for preview, 3 pt red for live.
            SlideThumbnail(app: app, slide: slide.content)
                .overlay(alignment: .topLeading) { tags(live: live, selected: selected).padding(5) }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.blue : .clear, lineWidth: 2))
                .padding(live ? 4 : 0)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(live ? ringColor : .clear, lineWidth: 3))
            HStack(spacing: 6) {
                Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(Tok.text)
                Text(slide.content.primary.split(whereSeparator: \.isNewline).first.map(String.init) ?? "")
                    .font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.triggerSlide(i) }
        .onTapGesture { workspace.selectSlide(i) }
        .draggable("\(i)")
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let from = Int(text), from != i else { return false }
            Task { await workspace.moveSlide(from: from, to: i) }
            return true
        }
        .contextMenu { slideMenu(i) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)")
        .accessibilityValue(stateWord(live: live, selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func tags(live: Bool, selected: Bool) -> some View {
        if live {
            switch app.mode {
            case .cleared: Badge(text: "CLEARED", style: .warning)
            case .blackout: Badge(text: "BLACKOUT", style: .warning)
            default: Badge(text: "LIVE", style: .live)
            }
        } else if selected {
            Badge(text: "PREVIEW", style: .preview)
        }
    }

    private func stateWord(live: Bool, selected: Bool) -> String {
        var words: [String] = []
        if live { words.append(app.mode == .cleared ? "live place, cleared" : (app.mode == .blackout ? "live place, blackout" : "live")) }
        if selected { words.append("in preview") }
        return words.joined(separator: ", ")
    }

    @ViewBuilder private func slideMenu(_ i: Int) -> some View {
        Button("Go Live") { app.triggerSlide(i) }
        Button("Quick edit") { workspace.selectSlide(i); app.openQuickEdit() }
        Divider()
        Button("Move earlier") { Task { await workspace.moveSlide(from: i, to: i - 1) } }.disabled(i == 0)
        Button("Move later") { Task { await workspace.moveSlide(from: i, to: i + 1) } }.disabled(i == workspace.slides.count - 1)
        Divider()
        Button("Delete slide…", role: .destructive) { pendingDelete = i }
    }
}

/// The list form of the grid: one row per slide.
struct SlideList: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    private var ringColor: Color { app.mode == .live ? Tok.liveFill : Tok.warning }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sectionRuns(workspace)) { run in
                    SectionHeader(run: run).padding(.horizontal, Space.s3)
                    ForEach(run.indices, id: \.self) { i in row(i, color: run.tone.color) }
                }
            }
            .padding(Space.s3)
        }
        .background(Tok.bg)
    }

    private func row(_ i: Int, color: Color) -> some View {
        let slide = workspace.slides[i]
        let selected = workspace.show.selectedIndex == i
        let live = liveIndex(app, workspace) == i
        return HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: 3, height: 16)
            Text("\(i + 1)").font(.system(size: 12, weight: .bold).monospacedDigit()).frame(width: 24, alignment: .trailing)
            Text(slide.content.primary.replacingOccurrences(of: "\n", with: " ")).lineLimit(1)
            Spacer()
            if live { Badge(text: app.mode == .live ? "LIVE" : app.mode == .blackout ? "BLACKOUT" : "CLEARED", style: app.mode == .live ? .live : .warning) }
            if selected { Badge(text: "PREVIEW", style: .preview) }
        }
        .padding(.horizontal, Space.s3).frame(height: 30)
        .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(live ? ringColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { app.triggerSlide(i) }
        .onTapGesture { workspace.selectSlide(i) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Editors

/// Three fields that keep the slide's objects: only the text changes.
struct WordsFields: View {
    @Bindable var workspace: WorkspaceModel
    let slide: Slide
    var minHeight: CGFloat = 90

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            field("First language", text: Binding(
                get: { slide.content.primary },
                set: { new in
                    var content = slide.content
                    content.primary = new
                    workspace.editSlide(id: slide.id, content: content)
                }))
            field("Second language", text: Binding(
                get: { slide.content.secondary ?? "" },
                set: { new in
                    var content = slide.content
                    content.secondary = new.isEmpty ? nil : new
                    workspace.editSlide(id: slide.id, content: content)
                }))
            field("Speaker notes — stage screens only", text: Binding(
                get: { slide.notes },
                set: { workspace.editSlide(id: slide.id, content: slide.content, notes: $0) }))
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        WordsEditorField(label: label, text: text, minHeight: minHeight)
    }
}

/// One multi-line words field: used by the Edit mode's three fields and by the Quick edit tab.
struct WordsEditorField: View {
    let label: String
    @Binding var text: String
    var minHeight: CGFloat = 52

    var body: some View {
        TextEditor(text: $text).font(.system(size: 13)).scrollContentBackground(.hidden)
            .padding(4)
            .frame(minHeight: minHeight)
            .background(Tok.bg, in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(label).font(.system(size: 13)).foregroundStyle(Tok.muted).padding(.horizontal, 9).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(label)
    }
}

/// The Edit mode's editor: the words row, then the objects canvas with its inspector, at full size.
struct SlideEditor: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        let index = workspace.show.selectedIndex
        VStack(alignment: .leading, spacing: 8) {
            if workspace.slides.indices.contains(index) {
                HStack {
                    Text("Slide \(index + 1) of \(workspace.slides.count)").font(.headline)
                    Spacer()
                    Text("Editing here changes the preview only. The audience sees the change when you go live again.")
                        .font(.caption).foregroundStyle(Tok.muted).lineLimit(2)
                }
                WordsFields(workspace: workspace, slide: workspace.slides[index], minHeight: 64)
                    .frame(height: 96)
                if let editor = app.slideEditor {
                    SlideObjectsEditor(app: app, editor: editor)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Text("Select a slide to edit it.").foregroundStyle(Tok.muted)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
    }
}
