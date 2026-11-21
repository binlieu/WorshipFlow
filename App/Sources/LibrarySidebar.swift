// OUT-004 / LIB-001 / LIB-002 / LIB-003: libraries and presentations on top, the playlist below.
import SwiftUI
import Domain
import OperatorCore

private enum NamePrompt: Equatable {
    case newLibrary, renameLibrary(UUID), newPlaylist, renamePlaylist(UUID), renamePresentation(UUID)

    var title: String {
        switch self {
        case .newLibrary: "New library"
        case .renameLibrary: "Rename library"
        case .newPlaylist: "New playlist"
        case .renamePlaylist: "Rename playlist"
        case .renamePresentation: "Rename presentation"
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

    var body: some View {
        VSplitView {
            librarySection.frame(minHeight: 160)
            playlistSection.frame(minHeight: 140)
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $promptText)
            Button("Cancel", role: .cancel) {}
            Button("OK") { commitPrompt() }
        }
        .confirmationDialog(pendingDelete?.message ?? "", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This cannot be undone.") }
    }

    // MARK: Library

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Library", selection: Binding(get: { workspace.selectedLibraryID ?? UUID() },
                                                     set: { id in Task { await workspace.selectLibrary(id) } })) {
                    ForEach(workspace.libraries) { Text($0.name).tag($0.id) }
                }.labelsHidden()
                Menu {
                    Button("New library…") { ask(.newLibrary, "") }
                    if let library = currentLibrary {
                        Button("Rename library…") { ask(.renameLibrary(library.id), library.name) }
                        Button("Delete library…", role: .destructive) { pendingDelete = .library(library.id, library.name) }
                            .disabled(workspace.libraries.count < 2)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Library actions")
            }
            List(selection: Binding(get: { workspace.openPresentationID },
                                    set: { id in if let id { Task { await workspace.openPresentation(id) } } })) {
                ForEach(workspace.presentations) { p in
                    Label(p.title, systemImage: "music.note.list")
                        .tag(p.id)
                        .contextMenu {
                            Button("Add to playlist") { Task { await workspace.addToPlaylist(p.id) } }
                            Button("Rename…") { ask(.renamePresentation(p.id), p.title) }
                            Divider()
                            Button("Delete…", role: .destructive) { pendingDelete = .presentation(p.id, p.title) }
                        }
                }
            }
            .overlay {
                if workspace.presentations.isEmpty {
                    Text("No presentations yet.\nImport lyrics with Command-I.")
                        .multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Presentations")
        }
        .padding(8)
    }

    // MARK: Playlist

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Playlist", selection: Binding(get: { workspace.selectedPlaylistID ?? UUID() },
                                                      set: { id in Task { await workspace.selectPlaylist(id) } })) {
                    ForEach(workspace.playlists) { Text($0.name).tag($0.id) }
                }.labelsHidden()
                Menu {
                    Button("New playlist…") { ask(.newPlaylist, "") }
                    if let playlist = currentPlaylist {
                        Button("Rename playlist…") { ask(.renamePlaylist(playlist.id), playlist.name) }
                        Button("Delete playlist…", role: .destructive) { pendingDelete = .playlist(playlist.id, playlist.name) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Playlist actions")
            }
            List(selection: Binding(get: { workspace.selectedPlaylistItemID },
                                    set: { id in if let id { Task { await workspace.openPlaylistItem(id) } } })) {
                ForEach(Array(workspace.playlistItems.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                        Text(item.title)
                        if workspace.emptyPlaylistItemIDs.contains(item.id) {
                            Text("empty").font(.caption2.bold()).foregroundStyle(.orange)
                                .help("This item has no slides to show. Its section order may be empty.")
                                .accessibilityLabel("Empty: no slides to show")
                        }
                        Spacer()
                        if app.show.liveDeck?.presentationID == item.presentationID {
                            Image(systemName: "circle.fill").font(.caption2).foregroundStyle(.red)
                                .accessibilityLabel("On screen")
                        }
                    }
                    .tag(item.id)
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
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    let to = destination > from ? destination - 1 : destination
                    guard to != from, workspace.playlistItems.indices.contains(from) else { return }
                    let id = workspace.playlistItems[from].id
                    Task { await workspace.movePlaylistItem(id: id, to: to) }
                }
            }
            .overlay {
                if workspace.playlistItems.isEmpty {
                    Text("Empty playlist.\nRight-click a song, then Add to playlist.")
                        .multilineTextAlignment(.center).font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Playlist items")
        }
        .padding(8)
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
