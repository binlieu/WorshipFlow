// OUT-004 / LIB-001 / LIB-002 / LIB-003: libraries and presentations on top, the playlist below.
import SwiftUI
import AppKit
import Domain
import OperatorCore

private enum NamePrompt: Equatable {
    case newLibrary(LibraryKind), renameLibrary(UUID), newPlaylist, renamePlaylist(UUID), renamePresentation(UUID), newHeader, renameHeader(UUID)

    var title: String {
        switch self {
        case .newLibrary(let kind): kind == .songs ? "New library" : "New \(kind.title.lowercased()) library"
        case .renameLibrary: "Rename library"
        case .newPlaylist: "New playlist"
        case .renamePlaylist: "Rename playlist"
        case .renamePresentation: "Rename presentation"
        case .newHeader: "New section header"
        case .renameHeader: "Rename header"
        }
    }
}

private enum PendingDelete: Equatable {
    case library(UUID, String), playlist(UUID, String), presentation(UUID, String)

    var message: String {
        switch self {
        case .library(_, let n): "Delete the library \"\(n)\" and every presentation in it?"
        case .playlist(_, let n): "Delete the playlist \"\(n)\"? The presentations stay in their library."
        case .presentation(_, let n): "Delete \"\(n)\" and all its slides?"
        }
    }
}

