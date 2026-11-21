// OUT-004 / LIB-001..003 / SLIDE-005: the operator workspace. Libraries, playlists, the open presentation and the
// show. It never throws at the interface: a failure sets `lastError` with a message a volunteer can act on.
// Foundation and Observation only; the views live in the app target.
import Foundation
import Observation
import Domain
import Persistence

/// Where the operator was, saved so a relaunch can bring it back to preview (NFR-06).
struct WorkspacePlace: Codable, Equatable, Sendable {
    var libraryID: UUID?
    var playlistID: UUID?
    var playlistItemID: UUID?
    var presentationID: UUID?
    var slideIndex: Int
}

/// Unsaved text typed into a slide.
struct SlideDraft: Equatable {
    var slide: Slide
}

@MainActor
@Observable
public final class WorkspaceModel {
    // MARK: State the interface reads

    public internal(set) var libraries: [Library] = []
    public internal(set) var selectedLibraryID: UUID?
    public internal(set) var presentations: [Presentation] = []
    public internal(set) var playlists: [Playlist] = []
    public internal(set) var selectedPlaylistID: UUID?
    public internal(set) var playlistItems: [PlaylistItem] = []
    /// Set only while the open presentation was opened from a playlist item.
    public internal(set) var selectedPlaylistItemID: UUID?
    public internal(set) var openPresentationID: UUID?
    /// The open presentation's slides in play order (the item's arrangement applied).
    public internal(set) var slides: [Slide] = []
    public internal(set) var groups: [SlideGroup] = []
    public internal(set) var arrangements: [Arrangement] = []
    public internal(set) var searchResults: [SearchHit] = []
    public internal(set) var show = ShowState()
    public internal(set) var lastError: String?

    /// Called on the main actor after every change to `show`, so the app can publish scenes to the outputs.
    @ObservationIgnored public var onShowChange: (@MainActor (ShowState) -> Void)?

    // MARK: Internals

    @ObservationIgnored let store: LibraryStore
    /// The playlist item whose presentation is on screen, so Next and Previous can cross item boundaries.
    @ObservationIgnored var liveItemID: UUID?
    /// Ids of the slides in the live deck, in the same order, so a quick edit can be saved.
    @ObservationIgnored var liveSlideIDs: [UUID] = []
    @ObservationIgnored var pendingDrafts: [UUID: Slide] = [:]
    @ObservationIgnored var searchToken = 0
    @ObservationIgnored var stepping = false
    @ObservationIgnored private var editSaver: DebouncedSaver<Int>?
    @ObservationIgnored private var placeSaver: DebouncedSaver<WorkspacePlace>?
    @ObservationIgnored private var restoring = false

    static let placeKey = "workspace.place"

    public init(store: LibraryStore, clock: any SaveClock = RealSaveClock()) {
        self.store = store
        editSaver = DebouncedSaver<Int>(delay: 2, maximumDelay: 5, clock: clock) { [weak self] _ in
            await self?.writeDrafts()
        }
        placeSaver = DebouncedSaver<WorkspacePlace>(delay: 0.5, maximumDelay: 2, clock: clock) { [weak self] place in
            await self?.writePlace(place)
        }
    }

    // MARK: Loading

    /// Opens the last place into preview. A first run seeds a "Songs" library and one playlist.
    public func load() async {
        restoring = true
        defer { restoring = false }
        guard let libs = await attempt("read the libraries", { try await self.store.libraries() }) else { return }
        var firstRun = false
        var all = libs
        if all.isEmpty {
            firstRun = true
            guard let created = await attempt("create the first library", { try await self.store.createLibrary(name: "Songs") }) else { return }
            all = [created]
        }
        libraries = all
        if firstRun {
            _ = await attempt("create the first playlist", { try await self.store.createPlaylist(name: "Service") })
        }
        playlists = await attempt("read the playlists", { try await self.store.playlists() }) ?? []

        let place = await storedPlace()
        selectedLibraryID = place?.libraryID.flatMap { id in all.contains { $0.id == id } ? id : nil } ?? all.first?.id
        await reloadPresentations()
        selectedPlaylistID = place?.playlistID.flatMap { id in playlists.contains { $0.id == id } ? id : nil } ?? playlists.first?.id
        await reloadPlaylistItems()

        guard let place else { return }
        if let itemID = place.playlistItemID, playlistItems.contains(where: { $0.id == itemID }) {
            await openPlaylistItem(itemID)
        } else if let presentationID = place.presentationID, await presentationExists(presentationID) {
            await openPresentation(presentationID)
        }
        if openPresentationID != nil { selectSlide(place.slideIndex) }
    }

