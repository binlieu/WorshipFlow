// OUT-004 / LIB-001 / LIB-002: libraries, presentations, search and import.
import Foundation
import Domain
import Persistence

extension WorkspaceModel {
    // MARK: Libraries

    func reloadLibraries() async {
        if let list = await attempt("read the libraries", { try await self.store.libraries() }) { libraries = list }
        await reloadOverview()
    }

    /// UI-001: the sidebar's counts and bilingual markers. A failed read leaves the old values: they are decoration.
    func reloadOverview() async {
        if let counts = try? await store.presentationCounts() {
            libraryCounts = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, counts[$0.id] ?? 0) })
        }
        if let ids = try? await store.bilingualPresentationIDs() { bilingualPresentationIDs = ids }
    }

    func reloadPresentations() async {
        guard let id = selectedLibraryID else { presentations = []; return }
        if let list = await attempt("read the presentations", { try await self.store.presentations(in: id) }) {
            presentations = list
            learnThemes(of: list)
            await reloadOverview()
        }
    }

    public func createLibrary(name: String, kind: LibraryKind = .songs) async {
        guard let library = await attempt("create the library", { try await self.store.createLibrary(name: name, kind: kind) }) else { return }
        await reloadLibraries()
        await selectLibrary(library.id)
    }

    public func selectLibrary(_ id: UUID) async {
        guard libraries.contains(where: { $0.id == id }) else { return }
        selectedLibraryID = id
        await reloadPresentations()
        placeChanged()
    }

    /// UI-005b: changes what a library is for (its icon and place in the sidebar). The presentations stay as they are.
    public func setLibraryKind(id: UUID, to kind: LibraryKind) async {
        guard await attempt("change the library", { try await self.store.setLibraryKind(id: id, to: kind) }) != nil else { return }
        await reloadLibraries()
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
        let doomed = Set((try? await store.presentations(in: id))?.map(\.id) ?? [])
        if let open = openPresentationID { ownedOpen = doomed.contains(open) } else { ownedOpen = false }
        guard await attempt("delete the library", { try await self.store.deleteLibrary(id: id) }) != nil else { return }
        dropDrafts(ofPresentations: doomed)        // their rows are gone; drafts of other libraries' songs stay
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
        dropDrafts(ofPresentations: [id])          // the write was attempted above; the row is gone now
        await reloadPresentations()
        await reloadPlaylistItems()
        if openPresentationID == id { closeOpenPresentation() }
        if searchResults.contains(where: { $0.presentationID == id }) {
            searchResults.removeAll { $0.presentationID == id }
        }
        placeChanged()
    }

    func closeOpenPresentation() {
        openScripture = nil
        openPresentationID = nil
        selectedPlaylistItemID = nil
        openPlaylistItemID = nil
        slides = []
        groups = []
        arrangements = []
        groupSlideCounts = [:]
        apply(.load(ShowDeck(presentationID: UUID(), slides: [])))
    }

    /// Opens a presentation in natural slide order, into preview only.
    public func openPresentation(_ id: UUID) async {
        let token = beginPreviewRequest()
        await flushDrafts()
        guard isCurrentPreviewRequest(token) else { return }
        previewArrangementID = nil             // a song is opened in natural order; the previewed order is chosen after
        guard let loaded = await loadContent(of: id, itemID: nil), isCurrentPreviewRequest(token) else { return }
        selectedPlaylistItemID = nil
        openPlaylistItemID = nil
        install(loaded, presentationID: id)
    }

    struct LoadedContent {
        var slides: [Slide]
        var groups: [SlideGroup]
        var arrangements: [Arrangement]
        var groupSlideCounts: [UUID: Int]

        /// Typed text that is still waiting to be written shows over what the library holds (R3).
        func applyingDrafts(_ drafts: [UUID: Slide]) -> LoadedContent {
            guard !drafts.isEmpty else { return self }
            var copy = self
            for i in copy.slides.indices {
                if let draft = drafts[copy.slides[i].id] {
                    copy.slides[i].content = draft.content
                    copy.slides[i].notes = draft.notes
                }
            }
            return copy
        }
    }

    func loadContent(of presentationID: UUID, itemID: UUID?) async -> LoadedContent? {
        await attempt("open the presentation") {
            let slides: [Slide]
            if let itemID { slides = try await self.store.slides(forPlaylistItem: itemID) } else if let order = self.previewArrangementID {
                slides = try await self.store.resolvedSlides(of: presentationID, arrangementID: order)     // UI-005b: previewed, not stored
            } else {
                slides = try await self.store.slides(of: presentationID)
            }
            let natural = try await self.store.slides(of: presentationID)
            let content = LoadedContent(slides: slides,
                                        groups: try await self.store.groups(of: presentationID),
                                        arrangements: try await self.store.arrangements(of: presentationID),
                                        groupSlideCounts: SectionOrderEditing.slideCounts(of: natural))
            await self.learnTheme(ofPresentation: presentationID)
            return content.applyingDrafts(self.pendingDrafts)
        }
    }

    func install(_ content: LoadedContent, presentationID: UUID) {
        openScripture = nil                    // a song or sermon replaces a passage in preview (LIB-004c)
        if openPresentationID != presentationID || openPlaylistItemID != nil { previewArrangementID = nil }
        openPresentationID = presentationID
        slides = content.slides
        groups = content.groups
        arrangements = content.arrangements
        groupSlideCounts = content.groupSlideCounts
        loadPreview()
        placeChanged()
    }

    /// Re-reads the open presentation (after a structural change), keeping the selection where it makes sense.
    func reloadOpen() async {
        guard let id = openPresentationID else { return }
        guard let loaded = await loadContent(of: id, itemID: openPlaylistItemID) else { return }
        slides = loaded.slides
        groups = loaded.groups
        arrangements = loaded.arrangements
        groupSlideCounts = loaded.groupSlideCounts
        let keep = min(show.selectedIndex, max(slides.count - 1, 0))
        apply(.restore(deck: previewDeck(), selectedIndex: keep))
        placeChanged()
    }

    /// UI-005b: the section order a song opened from the library is previewed in (nil: natural order). Nothing is stored and Live is
    /// not touched; with a playlist item open, the item's own order is used and this does nothing.
    public func setPreviewArrangement(_ id: UUID?) async {
        guard openPresentationID != nil, openPlaylistItemID == nil else { return }
        if let id, !arrangements.contains(where: { $0.id == id }) { return }
        previewArrangementID = id
        await reloadOpen()
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

    /// Replaces the slides of an existing presentation with a new split of the text (section identity is kept by name;
    /// slides whose words are unchanged keep their speaker notes and objects).
    @discardableResult
    public func reflowPresentation(id: UUID, primaryText: String, secondaryText: String?, maxLines: Int) async -> Bool {
        let secondary = secondaryText.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        return await reflowPresentation(id: id, results: Reflow.contents(primary: primaryText, secondary: secondary, maxLines: maxLines))
    }

    /// Speaker notes and objects that re-flowing with `results` would discard (KI-019), for the operator to read before
    /// saving. Slides whose words are unchanged keep theirs. A read that fails says nothing is lost: saving would fail too.
    public func reflowLosses(id: UUID, results: [ReflowResult]) async -> [ReflowLoss] {
        await flushDrafts()        // notes typed a moment ago count
        return (try? await store.reflowLosses(of: id, with: results)) ?? []
    }

    /// CUE-002b (KI-075): the slides whose actions re-flowing with `results` would drop, to be read before saving. Slides whose
    /// words are unchanged keep theirs. A read that fails says nothing is lost: saving would fail too.
    public func reflowSlideActionLosses(id: UUID, results: [ReflowResult]) async -> [SlideActionLoss] {
        (try? await store.slideActionLosses(of: id, with: results)) ?? []
    }

    /// Section orders (and the playlist items that play them) that re-flowing with `results` would shorten or empty (R11),
    /// for the sheet to show before the operator saves. A read that fails says nothing is lost: saving would fail too.
    public func reflowImpact(id: UUID, results: [ReflowResult]) async -> [SectionOrderLoss] {
        (try? await store.reflowImpact(of: id, with: results)) ?? []
    }

    @discardableResult
    public func reflowPresentation(id: UUID, results: [ReflowResult]) async -> Bool {
        guard !results.isEmpty else {
            lastError = "Could not re-flow: there is no lyric text. The song was left as it is."
            return false
        }
        await flushDrafts()
        guard await attempt("re-flow the song", { try await self.store.replaceContent(of: id, with: results) }) != nil else { return false }
        await reloadPlaylistItems()                // an emptied section order shows as an empty item
        if openPresentationID == id { await reloadOpen() }
        onContentReplaced?()                       // CUE-002b: the slides have new ids; their actions were carried over by the store
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