struct LibrarySidebar: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    /// The search text (UI-003): owned by the window, so Command-F and Escape can reach it.
    @Binding var query: String
    var searchFocused: FocusState<Bool>.Binding
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var pendingDelete: PendingDelete?
    @State private var countdownEditing: CountdownEdit?
    @State private var serviceDateEditing: ServiceDateEdit?
    @State private var loopEditing: LoopEdit?

    var body: some View {
        // The design's split: Libraries and the song list over 338 pt, the playlist beneath; a drag strip on the line moves it.
        GeometryReader { geo in
            VStack(spacing: 0) {
                librarySection.frame(height: min(max(app.ui.libraryHeight, 220), max(220, geo.size.height - 160)))
                SplitHandle(height: Binding(get: { app.ui.libraryHeight }, set: { app.ui.libraryHeight = $0 }), range: 220...max(220, geo.size.height - 160))
                playlistSection.frame(maxHeight: .infinity)
            }
        }
        .background(Tok.surface)
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $promptText)
            Button("Cancel", role: .cancel) {}
            Button("OK") { commitPrompt() }
        }
        .sheet(item: $countdownEditing) { edit in
            CountdownSheet(edit: edit) { spec in
                Task {
                    if let id = edit.itemID { await workspace.updatePlaylistItem(id: id, kind: .countdown(spec)) }
                    else { await workspace.addCountdown(spec) }
                }
            }
        }
        .sheet(item: $loopEditing) { _ in
            if let media = app.media { LoopSheet(media: media) { spec in Task { await workspace.addAnnouncementsItem(spec) } } }
        }
        .sheet(item: $serviceDateEditing) { edit in
            ServiceDateSheet(edit: edit) { date in Task { await workspace.setServiceDate(date, forPlaylist: edit.playlistID) } }
        }
        .confirmationDialog(pendingDelete?.message ?? "", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    // MARK: Library

    /// The library, or while a search is typed the presentations whose title or lyrics match, in the order the search gave.
    private var rows: [LibraryListing.Row] {
        LibraryListing.rows(query: query, presentations: workspace.presentations, hits: workspace.searchResults)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Libraries")
                Spacer()
                Menu {
                    Button("New presentation") { app.newPresentation() }
                    Button("Import lyrics…") { app.openImport(existing: nil) }
                    Divider()
                    Menu("New library") {
                        ForEach(LibraryKind.allCases, id: \.self) { kind in Button("\(kind.title)…") { ask(.newLibrary(kind), "") } }
                    }
                    if let library = currentLibrary {
                        Button("Rename library…") { ask(.renameLibrary(library.id), library.name) }
                        Menu("Library kind") {
                            ForEach(LibraryKind.allCases, id: \.self) { kind in
                                Button { Task { await workspace.setLibraryKind(id: library.id, to: kind) } } label: {
                                    if library.kind == kind { Label(kind.title, systemImage: "checkmark") } else { Text(kind.title) }
                                }
                            }
                        }
                        Button("Delete library…", role: .destructive) { pendingDelete = .library(library.id, library.name) }
                            .disabled(workspace.libraries.count < 2)
                    }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("New presentation (Command-N), import lyrics (Command-I), library actions")
                    .accessibilityLabel("Library actions")
            }
            .padding(.bottom, 6)
            searchField.padding(.bottom, 6)
            VStack(spacing: 0) {
                // UI-005b: the design's order: songs, the Bible entry, then sermons and announcements.
                let ordered = LibraryListing.sidebarOrder(workspace.libraries)
                let bibleAt = LibraryListing.scriptureEntryPosition(in: ordered)
                ForEach(Array(ordered.prefix(bibleAt))) { library in libraryRow(library) }
                scriptureRow
                ForEach(Array(ordered.dropFirst(bibleAt))) { library in libraryRow(library) }
            }
            .padding(.bottom, 10)
            Rectangle().fill(Tok.border).frame(height: 1).padding(.horizontal, -12)
            // UI-005a: a plain stack, not a system List, so the design's rounded 26 pt rows are drawn with no system selection block
            // and no extra inset. Up and Down move the selection like the List did; Tab reaches each row as a button.
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in songRow(row) }
                }
                .padding(.top, 10)
            }
            .focusable().focusEffectDisabled()
            .onMoveCommand { direction in
                guard let at = rows.firstIndex(where: { $0.id == workspace.openPresentationID }) else { if let first = rows.first { open(first.id) }; return }
                switch direction {
                case .up where at > 0: open(rows[at - 1].id)
                case .down where at < rows.count - 1: open(rows[at + 1].id)
                default: break
                }
            }
            .overlay {
                if workspace.presentations.isEmpty {
                    Text("No presentations yet.\nImport lyrics with Command-I.")
                        .multilineTextAlignment(.center).font(.wfSmall).foregroundStyle(Tok.muted)
                } else if rows.isEmpty {
                    Text("Nothing found. Searching ignores accents and capital letters.")
                        .multilineTextAlignment(.center).font(.wfSmall).foregroundStyle(Tok.muted)
                }
            }
            .accessibilityLabel("Presentations")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func songRow(_ row: LibraryListing.Row) -> some View {
        let selected = workspace.openPresentationID == row.id
        return Button { open(row.id) } label: {
            HStack(spacing: 8) {
                Image(systemName: currentLibrary?.kind.symbol ?? "music.note").font(.wf(13)).foregroundStyle(Tok.text).frame(width: 16)
                Text(row.title).font(.wf(13)).lineLimit(1)
                Spacer(minLength: 4)
                if let match = row.match {
                    Text(match == .title ? "Title" : "Lyrics").font(.wf(11)).foregroundStyle(Tok.muted)
                } else if workspace.bilingualPresentationIDs.contains(row.id) {
                    Text("EN · VI").font(.wf(11)).foregroundStyle(Tok.muted).accessibilityLabel("Two languages")
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(selected ? Tok.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button("Add to playlist") { Task { await workspace.addToPlaylist(row.id) } }
            if let p = workspace.presentations.first(where: { $0.id == row.id }) {
                Button("Rename…") { ask(.renamePresentation(p.id), p.title) }
                Divider()
                Button("Delete…", role: .destructive) { pendingDelete = .presentation(p.id, p.title) }
            }
        }
    }

    /// Search titles and lyrics (Command-F). It sits at the top of Libraries and filters the list beneath it. Escape clears it
    /// and puts keyboard focus back on the slide grid.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.wf(12)).foregroundStyle(Tok.muted).accessibilityHidden(true)
            TextField("", text: $query, prompt: Text("Search titles and lyrics").foregroundStyle(Tok.muted)).textFieldStyle(.plain)
                .focused(searchFocused)
                .accessibilityLabel("Search titles and lyrics")
            if LibraryListing.hasQuery(query) {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Tok.muted) }
                    .buttonStyle(.plain).help("Clear the search").accessibilityLabel("Clear the search")
            } else {
                KeyHint(key: "⌘F")
            }
        }
        .font(.wf(12))
        .padding(.horizontal, 8).frame(height: Space.controlHeight)
        .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: searchFocused.wrappedValue ? Tok.blue : Tok.borderStrong, fill: Tok.bg)
    }

    /// Opens a row: a search hit through the search (it may be in another library), a plain row directly.
    private func open(_ id: UUID) {
        app.ui.scriptureOpen = false
        if LibraryListing.hasQuery(query), let hit = workspace.searchResults.first(where: { $0.presentationID == id }) {
            query = ""
            Task { await workspace.openSearchResult(hit) }
        } else {
            Task { await workspace.openPresentation(id) }
        }
    }

    /// LIB-004c: the Bible (Command-J). Under the libraries because it is a place to get slides from, like them.
    private var scriptureRow: some View {
        let selected = app.ui.scriptureOpen || workspace.centreShowsScripture
        return Button { app.openScripture() } label: {
            HStack(spacing: 8) {
                Image(systemName: "book.closed").font(.wf(13)).frame(width: 16).foregroundStyle(Tok.text)
                Text("Scripture").font(.wf(13)).lineLimit(1)
                Spacer()
                KeyHint(key: "⌘J")
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(selected ? Tok.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scripture")
        .accessibilityHint("Type a Bible reference and put the verses on the screens. Command-J")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func libraryRow(_ library: Library) -> some View {
        let selected = library.id == workspace.selectedLibraryID && !(app.ui.scriptureOpen || workspace.centreShowsScripture)
        return Button { app.ui.scriptureOpen = false; Task { await workspace.selectLibrary(library.id) } } label: {
            HStack(spacing: 8) {
                Image(systemName: library.kind.symbol).font(.wf(13)).frame(width: 16).foregroundStyle(Tok.text)
                Text(library.name).font(.wf(13)).lineLimit(1)
                Spacer()
                if let count = workspace.libraryCounts[library.id] {
                    Text("\(count)").font(.wf(11)).foregroundStyle(Tok.muted)
                }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(selected ? Tok.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(library.kind.title) library \(library.name), \(workspace.libraryCounts[library.id] ?? 0) presentations")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Playlist

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel("Playlist")
                WFPopup(title: currentPlaylist?.name ?? "No playlist", accessibilityName: "Playlist", height: 22) {
                    ForEach(workspace.playlists) { playlist in
                        Button(playlist.name) { Task { await workspace.selectPlaylist(playlist.id) } }
                    }
                }
                .fixedSize().padding(.leading, 2)
                Spacer()
                Menu {
                    Button("Add header…") { ask(.newHeader, "") }
                    Button("Add announcements loop…") { loopEditing = LoopEdit() }
                    Button("Add countdown…") { countdownEditing = CountdownEdit(itemID: nil, spec: CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300))) }
                    Divider()
                    Button("New playlist…") { ask(.newPlaylist, "") }
                    if let playlist = currentPlaylist {
                        Button("Rename playlist…") { ask(.renamePlaylist(playlist.id), playlist.name) }
                        Button("Set service date and time…") { serviceDateEditing = ServiceDateEdit(playlistID: playlist.id, date: playlist.serviceAt) }
                        Button("Export program…") { app.openExportProgram(playlistID: playlist.id) }
                        Button("Import program…") { app.openImportProgram() }
                        Button("Delete playlist…", role: .destructive) { pendingDelete = .playlist(playlist.id, playlist.name) }
                    }
                } label: { Image(systemName: "ellipsis").foregroundStyle(Tok.muted) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Add a section header or a countdown, and playlist actions").accessibilityLabel("Playlist actions")
            }
            List(selection: Binding(get: { workspace.selectedPlaylistItemID },
                                    set: { id in if let id { selectPlaylistItem(id) } })) {
                ForEach(Array(workspace.playlistItems.enumerated()), id: \.element.id) { index, item in
                    playlistRow(item, number: playableNumber(index))
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let to = destination > from ? destination - 1 : destination
                    guard to != from, workspace.playlistItems.indices.contains(from) else { return }
                    let id = workspace.playlistItems[from].id
                    Task { await workspace.movePlaylistItem(id: id, to: to) }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).contentMargins(.horizontal, 0, for: .scrollContent).tint(.clear)   // UI-005a: no system selection block behind the rounded rows
            .overlay {
                if workspace.playlistItems.isEmpty {
                    Text("Empty playlist.\nRight-click a song, then Add to playlist.")
                        .multilineTextAlignment(.center).font(.wfSmall).foregroundStyle(Tok.muted)
                }
            }
            .accessibilityLabel("Playlist items")
            .background(TableHighlightOff())
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    /// A passage item opens the Scripture view, any other item closes it.
    private func selectPlaylistItem(_ id: UUID) {
        app.ui.scriptureOpen = workspace.playlistItems.first { $0.id == id }?.kind.isScripture == true
        Task { await workspace.openPlaylistItem(id) }
    }

    /// Headers are not numbered; the songs and countdowns are, in order.
    private func playableNumber(_ index: Int) -> Int { workspace.playlistItems.prefix(index + 1).filter { $0.kind.isSelectableLive }.count }

    private func isOnScreen(_ item: PlaylistItem) -> Bool {
        switch item.kind {
        case .presentation: app.show.liveDeck?.presentationID == item.presentationID
        case .countdown: app.show.liveDeck?.presentationID == item.id
        case .scripture: app.show.liveDeck?.presentationID == item.id
        case .sermon: app.show.liveDeck?.presentationID == item.presentationID
        case .media, .announcements: workspace.liveMediaMarkID == item.id         // UI-005b; FIX-H item 11: not once the loop ended by itself
        case .header: false
        }
    }

    @ViewBuilder private func playlistRow(_ item: PlaylistItem, number: Int) -> some View {
        switch item.kind {
        case .header(let label):
            Text(label.uppercased()).font(.wf(11, .semibold)).tracking(0.44).foregroundStyle(Tok.muted).lineLimit(1)
                .padding(.horizontal, 8).frame(height: 22, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: -9, bottom: 0, trailing: -9)).listRowSeparator(.hidden)
                .selectionDisabled()
            .tag(item.id)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Section: \(label)")
            .accessibilityAddTraits(.isHeader)
            .contextMenu {
                Button("Rename header…") { ask(.renameHeader(item.id), label) }
                Divider()
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .countdown(let spec):
            rowChrome(item, icon: "timer") {
                Text(spec.label.isEmpty ? "Countdown" : spec.label).lineLimit(1)
                Spacer()
                Text(Self.summary(spec)).font(.wf(11)).foregroundStyle(Tok.muted)
                liveMarker(item)
            }
            .accessibilityLabel("Countdown \(spec.label), \(Self.summary(spec))")
            .contextMenu {
                Button("Edit countdown…") { countdownEditing = CountdownEdit(itemID: item.id, spec: spec) }
                Divider()
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .scripture(let spec):
            rowChrome(item, icon: "book.closed") {
                Text(item.title).lineLimit(1)
                if let warning = app.scripture?.availability(of: spec) {
                    Text("not installed").font(.wf(10, .bold)).foregroundStyle(Tok.warning)
                        .help(warning)
                        .accessibilityLabel(warning)
                }
                Spacer()
                liveMarker(item)
            }
            .accessibilityLabel("Scripture \(item.title)")
            .contextMenu {
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .media(let spec):
            rowChrome(item, icon: Self.symbol(for: spec.kind)) {
                Text(item.title).lineLimit(1)
                Spacer()
                liveMarker(item)
            }
            .accessibilityLabel("\(spec.kind.rawValue) file \(item.title)")
            .contextMenu {
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .announcements(let spec):
            rowChrome(item, icon: "megaphone") {
                Text(item.title).lineLimit(1)
                Spacer()
                liveMarker(item)
            }
            .accessibilityLabel("Announcements loop \(item.title), \(spec.items.count) \(spec.isVideoLoop ? "video" : "pictures")")
            .contextMenu {
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .sermon:
            rowChrome(item, icon: "textformat") {
                Text("Sermon — \(item.title)").lineLimit(1)
                if workspace.emptyPlaylistItemIDs.contains(item.id) {
                    Text("empty").font(.wf(10, .bold)).foregroundStyle(Tok.warning)
                }
                Spacer()
                liveMarker(item)
            }
            .accessibilityLabel("Sermon \(item.title)")
            .contextMenu {
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .presentation:
            rowChrome(item, icon: "music.note") {
                Text(item.title).lineLimit(1)
                if workspace.emptyPlaylistItemIDs.contains(item.id) {
                    Text("empty").font(.wf(10, .bold)).foregroundStyle(Tok.warning)
                        .help("This item has no slides to show. Its section order may be empty.")
                        .accessibilityLabel("Empty: no slides to show")
                }
                Spacer()
                liveMarker(item)
            }
            .accessibilityLabel("Item \(number): \(item.title)")
            .contextMenu {
                Button("Section order…") {
                    Task {
                        await workspace.openPlaylistItem(item.id)
                        app.ui.showSectionOrders = true
                    }
                }
                Divider()
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        }
    }

    /// One playlist row in the design's form: a leading icon by kind (text colour), 13 pt text, 26 pt tall, `surface-3` when selected.
    private func rowChrome<C: View>(_ item: PlaylistItem, icon: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.wf(13)).foregroundStyle(Tok.text).frame(width: 16)
            content()
        }
        .font(.wf(13))
        .padding(.horizontal, 8).frame(height: 26)
        .tag(item.id)
        .listRowInsets(EdgeInsets(top: 0, leading: -9, bottom: 0, trailing: -9)).listRowSeparator(.hidden)
        .listRowBackground(RoundedRectangle(cornerRadius: Radius.md).fill(workspace.selectedPlaylistItemID == item.id ? Tok.surface3 : .clear))
    }

    @ViewBuilder private func liveMarker(_ item: PlaylistItem) -> some View {
        if isOnScreen(item) {
            HStack(spacing: 4) {
                Circle().fill(Tok.live).frame(width: 8, height: 8)
                Text("LIVE").font(.wf(11)).foregroundStyle(Tok.live)
            }
            .accessibilityLabel("On screen")
        }
    }

    static func symbol(for kind: MediaKind) -> String {
        switch kind { case .video: "film"; case .image: "photo"; case .audio: "waveform" }
    }

    static func summary(_ spec: CountdownSpec) -> String {
        switch spec.mode {
        case .duration(let seconds): CountdownText.format(seconds)
        case .targetTime(let h, let m): String(format: "to %d:%02d", h, m)
        }
    }

    // MARK: Helpers

    private var currentLibrary: Library? { workspace.libraries.first { $0.id == workspace.selectedLibraryID } }
    private var currentPlaylist: Playlist? { workspace.playlists.first { $0.id == workspace.selectedPlaylistID } }

    private func ask(_ p: NamePrompt, _ initial: String) {
        promptText = initial
        prompt = p
    }

    private func commitPrompt() {
        guard let p = prompt else { return }
        let name = promptText
        Task {
            switch p {
            case .newLibrary(let kind): await workspace.createLibrary(name: name, kind: kind)
            case .renameLibrary(let id): await workspace.renameLibrary(id: id, to: name)
            case .newPlaylist: await workspace.createPlaylist(name: name)
            case .renamePlaylist(let id): await workspace.renamePlaylist(id: id, to: name)
            case .renamePresentation(let id): await workspace.renamePresentation(id: id, to: name)
            case .newHeader: await workspace.addHeader(name)
            case .renameHeader(let id): await workspace.updatePlaylistItem(id: id, kind: .header(label: name))
            }
        }
    }

    private func commitDelete() {
        guard let d = pendingDelete else { return }
        Task {
            switch d {
            case .library(let id, _): await workspace.deleteLibrary(id: id)
            case .playlist(let id, _): await workspace.deletePlaylist(id: id)
            case .presentation(let id, _): await workspace.deletePresentation(id: id)
            }
        }
    }
}

/// A 9 pt drag strip on the line between the song list and the playlist (a keyboard or VoiceOver adjustment moves it by 8 pt).
struct SplitHandle: View {
    @Binding var height: Double
    let range: ClosedRange<Double>
    @State private var start: Double?

    var body: some View {
        Rectangle().fill(Tok.border).frame(height: 1)
            .overlay {
                Color.clear.frame(height: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            if start == nil { start = height }
                            height = min(max((start ?? height) + Double(drag.translation.height), range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in start = nil })
                    .accessibilityElement()
                    .accessibilityLabel("Library and playlist split")
                    .accessibilityValue("\(Int(height)) points")
                    .accessibilityAdjustableAction { direction in
                        height = min(max(height + (direction == .increment ? 8 : -8), range.lowerBound), range.upperBound)
                    }
            }
    }
}

struct LoopEdit: Identifiable { let id = UUID() }

/// UI-005b: chooses the pictures (or one video) of an announcements loop from the media bin. Pictures cycle; a video repeats; the
/// loop runs until the operator presses Next.
struct LoopSheet: View {
    @Bindable var media: MediaModel
    let save: (AnnouncementsSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = "Announcements loop"
    @State private var chosen: [UUID] = []
    @State private var seconds = 8

    private var candidates: [MediaAsset] { media.assets.filter { $0.kind != .audio } }
    private var spec: AnnouncementsSpec {
        AnnouncementsSpec(label: label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Announcements loop" : label,
                          items: chosen.compactMap { id in media.asset(id).map { MediaItemSpec(assetID: $0.id, name: $0.name, kind: $0.kind) } },
                          secondsPerPicture: seconds)
    }
    /// One video alone repeats; pictures cycle. A video chosen with other files would not play, so the sheet says so.
    private var problem: String? {
        let items = spec.items
        if items.isEmpty { return "Choose at least one picture, or one video." }
        if items.count > 1, items.contains(where: { $0.kind == .video }) { return "Choose pictures only, or a single video." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Announcements loop").font(.wfHeadline)
            TextField("Name", text: $label).textFieldStyle(.roundedBorder)
            if candidates.isEmpty {
                Text("The media bin has no pictures or videos yet. Add them in the Media tab first.").font(.wfSmall).foregroundStyle(Tok.muted)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(candidates) { asset in
                            Toggle(isOn: Binding(get: { chosen.contains(asset.id) },
                                                 set: { on in if on { chosen.append(asset.id) } else { chosen.removeAll { $0 == asset.id } } })) {
                                Label(asset.name, systemImage: LibrarySidebar.symbol(for: asset.kind))
                            }.toggleStyle(.wfCheckbox)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 160)
                Stepper("Each picture stays \(seconds) s", value: $seconds, in: AnnouncementsSpec.pictureSeconds)
            }
            Text("It runs until you press Next. It never moves the service on by itself.")
                .font(.wfSmall).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if let problem { Text(problem).font(.wfSmall).foregroundStyle(Tok.warning) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { save(spec); dismiss() }.keyboardShortcut(.defaultAction).disabled(problem != nil)
            }
        }
        .padding(Space.s6).frame(width: 420)
    }
}

struct ServiceDateEdit: Identifiable {
    let id = UUID()
    var playlistID: UUID
    var date: Date?
}

/// UI-005b: the service's date and time. The toolbar title reads from it ("Sunday 9:00 — 22 Nov"); without one it shows the playlist's name.
struct ServiceDateSheet: View {
    let edit: ServiceDateEdit
    let save: (Date?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text("Service date and time").font(.wfHeadline)
            DatePicker("Service", selection: $date, displayedComponents: [.date, .hourAndMinute])
            Text("The window title reads from it, in your language. Nothing on the screens changes.")
                .font(.wfSmall).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Remove date") { save(nil); dismiss() }.disabled(edit.date == nil)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(date); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s6).frame(width: 420)
        .onAppear { date = edit.date ?? Date() }
    }
}

struct CountdownEdit: Identifiable {
    let id = UUID()
    var itemID: UUID?
    var spec: CountdownSpec
}

/// Adds or edits a countdown: a length, or a time today. Going live on it shows the time left on the audience and stage screens.
struct CountdownSheet: View {
    let edit: CountdownEdit
    let save: (CountdownSpec) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var useTarget = false
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var target = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            Text(edit.itemID == nil ? "Add countdown" : "Edit countdown").font(.wfHeadline)
            TextField("Label (for example Starting soon)", text: $label).textFieldStyle(.roundedBorder)
            Picker("Counts", selection: $useTarget) {
                Text("A length of time").tag(false)
                Text("To a time today").tag(true)
            }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Counts")
            if useTarget {
                DatePicker("Time", selection: $target, displayedComponents: .hourAndMinute)
            } else {
                HStack {
                    Stepper("\(minutes) min", value: $minutes, in: 0...600)
                    Stepper("\(seconds) s", value: $seconds, in: 0...59)
                }
            }
            Text("It starts when you go live on it, and stays at 0:00 until you move on. It never moves the service on by itself.")
                .font(.wfSmall).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save(spec); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Space.s6).frame(width: 420)
        .onAppear {
            label = edit.spec.label
            switch edit.spec.mode {
            case .duration(let total): minutes = total / 60; seconds = total % 60; useTarget = false
            case .targetTime(let h, let m):
                useTarget = true
                target = Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
            }
        }
    }

    private var spec: CountdownSpec {
        if useTarget {
            let c = Calendar.current.dateComponents([.hour, .minute], from: target)
            return CountdownSpec(label: label, mode: .targetTime(hour: c.hour ?? 0, minute: c.minute ?? 0))
        }
        return CountdownSpec(label: label, mode: .duration(seconds: minutes * 60 + seconds))
    }
}

/// UI-005b: the system List keeps its selection, arrow keys, type-select, drag-reorder and VoiceOver; only the table's own square
/// selection block is turned off, so the rounded row fill is all that shows (the design's selected row).
extension LibraryKind {
    /// The icon the design gives each kind: music, book, text, megaphone.
    var symbol: String {
        switch self {
        case .songs: "music.note"
        case .scripture: "book.closed"
        case .sermons: "textformat"
        case .announcements: "megaphone"
        }
    }
}

private struct TableHighlightOff: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            var node: NSView? = view
            while let current = node {
                if let table = Self.table(in: current) { table.selectionHighlightStyle = .none; return }
                node = current.superview
            }
        }
    }
    private static func table(in view: NSView) -> NSTableView? {
        if let t = view as? NSTableView { return t }
        for sub in view.subviews { if let t = table(in: sub) { return t } }
        return nil
    }
}