    /// Writes everything that is waiting: typed slide text and the saved place. Call when the app loses focus or quits.
    public func flush() async {
        await editSaver?.flush()
        await placeSaver?.flush()
    }

    public func dismissError() { lastError = nil }

    // MARK: Place

    func placeChanged() {
        guard !restoring else { return }
        placeSaver?.schedule(WorkspacePlace(libraryID: selectedLibraryID, playlistID: selectedPlaylistID,
                                            playlistItemID: selectedPlaylistItemID, presentationID: openPresentationID,
                                            slideIndex: show.selectedIndex))
    }

    private func storedPlace() async -> WorkspacePlace? {
        // A damaged value is ignored: starting at the top is always safe.
        guard let text = try? await store.state(for: Self.placeKey), let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkspacePlace.self, from: data)
    }

    private func writePlace(_ place: WorkspacePlace) async {
        guard let data = try? JSONEncoder().encode(place), let text = String(data: data, encoding: .utf8) else { return }
        // The place is a convenience: failing to save it is not worth interrupting the operator.
        try? await store.setState(text, for: Self.placeKey)
    }

    private func presentationExists(_ id: UUID) async -> Bool {
        for library in libraries {
            if let list = try? await store.presentations(in: library.id), list.contains(where: { $0.id == id }) { return true }
        }
        return false
    }

    // MARK: Show

    /// The one place `show` changes, so the app is always told.
    func apply(_ command: ShowCommand) {
        show.apply(command)
        onShowChange?(show)
    }

    func previewDeck() -> ShowDeck {
        ShowDeck(presentationID: openPresentationID ?? UUID(), slides: slides.map(\.content))
    }

    func loadPreview() { apply(.load(previewDeck())) }

    /// Replaces the preview deck, keeping the selected slide where it is. Never touches live.
    func refreshPreview() { apply(.restore(deck: previewDeck(), selectedIndex: show.selectedIndex)) }

    // MARK: Errors and small helpers

    /// Runs `body`; on failure records a message and returns nil.
    func attempt<T>(_ what: String, _ body: () async throws -> T) async -> T? {
        do { return try await body() } catch {
            lastError = Self.message(for: error, doing: what)
            return nil
        }
    }

    static func message(for error: Error, doing what: String) -> String {
        if let store = error as? StoreError {
            switch store {
            case .invalidName: return "Could not \(what): a name is needed. Type at least one letter and try again."
            case .notFound: return "Could not \(what): that item no longer exists. It may have been deleted. Choose it again from the list."
            case .invalidReference: return "Could not \(what): that section order belongs to a different song."
            case .unknownMigration: return "Could not \(what): the library file is from a different version of the app."
            }
        }
        return "Could not \(what): \(error.localizedDescription) Nothing on the screens was changed. Try again; if it keeps failing, restart the app."
    }

    private func writeDrafts() async {
        let drafts = pendingDrafts
        pendingDrafts = [:]
        for slide in drafts.values {
            do { try await store.updateSlide(slide) } catch {
                // Put it back so the next flush retries and the typed text is not lost, unless the slide is gone.
                if (error as? StoreError) != .notFound, pendingDrafts[slide.id] == nil { pendingDrafts[slide.id] = slide }
                lastError = Self.message(for: error, doing: "save your typing")
            }
        }
    }

    func scheduleDraftSave() { editSaver?.schedule(0) }
    func flushDrafts() async { await editSaver?.flush() }
}
