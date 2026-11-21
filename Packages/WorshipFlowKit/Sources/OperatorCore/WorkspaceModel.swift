// OUT-004 / LIB-001..003 / SLIDE-005: the operator workspace. Libraries, playlists, the open presentation and the
// show. It never throws at the interface: a failure sets `lastError` with a message a volunteer can act on.
// Foundation and Observation only; the views live in the app target.
import Foundation
import Observation
import Domain
import Persistence
import CueEngine

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
    /// R11: playlist items that would show no slides (their section order has no sections left, or the song has no
    /// slides). Shown as empty in the playlist; Next and Previous stop on them with a message.
    public internal(set) var emptyPlaylistItemIDs: Set<UUID> = []
    /// The playlist item the operator chose last: a song, or a countdown (whose slides are not on screen). Go Live acts on it.
    public internal(set) var selectedPlaylistItemID: UUID?
    /// FIX-D S2: the playlist item the open presentation was opened from, whatever is selected now. Nil when it was opened from
    /// the library. A slide chosen after a countdown belongs to this item, and Next and Previous step from it.
    @ObservationIgnored public internal(set) var openPlaylistItemID: UUID?
    public internal(set) var openPresentationID: UUID?
    /// LIB-004c: the Bible passage in preview, if one is (it is not a presentation: `openPresentationID` is nil then).
    public internal(set) var openScripture: OpenScripture?
    /// The open presentation's slides in play order (the item's arrangement applied).
    public internal(set) var slides: [Slide] = []
    public internal(set) var groups: [SlideGroup] = []
    public internal(set) var arrangements: [Arrangement] = []
    /// How many slides each section of the open song has, whatever order the open item plays it in.
    public internal(set) var groupSlideCounts: [UUID: Int] = [:]
    public internal(set) var searchResults: [SearchHit] = []
    public internal(set) var show = ShowState()
    public internal(set) var lastError: String?
    /// UI-001: which of the six modes the window shows. Restored on relaunch; changing it never touches the show.
    public internal(set) var mode: WorkspaceMode = .show
    /// UI-001: presentations per library, and the presentations that carry a second language (sidebar rows).
    public internal(set) var libraryCounts: [UUID: Int] = [:]
    public internal(set) var bilingualPresentationIDs: Set<UUID> = []
    /// The theme each known presentation uses (PRES-06); absent means the role default. Filled as presentations load.
    public internal(set) var presentationThemes: [UUID: UUID] = [:]

    /// Called on the main actor after the theme of a presentation changes, so the app can publish scenes again.
    @ObservationIgnored public var onAppearanceChange: (@MainActor () -> Void)?

    /// Called on the main actor after every change to `show`, so the app can publish scenes to the outputs.
    @ObservationIgnored public var onShowChange: (@MainActor (ShowState) -> Void)?

    /// CUE-002b: called on the main actor after a command that took a slide live (a trigger, or a Next or Previous that moved
    /// the live slide). Not for preview, quick edit, clear or stop. The cue wiring hangs slide actions on it.
    @ObservationIgnored public var onSlideWentLive: (@MainActor (SlideLiveEvent) -> Void)?

    /// CUE-002b: called on the main actor after a re-flow replaced a presentation's slides (their ids changed).
    @ObservationIgnored public var onContentReplaced: (@MainActor () -> Void)?

    /// Called on the main actor by `clearAll()`, after the show state changed, so the app can stop the foreground clip.
    @ObservationIgnored public var onClearAll: (@MainActor () -> Void)?

    /// LIB-004c: reads the passages that scripture playlist items keep. Set by `ScriptureModel.connect`.
    @ObservationIgnored public weak var scripture: ScriptureModel?

    // MARK: Internals

    @ObservationIgnored let store: LibraryStore
    /// The playlist item whose presentation is on screen, so Next and Previous can cross item boundaries.
    @ObservationIgnored var liveItemID: UUID?
    /// Ids of the slides in the live deck, in the same order, so a quick edit can be saved.
    @ObservationIgnored var liveSlideIDs: [UUID] = []
    /// Speaker notes of those slides as they were when the deck went live (STAGE-001b); used when another presentation is open.
    @ObservationIgnored var liveSlideNotes: [String] = []
    /// UI-001: the live deck's title and the section name of each live slide, for the transport bar's position line.
    public internal(set) var liveTitle: String?
    public internal(set) var liveSectionNames: [String?] = []
    /// UI-005b: the media-file item or announcements loop that is live, if any. A song taken live, Stop or stepping on ends it.
    public internal(set) var liveMediaItemID: UUID?
    /// UI-005b: told to the app, which plays the files. The model never touches a player: it says what the operator chose.
    @ObservationIgnored public var onMediaItem: (@MainActor (MediaItemCommand) -> Void)?
    /// UI-002: the countdown that is live, if any.
    public internal(set) var liveCountdown: LiveCountdown?
    /// Where the time comes from; tests replace it.
    @ObservationIgnored public var countdownClock: @MainActor () -> Date = { Date() }
    @ObservationIgnored var pendingDrafts: [UUID: Slide] = [:]
    /// R3: set while typed text could not be written, with the reason. Stays until every draft is saved, and is not
    /// cleared by dismissing the error bar, so the operator always knows the typing is not on disk yet.
    public internal(set) var draftSaveProblem: String?
    /// True while typed text is waiting to be written (including text whose earlier write failed).
    public var hasUnsavedDrafts: Bool { !pendingDrafts.isEmpty }
    /// How one typed slide reaches the library. The store's own write; tests replace it with a failing one.
    @ObservationIgnored lazy var draftWriter: @MainActor (Slide) async throws -> Void = { [store] slide in try await store.updateSlide(slide) }
    @ObservationIgnored private var draftRetry: Task<Void, Never>?
    @ObservationIgnored private var draftFailures = 0
    @ObservationIgnored private let clock: any SaveClock
    @ObservationIgnored var searchToken = 0
    @ObservationIgnored var stepping = false
    /// FIX-F item 4: the number of the newest request to put something into preview (a typed passage, a playlist item, a song).
    @ObservationIgnored var previewRequest = 0

    /// FIX-F item 8: the last Next or Previous that stopped at a passage whose translation is missing. A second one for the same item,
    /// from the same live item, in the same stay (no other transport command in between) skips the item.
    struct BlockedStep: Equatable {
        var epoch: Int
        var from: UUID
        var target: UUID
        var direction: Int
    }
    @ObservationIgnored var blockedStep: BlockedStep?
    /// R13: the live presentation's theme as it was when the show was last triggered (see `shownThemeID`).
    @ObservationIgnored var capturedLiveThemeID: UUID?
    /// R1: transport commands (Go Live, Next, Previous) run one at a time, in the order they arrived.
    @ObservationIgnored var transportTail: Task<Void, Never>?
    /// R1: bumped by every immediate command (Clear, Stop, a direct trigger). A queued or running command that began
    /// before the bump is abandoned, so a slow playlist step can never undo what the operator did after it.
    @ObservationIgnored var transportEpoch = 0
    @ObservationIgnored private var editSaver: DebouncedSaver<Int>?
    @ObservationIgnored private var placeSaver: DebouncedSaver<WorkspacePlace>?
    @ObservationIgnored private var modeSaver: DebouncedSaver<WorkspaceMode>?
    @ObservationIgnored private var restoring = false
    /// UI-005b: the saved-note's source: when (on the save clock) typed text was last written, and the section order a song opened from
    /// the library is previewed in.
    public internal(set) var lastDraftSavedAt: TimeInterval?
    public internal(set) var previewArrangementID: UUID?

    static let placeKey = "workspace.place"
    public static let modeKey = "workspace.mode"

    public init(store: LibraryStore, clock: any SaveClock = RealSaveClock()) {
        self.store = store
        self.clock = clock
        editSaver = DebouncedSaver<Int>(delay: 2, maximumDelay: 5, clock: clock) { [weak self] _ in
            await self?.writeDrafts()
        }
        placeSaver = DebouncedSaver<WorkspacePlace>(delay: 0.5, maximumDelay: 2, clock: clock) { [weak self] place in
            await self?.writePlace(place)
        }
        modeSaver = DebouncedSaver<WorkspaceMode>(delay: 0.3, maximumDelay: 1, clock: clock) { [weak self] mode in
            // A convenience like the place: not worth interrupting the operator if it cannot be written.
            try? await self?.store.setState(mode.rawValue, for: Self.modeKey)
        }
    }

    /// UI-001: switches the mode (Command-1 to 6, the switcher) and remembers it for the next launch.
    public func setMode(_ new: WorkspaceMode) {
        guard new != mode else { return }
        mode = new
        modeSaver?.schedule(new)
    }

    // MARK: Quick edit labels (UI-005b)

    /// The note under the Quick edit fields, from the last real write of typed text and the save clock.
    public func quickEditSavedNote() -> String {
        QuickEditLabels.savedNote(secondsAgo: lastDraftSavedAt.map { Int((clock.now - $0).rounded(.down)) })
    }

    /// The two fields' labels: the language of the words in each, or the neutral names when the words do not say.
    public var quickEditLanguageNames: (first: String, second: String) {
        let sample = slides.prefix(12)
        return (LanguageNaming.name(of: sample.map(\.content.primary)) ?? "First language",
                LanguageNaming.name(of: sample.compactMap(\.content.secondary)) ?? "Second language")
    }

    // MARK: Loading

    /// Opens the last place into preview. A first run seeds a "Songs" library and one playlist.
    public func load() async {
        restoring = true
        defer { restoring = false }
        mode = WorkspaceMode.restored(from: try? await store.state(for: Self.modeKey))
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
        if let itemID = place.playlistItemID, let at = playlistItems.firstIndex(where: { $0.id == itemID }) {
            // UI-002: a stored place on a header lands on the nearest playable item; a countdown is selected, not started.
            if let landing = PlaylistStepping.landing(kinds: playlistKinds, at: at) { await openPlaylistItem(playlistItems[landing].id) }
        } else if let presentationID = place.presentationID, await presentationExists(presentationID) {
            await openPresentation(presentationID)
        }
        if openPresentationID != nil || openScripture != nil { selectSlide(place.slideIndex) }
    }

    /// Writes everything that is waiting: typed slide text and the saved place. Call when the app loses focus or quits.
    public func flush() async {
        await flushDrafts()
        await placeSaver?.flush()
        await modeSaver?.flush()
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
        let wasStopped = show.isStopped
        let before = show
        show.apply(command)
        switch command {
        case .select, .load, .restore: break
        default: if show != before { blockedStep = nil }     // a move of the live show ends the "stay" a stopped Next belongs to
        }
        defer {
            if let event = SlideLiveEvent.detect(command: command, before: before, after: show) { onSlideWentLive?(event) }
        }
        switch command {
        case .trigger: captureLiveTheme()
        case .next where wasStopped: captureLiveTheme()        // the first Next of a stopped show triggers the preview deck
        case .stop: capturedLiveThemeID = nil
        default: break
        }
        onShowChange?(show)
    }

    private func captureLiveTheme() {
        capturedLiveThemeID = show.liveDeck.flatMap { presentationThemes[$0.presentationID] }
    }

    func previewDeck() -> ShowDeck {
        if let open = openScripture { return ShowDeck(presentationID: open.deckID, slides: open.contents) }    // LIB-004c
        return ShowDeck(presentationID: openPresentationID ?? UUID(), slides: slides.map(\.content))
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

    /// R3: writes every waiting draft. A draft leaves `pendingDrafts` only when its write succeeded (or its slide no
    /// longer exists), and only if it was not replaced by newer typing meanwhile. A failure keeps it, shows the reason
    /// and schedules another try with back-off (2 s, 4 s, ... at most 30 s).
    private func writeDrafts() async {
        var failure: Error?
        var wrote = false
        for slide in pendingDrafts.values.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            do {
                try await draftWriter(slide)
                wrote = true
                if pendingDrafts[slide.id] == slide { pendingDrafts[slide.id] = nil }
            } catch StoreError.notFound {
                // The row is gone (deleted elsewhere): nothing to save into. Dropped knowingly, and the operator is told.
                if pendingDrafts[slide.id] == slide { pendingDrafts[slide.id] = nil }
                lastError = "Some typing could not be saved: that slide no longer exists. It may have been deleted. The text was discarded."
            } catch {
                failure = error
            }
        }
        if failure == nil, wrote { lastDraftSavedAt = clock.now }
        guard let failure else { draftsSettled(); return }
        let first = draftSaveProblem == nil
        draftSaveProblem = "Your typing is not saved yet: \(Self.reason(for: failure)) It is kept here and WorshipFlow keeps trying."
        if first { lastError = Self.message(for: failure, doing: "save your typing") }
        scheduleDraftRetry()
    }

    private static func reason(for error: Error) -> String {
        let text = (error as? StoreError).map { Self.message(for: $0, doing: "save") } ?? error.localizedDescription
        return text.hasSuffix(".") || text.hasSuffix("!") ? text : text + "."
    }

    /// Called after a write round and after drafts were dropped: with nothing waiting, the warning and the retry end.
    func draftsSettled() {
        guard pendingDrafts.isEmpty else { return }
        draftSaveProblem = nil
        draftFailures = 0
        draftRetry?.cancel()
        draftRetry = nil
    }

    private func scheduleDraftRetry() {
        draftFailures += 1
        let delay = min(30.0, 2.0 * pow(2.0, Double(draftFailures - 1)))
        draftRetry?.cancel()
        draftRetry = Task { @MainActor [weak self, clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            guard let self, !Task.isCancelled else { return }
            self.draftRetry = nil
            await self.flushDrafts()
        }
    }

    /// Forgets the waiting drafts of slides that belong to presentations that were deleted (their rows are gone, so a
    /// write could never succeed). Drafts of every other presentation stay.
    func dropDrafts(ofPresentations ids: Set<UUID>) {
        pendingDrafts = pendingDrafts.filter { !ids.contains($0.value.presentationID) }
        draftsSettled()
    }

    func scheduleDraftSave() { editSaver?.schedule(0) }
    func flushDrafts() async {
        if !pendingDrafts.isEmpty { editSaver?.schedule(0) }    // a draft whose earlier write failed is no longer scheduled
        await editSaver?.flush()
    }
}
