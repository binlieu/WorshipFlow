// OUT-004 / LIB-001 / LIB-002 / LIB-003: libraries and presentations on top, the playlist below.
import SwiftUI
import Domain
import OperatorCore

private enum NamePrompt: Equatable {
    case newLibrary, renameLibrary(UUID), newPlaylist, renamePlaylist(UUID), renamePresentation(UUID), newHeader, renameHeader(UUID)

    var title: String {
        switch self {
        case .newLibrary: "New library"
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
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var pendingDelete: PendingDelete?
    @State private var filter = ""
    @State private var countdownEditing: CountdownEdit?

    var body: some View {
        VSplitView {
            librarySection.frame(minHeight: 220)
            playlistSection.frame(minHeight: 160)
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
        .confirmationDialog(pendingDelete?.message ?? "", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    // MARK: Library

    private var visiblePresentations: [Presentation] { LibraryFilter.apply(filter, to: workspace.presentations, title: \.title) }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Libraries")
                Spacer()
                Menu {
                    Button("New presentation") { app.newPresentation() }
                    Button("Import lyrics…") { app.openImport(existing: nil) }
                    Divider()
                    Button("New library…") { ask(.newLibrary, "") }
                    if let library = currentLibrary {
                        Button("Rename library…") { ask(.renameLibrary(library.id), library.name) }
                        Button("Delete library…", role: .destructive) { pendingDelete = .library(library.id, library.name) }
                            .disabled(workspace.libraries.count < 2)
                    }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("New presentation (Command-N), import lyrics (Command-I), library actions")
                    .accessibilityLabel("Library actions")
            }
            .padding(.horizontal, 8)
            VStack(spacing: 2) {
                ForEach(workspace.libraries) { library in libraryRow(library) }
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(Tok.muted)
                TextField("Filter songs", text: $filter).textFieldStyle(.plain)
                    .accessibilityLabel("Filter the presentations of this library")
            }
            .padding(.horizontal, 8).frame(height: Space.controlHeight)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Tok.borderStrong, lineWidth: 1))
            .padding(.horizontal, 4)
            List(selection: Binding(get: { workspace.openPresentationID },
                                    set: { id in if let id { Task { await workspace.openPresentation(id) } } })) {
                ForEach(visiblePresentations) { p in
                    HStack(spacing: 8) {
                        Image(systemName: "music.note").foregroundStyle(Tok.muted).frame(width: 16)
                        Text(p.title).lineLimit(1)
                        Spacer(minLength: 4)
                        if workspace.bilingualPresentationIDs.contains(p.id) {
                            Text("EN · VI").font(.wfMonoData).foregroundStyle(Tok.muted)
                                .accessibilityLabel("Two languages")
                        }
                    }
                    .tag(p.id)
                    .listRowBackground(RoundedRectangle(cornerRadius: Radius.md).fill(workspace.openPresentationID == p.id ? Tok.surface3 : .clear).padding(.horizontal, 4))
                    .contextMenu {
                        Button("Add to playlist") { Task { await workspace.addToPlaylist(p.id) } }
                        Button("Rename…") { ask(.renamePresentation(p.id), p.title) }
                        Divider()
                        Button("Delete…", role: .destructive) { pendingDelete = .presentation(p.id, p.title) }
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .overlay {
                if workspace.presentations.isEmpty {
                    Text("No presentations yet.\nImport lyrics with Command-I.")
                        .multilineTextAlignment(.center).font(.caption).foregroundStyle(Tok.muted)
                } else if visiblePresentations.isEmpty {
                    Text("No title matches.").font(.caption).foregroundStyle(Tok.muted)
                }
            }
            .accessibilityLabel("Presentations")
        }
        .padding(8)
    }

    private func libraryRow(_ library: Library) -> some View {
        let selected = library.id == workspace.selectedLibraryID
        return Button { Task { await workspace.selectLibrary(library.id) } } label: {
            HStack(spacing: 8) {
                Image(systemName: "music.note.list").frame(width: 16).foregroundStyle(selected ? Tok.text : Tok.muted)
                Text(library.name).lineLimit(1)
                Spacer()
                if let count = workspace.libraryCounts[library.id] {
                    Text("\(count)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Tok.muted)
                }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(selected ? Tok.surface3 : Color.clear, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Library \(library.name), \(workspace.libraryCounts[library.id] ?? 0) presentations")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Playlist

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Playlist")
                Picker("Playlist", selection: Binding(get: { workspace.selectedPlaylistID ?? UUID() },
                                                      set: { id in Task { await workspace.selectPlaylist(id) } })) {
                    ForEach(workspace.playlists) { Text($0.name).tag($0.id) }
                }.labelsHidden().fixedSize()
                Spacer()
                Menu {
                    Button("Add header…") { ask(.newHeader, "") }
                    Button("Add countdown…") { countdownEditing = CountdownEdit(itemID: nil, spec: CountdownSpec(label: "Starting soon", mode: .duration(seconds: 300))) }
                } label: { Image(systemName: "plus") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Add a section header or a countdown to the playlist").accessibilityLabel("Add to playlist")
                Menu {
                    Button("New playlist…") { ask(.newPlaylist, "") }
                    if let playlist = currentPlaylist {
                        Button("Rename playlist…") { ask(.renamePlaylist(playlist.id), playlist.name) }
                        Button("Delete playlist…", role: .destructive) { pendingDelete = .playlist(playlist.id, playlist.name) }
                    }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Playlist actions")
            }
            List(selection: Binding(get: { workspace.selectedPlaylistItemID },
                                    set: { id in if let id { Task { await workspace.openPlaylistItem(id) } } })) {
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
            .listStyle(.plain).scrollContentBackground(.hidden)
            .overlay {
                if workspace.playlistItems.isEmpty {
                    Text("Empty playlist.\nRight-click a song, then Add to playlist.")
                        .multilineTextAlignment(.center).font(.caption).foregroundStyle(Tok.muted)
                }
            }
            .accessibilityLabel("Playlist items")
        }
        .padding(8)
    }

    /// Headers are not numbered; the songs and countdowns are, in order.
    private func playableNumber(_ index: Int) -> Int { workspace.playlistItems.prefix(index + 1).filter { $0.kind.isSelectableLive }.count }

    private func isOnScreen(_ item: PlaylistItem) -> Bool {
        switch item.kind {
        case .presentation: app.show.liveDeck?.presentationID == item.presentationID
        case .countdown: app.show.liveDeck?.presentationID == item.id
        case .header: false
        }
    }

    @ViewBuilder private func playlistRow(_ item: PlaylistItem, number: Int) -> some View {
        switch item.kind {
        case .header(let label):
            HStack(spacing: 6) {
                Text(label.uppercased()).font(.wfSectionLabel).tracking(0.66).foregroundStyle(Tok.muted).lineLimit(1)
                Rectangle().fill(Tok.border).frame(height: 1)
            }
            .padding(.top, 6)
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
            HStack(spacing: 8) {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(Tok.muted).frame(width: 18)
                Image(systemName: "timer").foregroundStyle(Tok.muted)
                Text(spec.label.isEmpty ? "Countdown" : spec.label).lineLimit(1)
                Spacer()
                Text(Self.summary(spec)).font(.wfMonoData).foregroundStyle(Tok.muted)
                liveMarker(item)
            }
            .tag(item.id)
            .listRowBackground(RoundedRectangle(cornerRadius: Radius.md).fill(workspace.selectedPlaylistItemID == item.id ? Tok.surface3 : .clear).padding(.horizontal, 4))
            .accessibilityLabel("Countdown \(spec.label), \(Self.summary(spec))")
            .contextMenu {
                Button("Edit countdown…") { countdownEditing = CountdownEdit(itemID: item.id, spec: spec) }
                Divider()
                Button("Remove from playlist", role: .destructive) { Task { await workspace.removePlaylistItem(id: item.id) } }
            }
        case .presentation:
            HStack(spacing: 8) {
                Text("\(number)").font(.caption.monospacedDigit()).foregroundStyle(Tok.muted).frame(width: 18)
                Text(item.title).lineLimit(1)
                if workspace.emptyPlaylistItemIDs.contains(item.id) {
                    Text("empty").font(.caption2.bold()).foregroundStyle(Tok.warning)
                        .help("This item has no slides to show. Its section order may be empty.")
                        .accessibilityLabel("Empty: no slides to show")
                }
                Spacer()
                liveMarker(item)
            }
            .tag(item.id)
            .listRowBackground(RoundedRectangle(cornerRadius: Radius.md).fill(workspace.selectedPlaylistItemID == item.id ? Tok.surface3 : .clear).padding(.horizontal, 4))
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

    @ViewBuilder private func liveMarker(_ item: PlaylistItem) -> some View {
        if isOnScreen(item) {
            HStack(spacing: 4) {
                Circle().fill(Tok.live).frame(width: 6, height: 6)
                Text("LIVE").font(.wfMonoData).foregroundStyle(Tok.live)
            }
            .accessibilityLabel("On screen")
        }
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
            case .newLibrary: await workspace.createLibrary(name: name)
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
            Text(edit.itemID == nil ? "Add countdown" : "Edit countdown").font(.headline)
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
                .font(.caption).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
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
