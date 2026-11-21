// OUT-004 / LIB-001 / LIB-002: libraries, presentations, search and import.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    // MARK: Libraries

    func reloadLibraries() async {
        if let list = await attempt("read the libraries", { try await self.store.libraries() }) { libraries = list }
    }

    func reloadPresentations() async {
        guard let id = selectedLibraryID else { presentations = []; return }
        if let list = await attempt("read the presentations", { try await self.store.presentations(in: id) }) {
            presentations = list
        }
    }

    public func createLibrary(name: String) async {
        guard let library = await attempt("create the library", { try await self.store.createLibrary(name: name) }) else { return }
        await reloadLibraries()
        await selectLibrary(library.id)
    }

    public func selectLibrary(_ id: UUID) async {
        guard libraries.contains(where: { $0.id == id }) else { return }
        selectedLibraryID = id
        await reloadPresentations()
        placeChanged()
    }

    public func renameLibrary(id: UUID, to name: String) async {
        guard await attempt("rename the library", { try await self.store.renameLibrary(id: id, to: name) }) != nil else { return }
        await reloadLibraries()
    }

    /// Deletes a library with its presentations. The last library cannot be deleted: there is always somewhere to put a song.
    public func deleteLibrary(id: UUID) async {
        guard libraries.count > 1 else {
            lastError = "Could not delete the library: it is the only one. Create another library first."
            return
        }
        await flushDrafts()
        let ownedOpen: Bool
        if let open = openPresentationID, let list = try? await store.presentations(in: id) {
            ownedOpen = list.contains { $0.id == open }
        } else { ownedOpen = false }
        guard await attempt("delete the library", { try await self.store.deleteLibrary(id: id) }) != nil else { return }
        await reloadLibraries()
        if selectedLibraryID == id || !libraries.contains(where: { $0.id == selectedLibraryID }) {
            selectedLibraryID = libraries.first?.id
        }
        await reloadPresentations()
        await reloadPlaylistItems()
        if ownedOpen { closeOpenPresentation() }
        placeChanged()
    }

    // MARK: Presentations

    /// An empty presentation in the selected library, opened in preview.
    @discardableResult
    public func createPresentation(title: String) async -> Presentation? {
        guard let library = selectedLibraryID else { lastError = "Choose a library first."; return nil }
        guard let p = await attempt("create the presentation", {
            try await self.store.createPresentation(in: library, title: title, kind: .song)
        }) else { return nil }
        await reloadPresentations()
        await openPresentation(p.id)
        return p
    }

    public func renamePresentation(id: UUID, to title: String) async {
        guard await attempt("rename the presentation", { try await self.store.renamePresentation(id: id, to: title) }) != nil else { return }
        await reloadPresentations()
        await reloadPlaylistItems()
    }

    /// Deleting the presentation that is on screen does not blank the screen: live keeps its own copy.
    public func deletePresentation(id: UUID) async {
        await flushDrafts()
        guard await attempt("delete the presentation", { try await self.store.deletePresentation(id: id) }) != nil else { return }
        await reloadPresentations()
        await reloadPlaylistItems()
        if openPresentationID == id { closeOpenPresentation() }
        if searchResults.contains(where: { $0.presentationID == id }) {
            searchResults.removeAll { $0.presentationID == id }
        }
        placeChanged()
    }

    func closeOpenPresentation() {
        openPresentationID = nil
        selectedPlaylistItemID = nil
        slides = []
        groups = []
        arrangements = []
        pendingDrafts = [:]
        apply(.load(ShowDeck(presentationID: UUID(), slides: [])))
    }

    /// Opens a presentation in natural slide order, into preview only.
    public func openPresentation(_ id: UUID) async {
        await flushDrafts()
        guard let loaded = await loadContent(of: id, itemID: nil) else { return }
        selectedPlaylistItemID = nil
        install(loaded, presentationID: id)
    }

    struct LoadedContent {
        var slides: [Slide]
        var groups: [SlideGroup]
        var arrangements: [Arrangement]
    }

    func loadContent(of presentationID: UUID, itemID: UUID?) async -> LoadedContent? {
        await attempt("open the presentation") {
            let slides: [Slide]
            if let itemID { slides = try await self.store.slides(forPlaylistItem: itemID) } else {
                slides = try await self.store.slides(of: presentationID)
            }
            return LoadedContent(slides: slides,
                                 groups: try await self.store.groups(of: presentationID),
                                 arrangements: try await self.store.arrangements(of: presentationID))
        }
    }

    func install(_ content: LoadedContent, presentationID: UUID) {
        openPresentationID = presentationID
        slides = content.slides
        groups = content.groups
        arrangements = content.arrangements
        loadPreview()
        placeChanged()
    }

    /// Re-reads the open presentation (after a structural change), keeping the selection where it makes sense.
    func reloadOpen() async {
        guard let id = openPresentationID else { return }
        guard let loaded = await loadContent(of: id, itemID: selectedPlaylistItemID) else { return }
        slides = loaded.slides
        groups = loaded.groups
        arrangements = loaded.arrangements
        let keep = min(show.selectedIndex, max(slides.count - 1, 0))
        apply(.restore(deck: previewDeck(), selectedIndex: keep))
        placeChanged()
    }

    // MARK: Search (PRES-08)

    public func search(_ query: String) async {
        searchToken += 1
        let token = searchToken
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { searchResults = []; return }
        let hits = await attempt("search") { try await self.store.search(trimmed, limit: 100) }
        guard token == searchToken, let hits else { return }
        searchResults = hits
    }

    /// Loads a search hit into preview, switching to its library if it is in another one.
    public func openSearchResult(_ hit: SearchHit) async {
        if !presentations.contains(where: { $0.id == hit.presentationID }) {
            for library in libraries where library.id != selectedLibraryID {
                if let list = try? await store.presentations(in: library.id), list.contains(where: { $0.id == hit.presentationID }) {
                    await selectLibrary(library.id)
                    break
                }
            }
        }
        await openPresentation(hit.presentationID)
    }

    // MARK: Import and re-flow (PRES-05, PRES-10)

    /// Splits the text into slides (pairing the second language line by line) and saves a new song.
    @discardableResult
    public func importLyrics(title: String, primaryText: String, secondaryText: String?, maxLines: Int) async -> Presentation? {
        let secondary = secondaryText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return await importLyrics(title: title, results: Reflow.contents(primary: primaryText, secondary: secondary, maxLines: maxLines))
    }

    /// Saves an already split song (the import sheet, after the operator moved some breaks).
    @discardableResult
    public func importLyrics(title: String, results: [ReflowResult]) async -> Presentation? {
        guard let library = selectedLibraryID else { lastError = "Choose a library first."; return nil }
        guard !results.isEmpty else {
            lastError = "Could not import: there is no lyric text. Paste the words of the song into the first box."
            return nil
        }
        guard let p = await attempt("import the song", {
            try await self.store.createPresentation(in: library, title: title, kind: .song)
        }) else { return nil }
        do {
            try await store.replaceContent(of: p.id, with: results)
        } catch {
            lastError = Self.message(for: error, doing: "import the song")
            try? await store.deletePresentation(id: p.id)    // no empty song left behind
            await reloadPresentations()
            return nil
        }
        await reloadPresentations()
        return p
    }

    /// Replaces the slides of an existing presentation with a new split of the text (section identity is kept by name).
    @discardableResult
    public func reflowPresentation(id: UUID, primaryText: String, secondaryText: String?, maxLines: Int) async -> Bool {
        let secondary = secondaryText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return await reflowPresentation(id: id, results: Reflow.contents(primary: primaryText, secondary: secondary, maxLines: maxLines))
    }

    @discardableResult
    public func reflowPresentation(id: UUID, results: [ReflowResult]) async -> Bool {
        guard !results.isEmpty else {
            lastError = "Could not re-flow: there is no lyric text. The song was left as it is."
            return false
        }
        await flushDrafts()
        guard await attempt("re-flow the song", { try await self.store.replaceContent(of: id, with: results) }) != nil else { return false }
        if openPresentationID == id { await reloadOpen() }
        return true
    }

    /// The editable text of a presentation (section labels included) for the import sheet.
    public func lyricsText(of id: UUID) async -> (primary: String, secondary: String) {
        guard let slides = try? await store.slides(of: id), let groups = try? await store.groups(of: id) else { return ("", "") }
        let names = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
        let pairs = slides.map { (name: $0.groupID.flatMap { names[$0] }, content: $0.content) }
        return (Reflow.text(from: pairs, language: .primary), Reflow.text(from: pairs, language: .secondary))
    }
}
