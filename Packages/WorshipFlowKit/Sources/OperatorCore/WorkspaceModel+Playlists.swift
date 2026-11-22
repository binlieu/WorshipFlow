// OUT-004 / LIB-003 / PRES-03: playlists and their items.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    func reloadPlaylists() async {
        if let list = await attempt("read the playlists", { try await self.store.playlists() }) { playlists = list }
    }

    func reloadPlaylistItems() async {
        guard let id = selectedPlaylistID else { playlistItems = []; emptyPlaylistItemIDs = []; return }
        if let list = await attempt("read the playlist", { try await self.store.playlistItems(of: id) }) {
            playlistItems = list
            var empty: Set<UUID> = []
            for item in list where ((try? await store.slides(forPlaylistItem: item.id))?.count ?? 1) == 0 {
                if item.kind.hasSlides { empty.insert(item.id) }      // a passage, a file or a loop has no stored slides, and is not "empty"
            }
            emptyPlaylistItemIDs = empty
        }
        if let open = selectedPlaylistItemID, !playlistItems.contains(where: { $0.id == open }) {
            selectedPlaylistItemID = nil      // the item went away; the presentation stays open
        }
        if let open = openPlaylistItemID, !playlistItems.contains(where: { $0.id == open }) { openPlaylistItemID = nil }
    }

    public func createPlaylist(name: String) async {
        guard let p = await attempt("create the playlist", { try await self.store.createPlaylist(name: name) }) else { return }
        await reloadPlaylists()
        await selectPlaylist(p.id)
    }

    public func selectPlaylist(_ id: UUID) async {
        guard playlists.contains(where: { $0.id == id }) else { return }
        if id != selectedPlaylistID { endLiveMediaItem() }       // FIX-H item 3: the file or loop belongs to the playlist being left
        selectedPlaylistID = id
        await reloadPlaylistItems()
        placeChanged()
    }

    public func renamePlaylist(id: UUID, to name: String) async {
        guard await attempt("rename the playlist", { try await self.store.renamePlaylist(id: id, to: name) }) != nil else { return }
        await reloadPlaylists()
    }

    public func deletePlaylist(id: UUID) async {
        guard await attempt("delete the playlist", { try await self.store.deletePlaylist(id: id) }) != nil else { return }
        if selectedPlaylistID == id { endLiveMediaItem() }       // FIX-H item 3: its file or loop cannot go on being "live"
        await reloadPlaylists()
        if selectedPlaylistID == id {
            selectedPlaylistID = playlists.first?.id
            selectedPlaylistItemID = nil
            openPlaylistItemID = nil
        }
        await reloadPlaylistItems()
        placeChanged()
    }

    /// Appends a presentation to the selected playlist, creating a "Service" playlist if there is none.
    public func addToPlaylist(_ presentationID: UUID) async {
        if selectedPlaylistID == nil {
            guard let p = await attempt("create the playlist", { try await self.store.createPlaylist(name: "Service") }) else { return }
            await reloadPlaylists()
            selectedPlaylistID = p.id
        }
        guard let playlist = selectedPlaylistID else { return }
        // UI-005b: a presentation from a sermons library is listed as a sermon.
        let isSermon = await libraryKind(ofPresentation: presentationID) == .sermons
        guard await attempt("add to the playlist", {
            if isSermon { _ = try await self.store.addPlaylistSermon(presentationID, to: playlist) }
            else { _ = try await self.store.addPresentation(presentationID, to: playlist) }
        }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    private func libraryKind(ofPresentation id: UUID) async -> LibraryKind? {
        for library in libraries {
            if let list = try? await store.presentations(in: library.id), list.contains(where: { $0.id == id }) { return library.kind }
        }
        return nil
    }

    /// UI-005b: appends a file from the media bin to the playlist.
    public func addMediaItem(_ spec: MediaItemSpec) async {
        guard let playlist = await ensurePlaylist() else { return }
        guard await attempt("add the file", { try await self.store.addPlaylistMedia(spec, to: playlist) }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    /// UI-005b: appends an announcements loop (pictures that cycle, or a video that repeats) to the playlist.
    public func addAnnouncementsItem(_ spec: AnnouncementsSpec) async {
        guard !spec.items.isEmpty else { lastError = "Could not add the loop: choose at least one picture or a video."; return }
        guard let playlist = await ensurePlaylist() else { return }
        guard await attempt("add the loop", { try await self.store.addPlaylistAnnouncements(spec, to: playlist) }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    public func movePlaylistItem(id: UUID, to index: Int) async {
        guard await attempt("move the item", { try await self.store.movePlaylistItem(id: id, to: index) }) != nil else { return }
        await reloadPlaylistItems()
    }

    public func removePlaylistItem(id: UUID) async {
        if liveMediaItemID == id { endLiveMediaItem() }           // UI-005b: removing the file that is playing stops it
        guard await attempt("remove the item", { try await self.store.removePlaylistItem(id: id) }) != nil else { return }
        if liveItemID == id { liveItemID = nil }
        countdownItemRemoved(id)
        await reloadPlaylistItems()
        placeChanged()
    }

    /// Opens a playlist item in preview, with its arrangement applied.
    public func openPlaylistItem(_ id: UUID) async {
        guard let item = playlistItems.first(where: { $0.id == id }) else { return }
        switch item.kind {
        case .header: return                                  // a header is a label: it cannot be selected
        case .countdown: _ = beginPreviewRequest(); selectedPlaylistItemID = id; placeChanged(); return    // selected for Go Live, not started
        case .scripture(let spec): await openScriptureItem(item, spec: spec); return        // LIB-004c
        case .media(let spec):                                // UI-005b: selected for Go Live, previewed in the bin player, never played
            _ = beginPreviewRequest(); selectedPlaylistItemID = id; placeChanged()
            if case .failed(let text) = perform(.preview(spec)) { lastError = text }
            return
        case .announcements:
            _ = beginPreviewRequest(); selectedPlaylistItemID = id; placeChanged(); return
        case .presentation, .sermon: break
        }
        let token = beginPreviewRequest()
        await flushDrafts()
        guard isCurrentPreviewRequest(token) else { return }
        guard let loaded = await loadContent(of: item.presentationID, itemID: id), isCurrentPreviewRequest(token) else { return }
        selectedPlaylistItemID = id
        openPlaylistItemID = id
        install(loaded, presentationID: item.presentationID)
    }

    /// Chooses the section order an item plays with (nil: natural order). Reloads the item if it is open.
    public func setArrangement(_ arrangementID: UUID?, forPlaylistItem itemID: UUID) async {
        guard await attempt("change the section order", {
            try await self.store.setArrangement(arrangementID, forPlaylistItem: itemID)
        }) != nil else { return }
        await reloadPlaylistItems()
        if openPlaylistItemID == itemID { await reloadOpen() }
    }

    /// A new section order for the open presentation, from group ids (a group may repeat).
    @discardableResult
    public func createArrangement(name: String, groupIDs: [UUID]) async -> Arrangement? {
        guard let id = openPresentationID else { return nil }
        let made = await attempt("create the section order", { try await self.store.createArrangement(for: id, name: name, groupIDs: groupIDs) })
        if made != nil { await reloadOpen() }
        return made
    }
}
