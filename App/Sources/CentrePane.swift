// OUT-004 / PRES-02 / PRES-07 / PRES-08: the open presentation (slide grid and editor) or the search results.
import SwiftUI
import Domain
import OperatorCore

struct CentrePane: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    let query: String
    let clearQuery: () -> Void

    var body: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SearchResultsView(workspace: workspace, query: query, open: { hit in
                clearQuery()
                Task { await workspace.openSearchResult(hit) }
            })
        } else if workspace.openPresentationID == nil {
            VStack(spacing: 8) {
                Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.secondary)
                Text("Choose a song from the library or the playlist").font(.title3)
                Text("Command-N makes a new presentation. Command-I imports lyrics. Command-F searches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                PresentationHeader(app: app, workspace: workspace)
                Divider()
                SlideGrid(app: app, workspace: workspace)
                Divider()
                SlideEditor(app: app, workspace: workspace)
            }
        }
    }
}

struct SearchResultsView: View {
    let workspace: WorkspaceModel
    let query: String
    let open: (SearchHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Results for \"\(query)\"").font(.headline).padding(12)
            Divider()
            if workspace.searchResults.isEmpty {
                Text("Nothing found. Searching ignores accents and capital letters.")
                    .foregroundStyle(.secondary).padding(16)
                Spacer()
            } else {
                List(workspace.searchResults) { hit in
                    Button { open(hit) } label: {
                        HStack {
                            Image(systemName: hit.matchedTitle ? "textformat" : "text.alignleft").foregroundStyle(.secondary)
                            Text(hit.title)
                            Spacer()
                            Text(hit.matchedTitle ? "Title" : "Lyrics").font(.caption).foregroundStyle(.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct PresentationHeader: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var title = ""
    @FocusState private var titleFocused: Bool

    private var presentation: Presentation? { workspace.presentations.first { $0.id == workspace.openPresentationID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder).font(.title3.bold()).frame(maxWidth: 360)
                    .focused($titleFocused)
                    .onSubmit { commitTitle() }
                    .onChange(of: titleFocused) { _, focused in if !focused { commitTitle() } }
                Spacer()
                Button { Task { await workspace.addSlide(SlideContent(primary: "")) } } label: { Label("Add slide", systemImage: "plus.rectangle") }
                Button { if let id = workspace.openPresentationID { app.openImport(existing: id) } } label: {
                    Label("Re-flow lyrics…", systemImage: "text.alignleft")
                }
                Button {
                    if let id = workspace.openPresentationID { Task { await workspace.addToPlaylist(id) } }
                } label: { Label("Add to playlist", systemImage: "text.badge.plus") }
            }
            HStack(spacing: 10) {
                Picker("Theme", selection: Binding(get: { workspace.openThemeID },
                                                   set: { id in if let open = workspace.openPresentationID { app.setPresentationTheme(id, forPresentation: open) } })) {
                    Text("Default").tag(UUID?.none)
                    ForEach(app.themes) { Text($0.name).tag(UUID?.some($0.id)) }
                }.frame(maxWidth: 260)
                    .help("The look of this song on the audience screen")
                if let itemID = workspace.selectedPlaylistItemID,
                   let item = workspace.playlistItems.first(where: { $0.id == itemID }) {
                    Picker("Section order", selection: Binding(get: { item.arrangementID },
                                                               set: { id in Task { await workspace.setArrangement(id, forPlaylistItem: itemID) } })) {
                        Text("Natural order").tag(UUID?.none)
                        ForEach(workspace.arrangements) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.frame(maxWidth: 260)
                }
                Spacer()
            }
        }
        .padding(10)
        .onAppear { title = presentation?.title ?? "" }
        .onChange(of: workspace.openPresentationID) { _, _ in title = presentation?.title ?? "" }
        .onChange(of: presentation?.title) { _, new in if !titleFocused { title = new ?? "" } }
        .onChange(of: app.ui.focusTitle) { _, _ in titleFocused = true }
    }

    private func commitTitle() {
        guard let p = presentation else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { title = p.title; return }
        if trimmed != p.title { Task { await workspace.renamePresentation(id: p.id, to: trimmed) } }
    }
}

// MARK: Slide grid

private let groupPalette: [Color] = [.blue, .green, .orange, .purple, .teal, .pink, .indigo, .brown]

private struct SlideRun: Identifiable {
    var id: Int
    var name: String?
    var color: Color
    var indices: [Int]
}

struct SlideGrid: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @State private var pendingDelete: Int?

    private var runs: [SlideRun] {
        var result: [SlideRun] = []
        for (i, slide) in workspace.slides.enumerated() {
            if let last = result.last, last.name == name(of: slide), sameGroup(result, slide, i) {
                result[result.count - 1].indices.append(i)
            } else {
                result.append(SlideRun(id: result.count, name: name(of: slide), color: color(of: slide), indices: [i]))
            }
        }
        return result
    }

    private func sameGroup(_ runs: [SlideRun], _ slide: Slide, _ index: Int) -> Bool {
        guard let previous = runs.last?.indices.last else { return false }
        return workspace.slides[previous].groupID == slide.groupID
    }

    private func name(of slide: Slide) -> String? {
        slide.groupID.flatMap { id in workspace.groups.first { $0.id == id }?.name }
    }

    private func color(of slide: Slide) -> Color {
        guard let id = slide.groupID, let i = workspace.groups.firstIndex(where: { $0.id == id }) else { return .gray }
        return groupPalette[i % groupPalette.count]
    }

    /// The live slide's index, only while what is live is the presentation that is open.
    private var liveIndex: Int? {
        guard app.show.liveDeck?.presentationID == workspace.openPresentationID else { return nil }
        return app.show.liveIndex
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if workspace.slides.isEmpty {
                    Text("This presentation has no slides. Use Add slide, or Re-flow lyrics to paste the words.")
                        .foregroundStyle(.secondary).padding(24)
                }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(runs) { run in
                        if let name = run.name {
                            HStack(spacing: 6) {
                                Circle().fill(run.color).frame(width: 9, height: 9)
                                Text(name).font(.subheadline.bold()).foregroundStyle(run.color)
                            }
                            .padding(.top, 6)
                            .accessibilityAddTraits(.isHeader)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                            ForEach(run.indices, id: \.self) { i in
                                cell(i, color: run.color).id(i)
                            }
                        }
                    }
                }
                .padding(12)
            }
            .onChange(of: workspace.show.selectedIndex) { _, new in withAnimation { proxy.scrollTo(new) } }
        }
        .frame(minHeight: 200)
        .confirmationDialog("Delete this slide?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete slide", role: .destructive) {
                if let i = pendingDelete { Task { await workspace.deleteSlide(at: i) } }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func cell(_ i: Int, color: Color) -> some View {
        let slide = workspace.slides[i]
        let selected = workspace.show.selectedIndex == i
        let live = liveIndex == i
        return VStack(alignment: .leading, spacing: 3) {
            SlideThumbnail(app: app, slide: slide.content)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(live ? Color.red : (selected ? Color.accentColor : Color.clear), lineWidth: 3))
                .overlay(alignment: .topLeading) {
                    if live {
                        Text(app.mode == .cleared ? "CLEARED" : "LIVE").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(app.mode == .cleared ? Color.orange : Color.red, in: Capsule()).padding(4)
                    }
                }
            HStack(spacing: 4) {
                Rectangle().fill(color).frame(width: 3, height: 12)
                Text("\(i + 1)").font(.caption.monospacedDigit().bold())
                Text(slide.content.primary.replacingOccurrences(of: "\n", with: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.goLive(at: i) }
        .onTapGesture { workspace.selectSlide(i) }
        .draggable("\(i)")
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let from = Int(text), from != i else { return false }
            Task { await workspace.moveSlide(from: from, to: i) }
            return true
        }
        .contextMenu {
            Button("Go Live") { workspace.goLive(at: i) }
            Divider()
            Button("Move earlier") { Task { await workspace.moveSlide(from: i, to: i - 1) } }.disabled(i == 0)
            Button("Move later") { Task { await workspace.moveSlide(from: i, to: i + 1) } }.disabled(i == workspace.slides.count - 1)
            Divider()
            Button("Delete slide…", role: .destructive) { pendingDelete = i }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)")
        .accessibilityValue(live ? (app.mode == .cleared ? "live place, cleared" : "live") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Editor

struct SlideEditor: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        let index = workspace.show.selectedIndex
        VStack(alignment: .leading, spacing: 6) {
            if workspace.slides.indices.contains(index) {
                let slide = workspace.slides[index]
                HStack {
                    Text("Slide \(index + 1) of \(workspace.slides.count)").font(.headline)
                    Spacer()
                    Text("Editing here changes the preview only. The audience sees the change when you go live again.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    field("First language", text: Binding(
                        get: { slide.content.primary },
                        set: { workspace.editSlide(id: slide.id, content: SlideContent(primary: $0, secondary: slide.content.secondary)) }))
                    field("Second language", text: Binding(
                        get: { slide.content.secondary ?? "" },
                        set: { workspace.editSlide(id: slide.id, content: SlideContent(primary: slide.content.primary, secondary: $0.isEmpty ? nil : $0)) }))
                }
                TextField("Speaker notes", text: Binding(
                    get: { slide.notes },
                    set: { workspace.editSlide(id: slide.id, content: slide.content, notes: $0) }))
                    .textFieldStyle(.roundedBorder)
            } else {
                Text("Select a slide to edit its words.").foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(height: 220)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text).font(.body)
                .frame(minHeight: 90)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                .accessibilityLabel(label)
        }
    }
}
