// UI-001 / ADR-0007: the Edit, Media, Stage, Cues and Screens modes. Each re-homes panels that already worked; none
// of them carries new logic.
import SwiftUI
import Domain
import OperatorCore

// MARK: Edit

struct EditModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

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
                filmstrip.frame(width: 208)
                Divider()
                VStack(spacing: 0) {
                    header
                    Divider()
                    insertBar
                    Divider()
                    status
                    Divider()
                    SlideEditor(app: app, workspace: workspace)
                }
            }
        }
    }

    // MARK: Filmstrip

    private var filmstrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel(workspace.presentations.first { $0.id == workspace.openPresentationID }?.title ?? "Slides")
                    .lineLimit(1)
                Spacer()
                Button { Task { await workspace.addSlide(SlideContent(primary: "")) } } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("Add slide").accessibilityLabel("Add slide")
            }
            .padding(Space.s4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.s3) {
                    ForEach(sectionRuns(workspace)) { run in
                        if let name = run.name {
                            Text(name.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(run.tone.color)
                                .padding(.top, Space.s3).accessibilityAddTraits(.isHeader)
                        }
                        ForEach(run.indices, id: \.self) { i in filmCell(i) }
                    }
                }
                .padding(.horizontal, Space.s4).padding(.bottom, Space.s4)
            }
        }
        .background(Tok.surface)
    }

    private func filmCell(_ i: Int) -> some View {
        let slide = workspace.slides[i]
        let selected = workspace.show.selectedIndex == i
        let live = app.show.liveDeck?.presentationID == workspace.openPresentationID && app.show.liveIndex == i
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(i + 1)").font(.wf(12, .bold).monospacedDigit())
            SlideThumbnail(app: app, slide: slide.content)
                .overlay(alignment: .bottomTrailing) { OwnBackgroundMark(content: slide.content, available: app.media.map { Set($0.allAssets.map(\.id)) }).padding(4) }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(selected ? Tok.blue : .clear, lineWidth: 2))
                .padding(live ? 4 : 0)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).stroke(live ? (app.mode == .live ? Tok.liveFill : Tok.warning) : .clear, lineWidth: 3))
        }
        .contentShape(Rectangle())
        .onTapGesture { workspace.selectSlide(i) }
        .dropDestination(for: String.self) { items, _ in
            guard let text = items.first, let mediaID = SlideBackgroundDrop.mediaID(fromDragText: text) else { return false }
            return app.setSlideBackground(mediaID: mediaID, slideID: slide.id)
        }
        .dropDestination(for: URL.self) { urls, _ in app.setSlideBackground(fileURLs: urls, slideID: slide.id) }
        .contextMenu {
            if SlideBackgroundDrop.hasOwnBackground(slide.content) {
                Button("Use the presentation's background") { app.clearSlideBackground(slideID: slide.id) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(i + 1): \(slide.content.primary)\(SlideBackgroundDrop.hasOwnBackground(slide.content) ? ", has its own background" : "")")
        .accessibilityValue(live ? "live" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Insert toolbar

    /// The design's object row (Text, Shape, Image): the same actions as the Insert menu.
    private var insertBar: some View {
        HStack(spacing: Space.s3) {
            Button { app.insertObject(.textBox) } label: { Label("Text", systemImage: "textformat") }
                .buttonStyle(HeaderButtonStyle()).help("Add a text box to the selected slide")
            Menu {
                Button("Rectangle") { app.insertObject(.rectangle) }
                Button("Ellipse") { app.insertObject(.ellipse) }
                Button("Rounded Rectangle") { app.insertObject(.roundedRectangle) }
            } label: { Label("Shape", systemImage: "square.on.circle") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 10).frame(height: Space.controlHeight)
                .background(Tok.surface2, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
                .help("Add a shape to the selected slide")
            Button { app.insertImage() } label: { Label("Image", systemImage: "photo") }
                .buttonStyle(HeaderButtonStyle()).help("Add an image to the selected slide")
            Spacer()
        }
        .padding(.horizontal, Space.s5).padding(.vertical, Space.s2)
    }

    // MARK: Header: theme, section orders, re-flow

    private var header: some View {
        AdaptiveHeader(labelledWidth: 1060) { compact in
            HStack(spacing: Space.s3) {
                Picker("Theme", selection: Binding(get: { workspace.openThemeID },
                                                   set: { id in if let open = workspace.openPresentationID { app.setPresentationTheme(id, forPresentation: open) } })) {
                    Text("Default").tag(UUID?.none)
                    ForEach(app.themes) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .frame(maxWidth: 220).help("The look of this song on the audience screen")
                HeaderControlButton(control: .themes, symbol: "paintpalette", compact: compact) { app.ui.showThemeEditor = true }
                if let itemID = workspace.selectedPlaylistItemID, let item = workspace.playlistItems.first(where: { $0.id == itemID }), item.kind.hasSlides {
                    Picker("Section order", selection: Binding(get: { item.arrangementID },
                                                               set: { id in Task { await workspace.setArrangement(id, forPlaylistItem: itemID) } })) {
                        Text("Natural order").tag(UUID?.none)
                        ForEach(workspace.arrangements) { Text($0.name).tag(UUID?.some($0.id)) }
                    }.frame(maxWidth: 220)
                }
                HeaderControlButton(control: .sectionOrders, symbol: "list.number", compact: compact) { app.ui.showSectionOrders = true }
                Spacer(minLength: 4)
                HeaderControlButton(control: .addSlide, symbol: "plus", compact: compact) { Task { await workspace.addSlide(SlideContent(primary: "")) } }
                HeaderControlButton(control: .reflow, symbol: "text.alignleft", compact: compact) {
                    if let id = workspace.openPresentationID { app.openImport(existing: id) }
                }
                HeaderControlButton(control: .editLiveSlide, symbol: "pencil.and.outline", compact: compact) { app.requestLiveQuickEdit() }
                    .disabled(workspace.show.liveSlide == nil)
            }
        }
        .padding(.horizontal, Space.s5)
    }

    private var status: some View {
        let editing = workspace.show.selectedIndex + 1
        let liveSame = app.show.liveDeck?.presentationID == workspace.openPresentationID
        return HStack(spacing: 6) {
            Image(systemName: "lock").foregroundStyle(Tok.muted)
            if liveSame, let live = app.show.liveIndex {
                Text("Slide \(live + 1) is live.").font(.wf(12, .semibold))
                Text("You are editing slide \(editing). Nothing on the screens changes until it is triggered again.").foregroundStyle(Tok.muted)
            } else {
                Text("Nothing from this song is live.").font(.wf(12, .semibold))
                Text("Editing changes the preview only.").foregroundStyle(Tok.muted)
            }
            Spacer()
        }
        .font(.wf(12)).lineLimit(1)
        .padding(.horizontal, Space.s5).frame(height: 30)
        .background(Tok.surface2)
    }
}

// MARK: Media

struct MediaModeView: View {
    let app: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if let media = app.media { sidebar(media).frame(width: 220) ; Divider() }
            ScrollView {
                if let media = app.media {
                    MediaBinPanel(app: app, media: media).padding(Space.s5)
                } else {
                    Text("The media bin is not available.").foregroundStyle(Tok.muted).padding(Space.s5)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // MEDIA-010: the player for the item selected in the bin, then the audio list.
                    if let preview = app.binPreview { BinPlayerPanel(app: app, preview: preview) ; Divider() }
                    if let audio = app.audio { AudioPanel(audio: audio).padding(Space.s5) }
                }
            }
            .frame(width: 380)
            .background(Tok.surface)
        }
    }

    /// The design's "Media bin" and "Audio" lists. Each row is the kind filter the bin always had, with its count.
    private func sidebar(_ media: MediaModel) -> some View {
        let entries = MediaBinCategories.entries(kinds: media.assets.map(\.kind))
        return VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("Media bin").padding(.bottom, Space.s2)
            ForEach(entries.filter { !$0.isAudio }, id: \.title) { row($0, media) }
            SectionLabel("Audio").padding(.top, Space.s5).padding(.bottom, Space.s2)
            ForEach(entries.filter(\.isAudio), id: \.title) { row($0, media) }
            folders
            Spacer()
        }
        .padding(Space.s4)
        .background(Tok.surface)
    }

    private func row(_ entry: MediaBinCategories.Entry, _ media: MediaModel) -> some View {
        let selected = media.kindFilter == entry.kind && app.ui.binFolderID == nil
        return Button { media.kindFilter = entry.kind; app.ui.binFolderID = nil } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: Self.symbol(entry.kind)).frame(width: 18).foregroundStyle(Tok.muted)
                Text(entry.title).font(.wf(14))
                Spacer()
                Text("\(entry.count)").font(.wf(12)).foregroundStyle(Tok.muted)
            }
            .padding(.horizontal, Space.s3).frame(height: 30)
            .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(entry.count)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// MEDIA-010: the hot folders the bin follows, each a source of its own.
    @ViewBuilder private var folders: some View {
        HStack {
            SectionLabel("Folders")
            Spacer()
            Button { app.addHotFolder() } label: { Image(systemName: "plus") }.buttonStyle(.plain).foregroundStyle(Tok.muted)
                .help("Point the bin at a folder: its videos, pictures and sound appear here and follow the folder")
                .accessibilityLabel("Add a folder")
        }
        .padding(.top, Space.s5).padding(.bottom, Space.s2)
        if let hot = app.hotFolders, !hot.folders.isEmpty {
            ForEach(hot.folders) { state in
                let selected = app.ui.binFolderID == state.id
                Button { app.ui.binFolderID = state.id } label: {
                    HStack(spacing: Space.s3) {
                        Image(systemName: state.status == .ok ? "folder" : "exclamationmark.triangle")
                            .frame(width: 18).foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                        Text(state.folder.name).font(.wf(14)).lineLimit(1)
                        Spacer()
                        Text(state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering" : "\(state.items.count)")).font(.wf(12))
                            .foregroundStyle(state.status == .ok ? Tok.muted : Tok.warning)
                    }
                    .padding(.horizontal, Space.s3).frame(height: 30)
                    .background(selected ? Tok.surface3 : .clear, in: RoundedRectangle(cornerRadius: Radius.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Folder \(state.folder.name), \(state.status == .missing ? "missing" : (state.status == .unreachable ? "not answering, last list kept" : "\(state.items.count) items"))")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        } else {
            Text("No folders. Add one with +.").font(.wfSmall).foregroundStyle(Tok.muted)
        }
    }

    private static func symbol(_ kind: MediaKind?) -> String {
        switch kind { case nil: "square.grid.2x2"; case .video?: "film"; case .image?: "photo"; case .audio?: "music.note" }
    }
}

// MARK: Stage

struct StageModeView: View {
    let app: AppModel

    var body: some View {
        if let stage = app.stage {
            StageEditorView(app: app, stage: stage)
        } else {
            Text("Stage layouts are not available.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
