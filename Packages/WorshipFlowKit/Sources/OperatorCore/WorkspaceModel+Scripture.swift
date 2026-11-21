// LIB-004c: a Bible passage in the workspace. A passage is not a stored presentation: it is a preview deck made from the library's
// verses, so choosing a slide changes preview only and Go Live, Next and Previous are the ones every song uses. A scripture
// playlist item (reference and translation codes) opens the same way; a passage that is kept as a presentation becomes an ordinary
// one that can be edited.
import Foundation
import Domain
import Persistence

/// The passage in preview.
public struct OpenScripture: Equatable, Sendable {
    /// The deck id the show uses: the playlist item's id when the passage came from one (so the item can be marked live), else new.
    public var deckID: UUID
    public var title: String
    public var itemID: UUID?
    /// The slides as the screens get them. Empty while `problem` is set.
    public var contents: [SlideContent]
    /// Set when the passage cannot be shown (a translation is not installed), in plain words.
    public var problem: String?
}

extension WorkspaceModel {
    /// Puts a passage into preview. It never touches what is live. Nothing is written to the library.
    public func openScripturePassage(_ passage: ScripturePassage, itemID: UUID? = nil) {
        installScripture(OpenScripture(deckID: itemID ?? passage.id, title: passage.title, itemID: itemID, contents: passage.contents, problem: nil))
        if itemID != nil { scripture?.adopt(passage) }       // a typed passage is already the model's own
    }

    /// A playlist item whose passage cannot be shown: selected, with the reason in the centre pane and an empty preview.
    func openScriptureProblem(_ text: String, item: PlaylistItem, title: String) {
        installScripture(OpenScripture(deckID: item.id, title: title, itemID: item.id, contents: [], problem: text))
        scripture?.clearPassage()
    }

    private func installScripture(_ open: OpenScripture) {
        openPresentationID = nil
        slides = []
        groups = []
        arrangements = []
        groupSlideCounts = [:]
        openPlaylistItemID = open.itemID
        selectedPlaylistItemID = open.itemID
        openScripture = open
        apply(.load(ShowDeck(presentationID: open.deckID, slides: open.contents)))
        placeChanged()
    }

    /// The reference field went empty or could not be read: the passage leaves preview (live is not touched).
    public func closeScripture() {
        guard openScripture != nil else { return }
        openScripture = nil
        openPlaylistItemID = nil
        selectedPlaylistItemID = nil
        apply(.load(ShowDeck(presentationID: UUID(), slides: [])))
        placeChanged()
    }

    func openScriptureItem(_ item: PlaylistItem, spec: ScriptureItemSpec) async {
        selectedPlaylistItemID = item.id
        guard let scripture else {
            lastError = "Could not open the passage: Scripture is not available in this session."
            return
        }
        await flushDrafts()
        switch await scripture.resolve(spec) {
        case .ready(let passage): openScripturePassage(passage, itemID: item.id)
        case .notInstalled(let text): openScriptureProblem(text, item: item, title: spec.label)
        case .failed(let text):
            openScriptureProblem(text, item: item, title: spec.label)
            lastError = "Could not open “\(spec.label)”: \(text)"
        }
    }

    // MARK: Keeping a passage

    /// Appends a passage to the selected playlist (a "Service" playlist is made when there is none). Only the reference and the
    /// translation codes are stored.
    public func addScriptureToPlaylist(_ spec: ScriptureItemSpec) async {
        if selectedPlaylistID == nil {
            guard let p = await attempt("create the playlist", { try await self.store.createPlaylist(name: "Service") }) else { return }
            await reloadPlaylists()
            selectedPlaylistID = p.id
        }
        guard let playlist = selectedPlaylistID else { return }
        guard await attempt("add the passage to the playlist", { try await self.store.addPlaylistScripture(spec, to: playlist) }) != nil else { return }
        await reloadPlaylistItems()
        placeChanged()
    }

    /// An ordinary presentation of the passage's slides, in the selected library, opened for editing. Nil (with a message) on failure;
    /// a half-made presentation is deleted.
    public func saveScriptureAsPresentation(title: String, contents: [SlideContent]) async -> Presentation? {
        guard let library = selectedLibraryID else { lastError = "Choose a library first."; return nil }
        guard !contents.isEmpty else { lastError = "Could not save the passage: it has no slides."; return nil }
        guard let made = await attempt("save the passage", {
            try await self.store.createPresentation(in: library, title: title, kind: .scripture)
        }) else { return nil }
        do {
            for content in contents { _ = try await store.appendSlide(to: made.id, content: content) }
        } catch {
            lastError = Self.message(for: error, doing: "save the passage")
            try? await store.deletePresentation(id: made.id)         // no half-made presentation left behind
            await reloadPresentations()
            return nil
        }
        await reloadPresentations()
        await openPresentation(made.id)
        return made
    }
}
