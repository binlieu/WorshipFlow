// OUT-002: operator state. The show lives in `ShowState`, scenes come from `SceneComposer`, and outputs are run
// by `OutputCoordinator`. This model sends commands and reads status; it never renders. Render threads read an
// immutable `PublishedScenes` snapshot, never this object.
import AppKit
import Observation
import Domain
import MediaEngine
import OutputEngine
import RenderEngine
import SDIEngine
import DeckLinkSDI
import Persistence
import OperatorCore

enum LiveMode: Equatable { case stopped, live, cleared, blackout }

struct LibraryProblem: Equatable {
    var path: String
    var message: String
}

struct DisplayChoice: Identifiable, Equatable {
    var id: UInt32
    var name: String
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let operatorWindowTitle = "WORSHIPFLOW"
    /// The operator window is found by this identifier (set when its view reaches the window), because its title is the service name.
    static let operatorWindowIdentifier = NSUserInterfaceItemIdentifier("wf-operator-window")
    static var operatorWindow: NSWindow? {
        NSApplication.shared.windows.first { $0.identifier == operatorWindowIdentifier } ?? NSApplication.shared.windows.first { $0.title == operatorWindowTitle }
    }

    private(set) var show = ShowState()
    private(set) var readouts: [ScreenReadout] = []
    private(set) var displayChoices: [DisplayChoice] = []
    private(set) var screensOn = false
    /// SDI cards the coordinator can see now (HW-002), and what each connector of each carries.
    private(set) var sdiDevices: [SDIDeviceSummary] = []
    /// The state of the SDI driver and cards (HW-004): shown as one calm line in the Screens panel when there is no driver or no card.
    private(set) var sdiEnvironment: SDIEnvironmentStatus?
    /// What happened the last time the app was asked to change a card's profile for fill and key (KI-054).
    private(set) var sdiProfileNotice: String?
    private(set) var connectorRows: [String: [ConnectorRow]] = [:]
    /// UI-002: what the signal map is drawn from (cached by `updateReadouts`, so drawing never asks a device).
    private(set) var sdiStatuses: [SDIDeviceStatus] = []
    private(set) var connectorMapsByDevice: [String: SDIConnectorMap] = [:]
    private(set) var videoURL: URL?
    private(set) var messages: [String] = []
    /// Screen profiles, Looks, props and custom themes, stored in the library (APP-001). Nil in a soak run, or when
    /// the library file could not be opened.
    private(set) var settings: SettingsModel?
    /// Stage layouts, timers and the stage clock (STAGE-001b). Nil in a soak run, or when the library could not be opened.
    private(set) var stage: StageModel?
    /// The one screen a soak run drives; a soak never reads or writes settings.
    @ObservationIgnored private var soakProfiles: [ScreenProfile] = []
    /// Image files that are missing or unreadable: from the files checked here and from what the outputs reported.
    private(set) var unavailableImages: [String] = []
    /// The operator workspace (OUT-004). Nil in a soak run, or when the library file could not be opened.
    private(set) var workspace: WorkspaceModel?
    private(set) var workspaceLoaded = false
    /// Objects (text boxes, shapes, images) on the selected slide (SLIDE-001b). Nil when the workspace is nil.
    private(set) var slideEditor: SlideEditorModel?
    /// The media bin and the background / foreground layers (MEDIA-001). Nil in a soak run, or when the library could not be opened.
    private(set) var media: MediaModel?
    /// The audio list, cues and programme audio device (MEDIA-005 / MEDIA-006). Nil under the same conditions.
    private(set) var audio: AudioModel?
    /// Set when the library file could not be opened: the path and a message. The file is left untouched.
    private(set) var libraryProblem: LibraryProblem?
    /// Bumped on every publish, so previews know to re-read their scene.
    private(set) var sceneRevision = 0
    /// R15: bumped only when something that changes how a slide looks changed (Look, theme, props, screens), so the
    /// slide thumbnails are not rebuilt on every keystroke or every Next.
    private(set) var appearanceRevision = 0
    /// Bumped on every publish including the stage's one-second ones, for the live previews only.
    private(set) var liveRevision = 0
    /// Sheets and focus requests shared by the menus and the views.
    let ui = WorkspaceUIState()

    @ObservationIgnored private let sceneBox: SceneBox
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]   // security-scoped access held while the prop exists
    @ObservationIgnored private lazy var coordinator: OutputCoordinator = makeCoordinator()
    /// The simulated SDI card and its real-time clock (HW-002). It is offered beside the real DeckLink provider only while
    /// the "Show simulated SDI device" developer setting is on.
    @ObservationIgnored private let simulatedCard = SimulatedSDIDevice()
    @ObservationIgnored private var simulatedClock: SimulatedClockDriver?
    @ObservationIgnored private var sdiMonitor: Task<Void, Never>?
    @ObservationIgnored private var changingProfiles = false
    static let simulatedCardID = "simulated-sdi-duo2"
    @ObservationIgnored private var video: LoopingVideoSource?
    /// Opens and closes the players for the media layers; every output reads frames from it (MEDIA-001).
    @ObservationIgnored let mediaRegistry = MediaRegistry()
    /// Access held to the files of open media layers (a security-scoped bookmark is resolved while its player is open).
    @ObservationIgnored private var mediaAccess: [MediaLayerSlot: (assetID: UUID, access: MediaAccess)] = [:]
    @ObservationIgnored private var knownMediaIDs: Set<UUID> = []
    @ObservationIgnored private var mediaTicker: Timer?
    /// Ends audio cues whose clip has reached its end by the clock (the player's own report does the same).
    @ObservationIgnored private var audioTicker: Timer?
    @ObservationIgnored private var clockText = ""
    @ObservationIgnored private var timer: Timer?
    /// Republishes the stage scenes every second, and exists only while a stage screen shows a clock or timer.
    @ObservationIgnored private var stageTicker: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var publicationGate = LivePublicationGate()
    /// R6: reads the file system for image availability, off the main thread.
    @ObservationIgnored private let imageMonitor = ImageAvailabilityMonitor()
    @ObservationIgnored private var reportedImages: [String] = []
    /// Images of the preview scenes that could not be read when they were decoded ahead of time.
    @ObservationIgnored private var warmedUnreadable: Set<String> = []
    @ObservationIgnored private var warmTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var soakTask: Task<Void, Never>?
    @ObservationIgnored private(set) var soak: SoakConfig?
    @ObservationIgnored private var soakProfileID: UUID?
    /// The Hardware Test window's controller (HWTEST-001). It refuses to start while the screens are open.
    @ObservationIgnored lazy var hardwareTest = HardwareTestController(
        realProvider: { AppHardwareTest.realProvider() }, environment: AppHardwareTest.environment(),
        screensOpen: { [unowned self] in self.screensOn || self.soak != nil },
        unfinishedParent: AppHardwareTest.unfinishedParent(),
        onRunningChange: { [unowned self] running in self.hardwareTestRunning = running })
    /// FIX-D S15: true while a Hardware Test run is going on. The screens cannot be opened then (the test uses the card).
    @ObservationIgnored private(set) var hardwareTestRunning = false

    private init() {
        sceneBox = SceneBox(PublishedScenes(state: ShowState(), clockText: nil))
        imageMonitor.onChange = { [weak self] _ in self?.refreshUnavailableImages() }
        soak = SoakConfig.parse(CommandLine.arguments)   // known first, so a soak never opens a library or writes settings
        refreshDisplayChoices()
        updateClock(force: true)
        if soak == nil && !HardwareTestLaunchMode.isHeadless { openLibrary() }   // a headless hardware test opens no library
        if soak == nil && !HardwareTestLaunchMode.isHeadless { startSDIMonitoring() }
    }

    // MARK: Library (OUT-004)

    /// `--library <path>` overrides the default file (for tests and screenshots); a bare launch uses ADR-0004's path.
    static func libraryURL(arguments: [String] = CommandLine.arguments) -> URL {
        if let i = arguments.firstIndex(of: "--library"), i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1])
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent("WORSHIPFLOW", isDirectory: true).appendingPathComponent("Library.sqlite")
    }

    private func openLibrary() {
        let url = Self.libraryURL()
        do {
            let store = try LibraryStore.open(at: url)
            let model = WorkspaceModel(store: store)
            model.onShowChange = { [weak self] state in self?.showChanged(state) }
            model.onAppearanceChange = { [weak self] in self?.lookChanged() }
            model.onClearAll = { [weak self] in self?.media?.stopForeground() }      // R8: Clear all also stops the clip
            workspace = model
            let editor = SlideEditorModel(workspace: model, imageChooser: { await Self.chooseImagePath() })
            editor.reservedFrames = { [weak self] content in
                // Where the audience screen puts this slide's words, so a new object is not dropped on top of them.
                guard let self, !content.primary.isEmpty || content.secondary != nil else { return [] }
                return self.thumbnailScene(for: SlideContent(primary: content.primary, secondary: content.secondary)).textLayers.map(\.frame)
            }
            slideEditor = editor
            let settings = SettingsModel(store: store, legacy: LegacySettingsFiles(libraryURL: url), defaultProfiles: { [weak self] in
                ScreenProfile.defaults(displays: NSScreen.screens.map(DisplayOutput.displayID(of:)),
                                       operatorDisplay: self?.operatorDisplayID())
            })
            settings.onProfilesChange = { [weak self] in self?.profilesChanged() }
            settings.onAppearanceChange = { [weak self] in self?.lookChanged() }
            settings.onSimulatedSDIDeviceChange = { [weak self] in self?.sdiDevicesChanged() }
            self.settings = settings
            let stage = StageModel(store: store)
            stage.onChange = { [weak self] in self?.publish() }
            self.stage = stage
            let media = MediaModel(store: store, prober: AppMediaProber())
            media.onLayersChange = { [weak self] layers in self?.mediaLayersChanged(layers) }
            media.onAssetsChange = { [weak self] assets in
                self?.mediaAssetsChanged(assets)
                self?.audio?.setAssets(assets)
            }
            media.onAudioChange = { [weak self] volume, muted in self?.mediaRegistry.setForegroundAudio(volume: volume, muted: muted) }
            mediaRegistry.setForegroundAudio(volume: Float(media.volume), muted: media.isMuted)
            // A player that failed or stalled: end the clip so the words come back, and tell the operator (R9).
            mediaRegistry.setOnAvailabilityChange { id, state in
                let mapped: ClipAvailability
                switch state {
                case .notOpen: mapped = .notOpen
                case .starting: mapped = .starting
                case .delivering: mapped = .delivering
                case .failed(let reason): mapped = .failed(reason)
                case .stalled: mapped = .stalled
                }
                Task { @MainActor in AppModel.shared.media?.availabilityChanged(id, mapped) }
            }
            mediaRegistry.setOnForegroundEnded {
                Task { @MainActor in AppModel.shared.media?.playerReportedEnd() }
            }
            self.media = media
            makeAudio(store: store)
        } catch {
            // The file is never deleted or replaced: the volunteer can keep it, move it or restore a backup.
            libraryProblem = LibraryProblem(path: url.path, message: error.localizedDescription)
            log("The library at \(url.path) could not be opened: \(error.localizedDescription)")
        }
    }

    func startWorkspace() {
        guard let workspace, !workspaceLoaded else { return }
        Task { @MainActor in
            await settings?.load()
            await stage?.load()
            await resolvePropBookmarks()
            await media?.load()
            await audio?.load()
            coordinator.setProfiles(profiles)
            publish()
            updateReadouts()
            await workspace.load()
            workspaceLoaded = true
            // Test hook for runs that cannot scroll: start with the Screens panel in view.
            if CommandLine.arguments.contains("--show-screens-panel") { workspace.setMode(.screens) }
            // Test hook for runs that cannot click: open the screens as soon as the workspace is loaded.
            if CommandLine.arguments.contains("--open-screens") { startScreens() }
        }
    }

    /// Command-N: an empty presentation in the selected library, opened with its title ready to type.
    func newPresentation() {
        guard let w = workspace else { return }
        Task { @MainActor in
            if await w.createPresentation(title: "New presentation") != nil { ui.focusTitle += 1 }
        }
    }

    /// Command-I: the import sheet, for a new presentation or (with an id) to re-flow an existing one.
    func openImport(existing id: UUID?) {
        guard workspace != nil else { return }
        ui.importExistingID = id
        ui.showImport = true
    }

    // MARK: Slide objects (SLIDE-001b)

    /// Insert menu: adds the object to the selected slide and shows the objects editor.
    func insertObject(_ template: NewSlideObject) {
        guard slideEditor?.slide != nil else { return }
        workspace?.setMode(.edit)          // the objects editor lives in Edit
        slideEditor?.add(template)
    }

    func insertImage() {
        guard slideEditor?.slide != nil else { return }
        workspace?.setMode(.edit)
        Task { @MainActor in await slideEditor?.addImage() }
    }

    /// True while a text field is being edited: Command-Z then belongs to that field, not to the objects.
    private var textFieldIsEditing: Bool { NSApp.keyWindow?.firstResponder is NSText }

    /// Command-Z.
    func undoEdit() {
        if textFieldIsEditing { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { slideEditor?.undo() }
    }

    /// Shift-Command-Z.
    func redoEdit() {
        if textFieldIsEditing { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { slideEditor?.redo() }
    }

    /// Command-D.
    func duplicateObject() {
        guard workspace?.mode == .edit else { return }
        slideEditor?.duplicateSelected()
    }

    /// The Delete key, only while the objects editor is showing.
    func deleteSelectedObject() -> Bool {
        guard workspace?.mode == .edit else { return false }
        return slideEditor?.deleteSelected() ?? false
    }

    /// The open panel for an image object. Returns the path, or nil if cancelled.
    static func chooseImagePath() async -> String? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.message = "Choose an image to put on the slide"
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url?.path : nil)
            }
        }
    }

    /// Writes everything that is waiting, in all four models: typed text and place, stage layouts and timers, settings
    /// (screens, Looks, props, themes) and the media bin. Called when the app loses focus and before it quits (R12).
    func flushWorkspace() async {
        await workspace?.flush()
        await stage?.flush()
        await settings?.flush()
        await media?.flush()
        await audio?.flush()
    }

    /// R4: what may happen now, given whether any screen is open. A soak run counts as open.
    func quitDecision(for request: QuitRequest) -> QuitDecision {
        QuitPolicy.decision(for: request, screensOpen: screensOn || soak != nil)
    }

    /// R4: Hide would take the screens' windows with it.
    var mayHide: Bool { QuitPolicy.mayHide(screensOpen: screensOn || soak != nil) }

    /// The scene a screen is showing now, for the live thumbnails.
    func scene(forScreen id: UUID) -> SceneDescription { sceneBox.read().scene(forScreen: id) }

    /// How `slide` looks on the audience screen, built by the same composer the outputs use.
    func thumbnailScene(for slide: SlideContent) -> SceneDescription {
        var state = ShowState()
        let deck = ShowDeck(presentationID: UUID(), slides: [slide])
        state.apply(.load(deck))
        state.apply(.trigger(index: 0))
        let profile = profiles.first { $0.role == .audience && $0.isEnabled }
            ?? profiles.first { $0.role == .audience }
            ?? ScreenProfile(name: "Audience", role: .audience, destination: .window)
        return PublishedScenes(state: state, clockText: nil, profiles: [profile], themes: themes, look: currentLook, props: props,
                               presentationThemeID: workspace?.openThemeID, media: media?.layers.withoutForeground)
            .scene(forScreen: profile.id)
    }

    /// The workspace changed the show: publish to every output and open the screens on the first slide.
    private func showChanged(_ state: ShowState) {
        let wasStopped = show.isStopped
        show = state
        media?.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut)     // Stop takes a playing clip off the screens too; Blackout takes its sound off
        audio?.showStateChanged(isLive: !state.isStopped)     // ... and ends the sound cues (Clear and Clear all leave them)
        // R15: typing, moving the selection and loading a deck change preview only; the screens are republished
        // (every scene composed again) only when what they show changed.
        scheduleImageWarm()
        if publicationGate.shouldPublish(LiveOutputKey(state: state, notes: workspace?.liveNotes)) { publish() }
        if wasStopped, !show.isStopped, !screensOn { startScreens() }
    }

    /// Decodes the images of the preview scenes before they go live, so every screen draws them in its first frame
    /// (R10). Debounced, off the main actor, and nothing waits for it: a trigger never blocks on this.
    private func scheduleImageWarm() {
        warmTask?.cancel()
        warmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            let scenes = self.previewScenes()
            let missing = await ImageWarmer.warm(scenes: scenes)
            guard !Task.isCancelled else { return }
            if missing != self.warmedUnreadable {
                self.warmedUnreadable = missing
                self.refreshUnavailableImages()
            }
        }
    }

    /// What each enabled audience and broadcast screen would show if the selected preview slide went live now.
    private func previewScenes() -> [SceneDescription] {
        guard let deck = show.previewDeck, deck.slides.indices.contains(show.selectedIndex) else { return [] }
        var state = ShowState()
        state.apply(.load(deck))
        state.apply(.trigger(index: show.selectedIndex))
        let screens = profiles.filter { $0.isEnabled && $0.role != .stage }
        let snapshot = PublishedScenes(state: state, clockText: nil, profiles: screens, themes: themes, look: currentLook,
                                       props: props, presentationThemeID: workspace?.openThemeID)
        return screens.map { snapshot.scene(forScreen: $0.id) }
    }

    private func makeCoordinator() -> OutputCoordinator {
        let sdi = SDIEnvironment(
            devices: { [weak self] in self?.sdiHandles() ?? [] },
            makeTarget: { [weak self] profile, setup in
                guard let self else { throw OutputSetupError.modelGone }
                return try self.makeSDITarget(profile, setup)
            })
        let c = OutputCoordinator(
            displays: { [weak self] in self?.displaySnapshot() ?? DisplaySnapshot(available: [], operatorDisplay: nil) },
            makeSlotTarget: { [weak self] profile, slot, destination in
                guard let self else { throw OutputSetupError.modelGone }
                return try self.makeTarget(profile, slot, destination)
            },
            sleepGuard: SleepGuard(), sdi: sdi)
        c.onChange = { [weak self] in self?.updateReadouts() }
        return c
    }

    private enum OutputSetupError: Error, LocalizedError {
        case modelGone, displayGone, sdiNotPlanned
        var errorDescription: String? {
            switch self {
            case .modelGone: "The app is shutting down."
            case .displayGone: "The display is no longer connected."
            case .sdiNotPlanned: "This SDI output was not set up through a card."
            }
        }
    }

    // MARK: Derived state for the UI

    var slides: [SlideContent] { show.previewDeck?.slides ?? [] }
    var selectedIndex: Int { show.selectedIndex }
    var liveIndex: Int? { show.liveIndex }
    var mode: LiveMode { show.isStopped ? .stopped : (show.isBlackedOut ? .blackout : (show.isCleared ? .cleared : .live)) }

    /// UI-001: the AUD, STG and BRD pills of the toolbar.
    var rolePills: [RolePill] {
        RolePills.pills(from: readouts.map { ScreenStatusInput(role: $0.role, isEnabled: $0.isEnabled, run: Self.runState($0.state)) })
    }

    /// UI-001: frame rate, dropped and late frames for the transport bar; nil while no screen runs.
    var outputHealth: OutputHealthSummary? {
        OutputHealth.summary(from: readouts.map {
            OutputHealthSample(role: $0.role, run: Self.runState($0.state), refreshRate: $0.refreshRate, dropped: $0.dropped, late: $0.late)
        })
    }

    private static func runState(_ state: ScreenState) -> ScreenRunState {
        switch state { case .stopped: .stopped; case .running: .running; case .hidden: .hidden; case .faulted: .faulted }
    }

    // MARK: Setup

    func installSystemHooks() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only real windows (operator or output window), never menus or panels.
            guard let window = event.window, window.canBecomeMain else { return event }
            // FIX-D S15: the Hardware Test window, and a session started for a hardware test, never drive the show with keys.
            guard KeyRouting.transportKeysActive(windowTitle: window.title, windowIdentifier: window.identifier?.rawValue,
                                                 launchedWithHardwareTest: HardwareTestLaunchMode.opensHardwareTest) else { return event }
            let responder = window.firstResponder
            let textInput = responder is NSText || responder is NSTextField
            let inSearch = textInput && Self.isInsideSearchField(responder)
            let held = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let shift = event.modifierFlags.contains(.shift)
            let key = KeyboardKey(keyCode: event.keyCode)
            let isRepeat = event.isARepeat      // R1: a held key never moves the show
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                let sheetOpen = self.ui.anySheetOpen || window.attachedSheet != nil
                switch KeyRouting.decision(for: key, textInputFocused: textInput, searchFieldFocused: inSearch,
                                           sheetOpen: sheetOpen, commandModifierDown: held, shiftDown: shift, isRepeat: isRepeat) {
                case .ignore:
                    return true                   // swallowed: not a second Next, and not a beep either
                case .transport(let command):
                    switch command {
                    case .goLive: self.goLive()
                    case .next: self.next()
                    case .previous: self.previous()
                    case .clear: self.clear()
                    case .clearAll: self.clearAll()
                    case .blackout: self.blackout()
                    }
                    return true
                case .leaveSearch:
                    self.ui.leaveSearch += 1      // the workspace view clears the search and puts focus on the slide grid
                    return true
                case .deleteSelectedObject:
                    return self.deleteSelectedObject()      // false (key passes through) when no object is selected
                case .passThrough:
                    return false
                }
            }
            return handled ? nil : event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateClock(force: false)
                self?.updateReadouts()
            }
        }
    }

    /// True when the text being edited belongs to a search field (the field editor is a subview of the field).
    private static func isInsideSearchField(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view {
            if current is NSSearchField { return true }
            view = current.superview
        }
        return false
    }

    private func displaySnapshot() -> DisplaySnapshot {
        DisplaySnapshot(available: NSScreen.screens.map(DisplayOutput.displayID(of:)),
                        operatorDisplay: soak == nil ? operatorDisplayID() : nil)
    }

    private func operatorDisplayID() -> UInt32? {
        let window = Self.operatorWindow.flatMap { $0.isVisible ? $0 : nil }
        guard let screen = window?.screen ?? NSScreen.screens.first else { return nil }
        return DisplayOutput.displayID(of: screen)
    }

    private func refreshDisplayChoices() {
        let operatorID = operatorDisplayID()
        displayChoices = NSScreen.screens.map { s in
            let id = DisplayOutput.displayID(of: s)
            let f = s.frame
            let suffix = id == operatorID ? ", operator display" : ""
            return DisplayChoice(id: id, name: "\(s.localizedName) (\(Int(f.width))x\(Int(f.height))\(suffix))")
        }
    }

    private func displaysChanged() {
        refreshDisplayChoices()
        coordinator.displaysChanged()
        updateReadouts()
    }

    func destinationName(_ destination: OutputDestination) -> String {
        ScreenEditing.destinationLabel(destination, devices: sdiDevices) { id in
            displayChoices.first { $0.id == id }?.name ?? "Display \(id) (not connected)"
        }
    }

    // MARK: Settings (APP-001)

    var profiles: [ScreenProfile] { settings?.profiles ?? soakProfiles }
    var looks: [Look] { settings?.looks ?? [] }
    var selectedLookID: UUID? { settings?.selectedLookID }
    var props: [Prop] { settings?.props ?? [] }
    /// Built-in themes and the operator's own: what the per-screen picker and the editor offer.
    var themes: [Theme] { settings?.themes ?? Theme.builtIn }
    /// A message from the settings store (a failed save), for the error bar.
    var settingsError: String? { settings?.lastError ?? stage?.lastError ?? media?.lastError ?? audio?.lastError }
    /// R3 / R12: why typed text or settings are not on disk yet. Persistent: it has no Dismiss and goes away only when
    /// the write succeeds.
    var unsavedProblems: [String] {
        [workspace?.draftSaveProblem, settings?.writeProblem, media?.writeProblem, audio?.writeProblem].compactMap { $0 }
    }
    func dismissSettingsError() {
        settings?.dismissError()
        stage?.dismissError()
        media?.dismissError()
        audio?.dismissError()
    }

    func updateProfile(_ profile: ScreenProfile) {
        if let settings {
            settings.updateProfile(profile)
        } else if let i = soakProfiles.firstIndex(where: { $0.id == profile.id }), soakProfiles[i] != profile {
            soakProfiles[i] = profile
            profilesChanged()
        }
    }

    private func profilesChanged() {
        appearanceRevision &+= 1
        publish()   // a role change composes a different scene
        coordinator.setProfiles(profiles)
        updateReadouts()
    }

    func restartScreen(_ id: UUID) {
        startVideoIfNeeded()
        coordinator.restart(id)
        screensOn = coordinator.isActive
        updateReadouts()
    }

    func stopScreen(_ id: UUID) {
        coordinator.stop(id)
        updateReadouts()
    }

    // MARK: Themes (APP-001)

    var customThemes: [Theme] { settings?.customThemes ?? [] }

    @discardableResult
    func createTheme(name: String) -> Theme? { settings?.createTheme(name: name) }
    @discardableResult
    func duplicateTheme(_ id: UUID) -> Theme? { settings?.duplicateTheme(id) }
    func renameTheme(_ id: UUID, to name: String) { settings?.renameTheme(id, to: name) }
    func updateTheme(_ id: UUID, _ change: (inout Theme) -> Void) { settings?.updateTheme(id, change) }

    /// Deletes a custom theme, then tells the workspace so presentations that used it show "default".
    func deleteTheme(_ id: UUID) {
        guard let settings else { return }
        Task { @MainActor in
            await settings.deleteTheme(id)
            await workspace?.themesChanged()
        }
    }

    /// The theme of the open presentation (nil: role default). Waits for a new theme to reach the library first.
    func setPresentationTheme(_ themeID: UUID?, forPresentation id: UUID) {
        guard let workspace else { return }
        Task { @MainActor in
            await settings?.flush()
            await workspace.setTheme(themeID, forPresentation: id)
        }
    }

    // MARK: Looks and props (OUT-003)

    var currentLook: Look? { settings?.currentLook }

    func screenLook(for screenID: UUID) -> ScreenLook { settings?.screenLook(for: screenID) ?? .standard }

    func selectLook(_ id: UUID) { settings?.selectLook(id) }
    func addLook() { settings?.addLook() }
    func renameLook(_ id: UUID, to name: String) { settings?.renameLook(id, to: name) }
    func deleteLook(_ id: UUID) { settings?.deleteLook(id) }
    func setTheme(_ themeID: UUID?, forScreen screenID: UUID) { settings?.setTheme(themeID, forScreen: screenID) }
    func setLayer(_ layer: LayerKind, visible: Bool, forScreen screenID: UUID) {
        settings?.setLayer(layer, visible: visible, forScreen: screenID)
    }

    func chooseProp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose an image for the prop (for example a logo)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.addProp(url) }
        }
    }

    func addProp(_ url: URL) {
        guard let settings else { return }
        let id = UUID()
        _ = url.startAccessingSecurityScopedResource()   // an open-panel URL is already accessible; keep access for the prop's lifetime
        scopedURLs[id] = url
        var bookmark: Data?
        do {
            bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            log("Could not remember access to \(url.lastPathComponent) across launches: \(error.localizedDescription)")
        }
        settings.addProp(Prop(id: id, name: url.deletingPathExtension().lastPathComponent, imagePath: url.path,
                              frame: NormalizedRect(x: 0.86, y: 0.04, width: 0.1, height: 0.1), opacity: 1, isOn: true),
                         bookmark: bookmark)
    }

    func setProp(_ id: UUID, isOn: Bool) { settings?.setProp(id, isOn: isOn) }

    func removeProp(_ id: UUID) {
        scopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        settings?.removeProp(id)
    }

    /// One publish per operator change. Writing to the library is the settings model's job.
    private func lookChanged() {
        appearanceRevision &+= 1
        scheduleImageWarm()
        publish()
        updateReadouts()
    }

    /// Reopens the image files of stored props through their bookmarks, so access survives a relaunch.
    private func resolvePropBookmarks() async {
        guard let settings else { return }
        for prop in settings.props {
            guard let data = await settings.bookmark(forProp: prop.id) else { continue }
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            _ = url.startAccessingSecurityScopedResource()
            scopedURLs[prop.id] = url
            if url.path != prop.imagePath || stale {     // follows the file if it was moved or renamed
                let fresh = stale ? (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) : nil
                settings.updatePropLocation(prop.id, path: url.path, bookmark: fresh)
            }
        }
    }

    /// Files the live scenes need that cannot be read (checked off the main thread), plus what the outputs reported.
    /// Sorted, no duplicates.
    private func refreshUnavailableImages() {
        let problems = Set(reportedImages).union(imageMonitor.unreadable).union(warmedUnreadable).sorted()
        if problems != unavailableImages { unavailableImages = problems }
    }

    // MARK: Video

    /// The soak run's `--video` loop (OUT-001). The workspace sets backgrounds from the media bin instead (MEDIA-001).
    func setVideo(_ url: URL?) {
        video?.stop()
        video = nil
        videoURL = nil
        if let url {
            do {
                video = try LoopingVideoSource(url: url)
                videoURL = url
            } catch {
                log("Could not open video: \(error.localizedDescription)")
            }
        }
        if screensOn {
            video?.start()
            // Running audience outputs captured the previous source; restart them so they pick up the new one.
            for r in coordinator.readouts() where r.role != .stage && (r.state == .running || r.state == .hidden) {
                coordinator.restart(r.id)
            }
            updateReadouts()
        }
    }

    private func startVideoIfNeeded() { if video != nil { video?.start() } }

    // MARK: Media (MEDIA-001)

    /// Frames of the media layers, for the live previews.
    var mediaFrames: any MediaFrameSource { mediaRegistry }

    /// The layers changed: open the players for what was newly chosen, close the rest, and publish scenes.
    private func mediaLayersChanged(_ layers: MediaLayers) {
        var closing: [MediaAccess] = []
        for (slot, layer) in [(MediaLayerSlot.background, layers.background), (.foreground, layers.foreground)] {
            let id = layer?.selection.assetID
            if let held = mediaAccess[slot], held.assetID == id { continue }
            if let held = mediaAccess.removeValue(forKey: slot) { closing.append(held.access) }
            guard let layer, let asset = media?.asset(layer.selection.assetID) else { continue }
            let access = MediaAccess.open(asset)
            mediaAccess[slot] = (asset.id, access)
            mediaRegistry.register(id: asset.id, kind: asset.kind, url: access.url, duration: asset.duration)
        }
        mediaRegistry.apply(layers)
        appearanceRevision &+= 1          // thumbnails draw the background
        closing.forEach { $0.stop() }          // the players that used these files are closed now
        updateMediaTicker(layers)
        publish()
    }

    /// Forgets what the registry holds for assets that left the bin.
    private func mediaAssetsChanged(_ assets: [MediaAsset]) {
        let ids = Set(assets.map(\.id))
        for gone in knownMediaIDs.subtracting(ids) { mediaRegistry.unregister(gone) }
        knownMediaIDs = ids
    }

    /// Runs only while a layer exists: ends a finished clip, and takes out a layer whose file could not be opened.
    private func updateMediaTicker(_ layers: MediaLayers) {
        let needed = layers.foreground != nil || layers.background != nil
        if needed, mediaTicker == nil {
            let ticker = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let media = self?.media else { return }
                    media.tick()
                    if let unavailable = self?.mediaRegistry.unavailableAssetIDs, !unavailable.isEmpty {
                        media.reportUnavailable(unavailable)
                    }
                }
            }
            RunLoop.main.add(ticker, forMode: .common)
            mediaTicker = ticker
        } else if !needed, let ticker = mediaTicker {
            ticker.invalidate()
            mediaTicker = nil
        }
    }

    // MARK: Audio (MEDIA-005 / MEDIA-006)

    /// Builds the audio model on the system's devices. `--silent-audio` renders every cue to nowhere (nothing is
    /// heard; the meter and the transport still move), for checking the interface without sound.
    private func makeAudio(store: LibraryStore) {
        let catalog = CoreAudioDeviceCatalog()
        let silent = CommandLine.arguments.contains("--silent-audio")
        let audio = AudioModel(store: store, devices: catalog, makeEngine: {
            let player = AudioCuePlayer(catalog: catalog, output: silent ? .offline(sampleRate: 48_000) : .hardware)
            player.pumpsOffline = silent
            return player
        }, access: { asset in
            let held = MediaAccess.open(asset)
            return AudioFileAccess(url: held.url, release: { held.stop() })
        })
        // Rule HW-08: one path per signal. The foreground video's sound goes to the same device as the cues.
        audio.onProgrammeDeviceChange = { [weak self] uid in self?.mediaRegistry.setAudioOutputDevice(uid: uid) }
        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.audio?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        audioTicker = ticker
        self.audio = audio
    }

    /// Choose pictures and videos for the bin with the system open panel.
    func chooseMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie, .audiovisualContent, .audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose pictures, videos and sound files for the media bin"
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated { self?.addMedia(urls) }
        }
    }

    /// Adds files chosen in the panel or dropped on the bin. Each gets a bookmark so access survives a relaunch.
    func addMedia(_ urls: [URL]) {
        guard let media else { return }
        Task { @MainActor in
            var bookmarks: [URL: Data] = [:]
            for url in urls {
                let started = url.startAccessingSecurityScopedResource()
                if let data = MediaAccess.bookmark(for: url) { bookmarks[url] = data }
                if started { url.stopAccessingSecurityScopedResource() }
            }
            await media.add(urls: urls, bookmarks: bookmarks)
        }
    }

    // MARK: Show control

    func send(_ command: ShowCommand) {
        let wasStopped = show.isStopped
        show.apply(command)
        publish()
        if wasStopped, !show.isStopped, !screensOn { startScreens() }
    }

    // With a workspace these go through it (playlist stepping, live bookkeeping); a soak run has none.
    func goLive() { if let w = workspace { Task { await w.goLive() } } else { send(.trigger(index: show.selectedIndex)) } }
    func next() { if let w = workspace { Task { await w.next() } } else { send(.next) } }
    func previous() { if let w = workspace { Task { await w.previous() } } else { send(.previous) } }
    func clear() { if let w = workspace { w.clear() } else { send(.clear) } }
    /// R8: Clear plus stopping the clip that plays over the slide.
    func clearAll() {
        if let w = workspace { w.clearAll() } else { send(.clearAll) }
    }
    /// Command-E: the quick edit popover lives in the Show mode, so go there first.
    func requestQuickEdit() {
        guard workspace?.show.liveSlide != nil else { return }
        workspace?.setMode(.show)
        ui.showQuickEdit = true
    }

    /// UI-001: Blackout (the B key, the transport bar).
    func blackout() { if let w = workspace { w.blackout() } else { send(.blackout) } }
    func stopShow() { if let w = workspace { w.stop() } else { send(.stop) } }

    private func publish() {
        sceneRevision &+= 1
        liveRevision &+= 1
        sceneBox.publish(makeSnapshot())
        updateStageTicker()
    }

    /// One immutable snapshot: every screen's scene for the state, Look, themes, props and stage layouts right now.
    private func makeSnapshot() -> PublishedScenes {
        let stageIDs = profiles.filter { $0.role == .stage }.map(\.id)
        let stageScenes = stage?.stageScenes(forScreens: stageIDs, state: show, notes: workspace?.liveNotes) ?? [:]
        return PublishedScenes(state: show, clockText: clockText, profiles: profiles, themes: themes,
                               look: currentLook, props: props, presentationThemeID: workspace?.shownThemeID,
                               stageScenes: stageScenes, media: media?.layers)
    }

    /// The stage's one-second republish. Skipped when nothing on any screen changed, and it does not touch the slide
    /// thumbnails (`sceneRevision`).
    private func stageTick() {
        let snapshot = makeSnapshot()
        guard snapshot != sceneBox.read() else { return }
        liveRevision &+= 1
        sceneBox.publish(snapshot)
    }

    /// Runs the ticker only while an enabled stage screen has a clock or a timer in its layout (LIVE-04).
    private func updateStageTicker() {
        let ids = profiles.filter { $0.role == .stage && $0.isEnabled }.map(\.id)
        let needed = stage?.needsPerSecondRefresh(forScreens: ids) ?? false
        if needed, stageTicker == nil {
            // First fire on the next whole second of the wall clock, so the clock text changes when the clock does.
            let next = Date(timeIntervalSinceReferenceDate: Date.now.timeIntervalSinceReferenceDate.rounded(.down) + 1)
            let ticker = Timer(fire: next, interval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stageTick() }
            }
            RunLoop.main.add(ticker, forMode: .common)   // keeps running while a menu or a drag is open
            stageTicker = ticker
        } else if !needed, let ticker = stageTicker {
            ticker.invalidate()
            stageTicker = nil
        }
    }

    /// True while the one-second stage republish is running (shown in the timers panel).
    var stageTickerRunning: Bool { stageTicker != nil }

    private func updateClock(force: Bool) {
        let text = Date.now.formatted(date: .omitted, time: .shortened)
        guard force || text != clockText else { return }
        clockText = text
        if stage == nil { publish() }     // with stage layouts the stage clock comes from the stage model, not from here
    }

    // MARK: Screens

    func startScreens() {
        // FIX-D S15: a Hardware Test run is using the card, so no screen is opened until it ends.
        if let why = HardwareTestGuard.screensRefusal(testIsRunning: hardwareTestRunning) {
            sdiProfileNotice = why
            Self.tellOperator("The screens cannot be opened now", why)
            return
        }
        let pending = keyingProfileChanges()
        guard pending.isEmpty else {
            guard !changingProfiles else { return }
            changingProfiles = true
            Task { [weak self] in
                await self?.changeProfilesThenStart(pending)
            }
            return
        }
        openScreensNow()
    }

    private func openScreensNow() {
        startVideoIfNeeded()
        coordinator.start()
        screensOn = true
        updateReadouts()
    }

    // MARK: Keying profiles (HW-004 / KI-054)

    /// Cards that a keyed screen is sent to and whose current profile cannot key. Nothing is changed here.
    private func keyingProfileChanges() -> [(device: SDIProvidedDevice, firstConnector: Int)] {
        let devices = sdiProvider().currentDevices()
        var found: [(device: SDIProvidedDevice, firstConnector: Int)] = []
        for profile in profiles where profile.isEnabled {
            for destination in [profile.destination] + profile.mirrors {
                guard case .sdi(let id, let connector, true, _) = destination, let device = devices.first(where: { $0.id == id }),
                      !found.contains(where: { $0.device.id == id && $0.firstConnector == connector }) else { continue }
                if case .askOperator = SDIKeyingProfile.decision(for: device.info, firstConnector: connector) {
                    found.append((device, connector))
                }
            }
        }
        return found
    }

    private func changeProfilesThenStart(_ pending: [(device: SDIProvidedDevice, firstConnector: Int)]) async {
        var notices: [String] = []
        for item in pending {
            let outcome = await SDIKeyingProfile.ensure(device: item.device, firstConnector: item.firstConnector) { change in
                await MainActor.run { Self.confirmProfileChange(change) }
            }
            notices.append(outcome.message)
            log(outcome.message)
        }
        sdiProfileNotice = notices.joined(separator: " ")
        changingProfiles = false
        sdiDevicesChanged()
        openScreensNow()      // a screen whose card could not key says so itself; the others open as usual
    }

    private static func tellOperator(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// The operator decides: changing a card's profile can interrupt outputs on its other connectors.
    private static func confirmProfileChange(_ change: SDIProfileChange) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Change the SDI card's profile?"
        alert.informativeText = change.question
        alert.addButton(withTitle: "Change the profile")
        alert.addButton(withTitle: "Leave it as it is")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func stopScreens() {
        coordinator.stop()
        video?.stop()
        media?.screensClosed()      // R17: the clip playing over the slide, and its sound, stop with the screens
        screensOn = false
        updateReadouts()
    }

    func shutdown() {
        audioTicker?.invalidate()
        audioTicker = nil
        audio?.shutdown()
        stopScreens()
        mediaRegistry.closeAll()
        mediaAccess.values.forEach { $0.access.stop() }
        mediaAccess.removeAll()
    }

    private func makeTarget(_ profile: ScreenProfile, _ slot: OutputSlot, _ destination: OutputDestination) throws -> any OutputTarget {
        let box = sceneBox
        let role = profile.role
        let screenID = profile.id
        let provider: SceneProvider = { box.read().scene(forScreen: screenID) }
        let source: (any VideoSourceFactory)? = role != .stage ? video : nil
        // The stage scene never names media, so it never asks; passing the registry to every output is still harmless.
        let mediaSource: (any MediaFrameSource)? = mediaRegistry
        let name = slot.mirror.map { "\(profile.name) mirror \($0 + 1)" } ?? profile.name
        switch destination {
        case .display(let id):
            guard let screen = NSScreen.screens.first(where: { DisplayOutput.displayID(of: $0) == id }) else {
                throw OutputSetupError.displayGone
            }
            return DisplayOutput(screen: screen, name: name, sceneProvider: provider, videoSource: source,
                                 mediaSource: mediaSource)
        case .window:
            // Each window output, primary or mirror, opens a little lower and to the right of the one before it.
            var index = 0
            outer: for p in profiles {
                for (i, d) in ([p.destination] + p.mirrors).enumerated() where d == .window {
                    if p.id == slot.screenID && (i == 0 ? nil : i - 1) == slot.mirror { break outer }
                    index += 1
                }
            }
            return WindowOutput(name: name, sceneProvider: provider, videoSource: source, cascadeIndex: index,
                                mediaSource: mediaSource)
        case .sdi:
            // The coordinator routes SDI through `makeSDITarget`, which needs an opened port.
            throw OutputSetupError.sdiNotPlanned
        }
    }

    // MARK: SDI (HW-002)

    /// The real DeckLink provider always, and the simulated card beside it while the developer setting is on (HW-004).
    private func sdiProvider() -> CompositeSDIProvider {
        var providers: [any SDIDeviceProviding] = [AppSDI.deckLink]
        if settings?.showSimulatedSDIDevice == true { providers.append(SimulatedSDIProvider(device: simulatedCard, id: Self.simulatedCardID)) }
        return CompositeSDIProvider(providers)
    }

    private func sdiHandles() -> [SDIDeviceHandle] {
        sdiProvider().currentDevices().map { SDIDeviceHandle($0) }
    }

    /// Looks for cards once off the main thread, then follows arrivals and removals. With no driver the stream ends at once.
    private func startSDIMonitoring() {
        guard sdiMonitor == nil else { return }
        refreshSDIEnvironment()
        sdiMonitor = Task { [weak self] in
            await Task.detached { AppSDI.deckLink.rescan() }.value
            self?.sdiDevicesChanged()
            for await _ in AppSDI.deckLink.events() { self?.sdiDevicesChanged() }
        }
    }

    /// The "Rescan" button: looks again for the driver's cards, off the main thread.
    func rescanSDI() {
        Task { [weak self] in
            await Task.detached { AppSDI.deckLink.rescan() }.value
            self?.sdiDevicesChanged()
        }
    }

    private func refreshSDIEnvironment() {
        let status = sdiProvider().environmentStatus()
        if status != sdiEnvironment { sdiEnvironment = status }
    }

    /// One clock per simulated card: every connector ticks at the rate of the first output's mode.
    private func simulatedClock(for mode: SDIVideoMode) -> SimulatedClockDriver {
        if let existing = simulatedClock, existing.isRunning || existing.mode == mode { return existing }
        let driver = SimulatedClockDriver(device: simulatedCard, mode: mode)
        simulatedClock = driver
        return driver
    }

    private func makeSDITarget(_ profile: ScreenProfile, _ setup: SDIOutputSetup) throws -> any OutputTarget {
        let box = sceneBox
        let screenID = profile.id
        let name = setup.slot.mirror.map { "\(profile.name) mirror \($0 + 1)" } ?? profile.name
        return SDIOutput(name: name, port: setup.port, mode: setup.planned.mode, keying: setup.planned.keying,
                         isSimulated: setup.info.isSimulated, sceneProvider: { box.read().scene(forScreen: screenID) },
                         videoSource: profile.role != .stage ? video : nil, mediaSource: mediaRegistry,
                         clock: setup.info.isSimulated ? simulatedClock(for: setup.planned.mode) : nil)
    }

    private func sdiDevicesChanged() {
        refreshSDIEnvironment()
        coordinator.devicesChanged()
        updateReadouts()
    }

    /// UI-002: System, Dark or Light for the operator window (outputs never follow it).
    var appearance: AppearanceChoice { settings?.appearance ?? .default }
    func setAppearance(_ choice: AppearanceChoice) { settings?.setAppearance(choice) }

    var showSimulatedSDIDevice: Bool { settings?.showSimulatedSDIDevice ?? false }

    func setShowSimulatedSDIDevice(_ on: Bool) { settings?.setShowSimulatedSDIDevice(on) }

    /// Developer control: the simulated card disappears, as if its cable were pulled.
    func simulateSDIUnplug() {
        guard showSimulatedSDIDevice else { return }
        simulatedCard.simulateUnplug()
        updateReadouts()
    }

    /// Developer control: the simulated card comes back; screens that were running on it resume (KI-012).
    func simulateSDIReplug() {
        guard showSimulatedSDIDevice else { return }
        simulatedCard.simulateReplug()
        sdiDevicesChanged()
    }

    func sdiDevice(id: String) -> SDIDeviceSummary? { sdiDevices.first { $0.id == id } }

    // MARK: Signal map (UI-002)

    /// The signal map of the Screens mode: drawn entirely from the profiles, the devices' reports and the planner's map.
    var signalMap: SignalMap {
        var states: [OutputSlot: ScreenState] = [:]
        for r in readouts {
            states[OutputSlot(screenID: r.id)] = r.state
            for m in r.mirrors { states[OutputSlot(screenID: r.id, mirror: m.index)] = m.state }
        }
        let names = Dictionary(uniqueKeysWithValues: displayChoices.map { ($0.id, $0.name) })
        return SignalMapPresenter.map(SignalMapInput(
            profiles: profiles, devices: sdiStatuses, maps: connectorMapsByDevice, states: states,
            displayName: { names[$0] ?? "Display \($0) (not connected)" }, hostName: Host.current().localizedName ?? "This Mac"))
    }

    /// Applies a preset the operator has read: each changed screen goes through the ordinary profile update, so the
    /// planner, and the question before a card profile change, work as for any manual change.
    func applyPreset(_ proposal: PresetProposal) {
        for p in proposal.applied(to: profiles) where profiles.first(where: { $0.id == p.id }) != p { updateProfile(p) }
    }

    /// Writes the diagnostic bundle (environment and devices, no video) to `url`. Returns nil on success, or the problem.
    func exportDiagnosticBundle(to url: URL) async -> String? {
        let provider = HardwareTestProvider(provider: sdiProvider())
        let code = await DiagnosticBundle.export(to: url, environment: AppHardwareTest.environment(), provider: provider)
        return code == 0 ? nil : "The log bundle could not be written to \(url.lastPathComponent)."
    }

    func updateReadouts() {
        let r = coordinator.readouts()
        if r != readouts { readouts = r }
        reportedImages = r.flatMap(\.unavailableImagePaths)
        // R6: the file system is asked on a background thread, and only about images the screens draw now.
        imageMonitor.check(ImageUsage.pathsInUse(props: props, themes: themes, profiles: profiles, look: currentLook,
                                                 presentationThemeID: workspace?.shownThemeID))
        refreshUnavailableImages()
        if screensOn != coordinator.isActive { screensOn = coordinator.isActive }
        let summaries = coordinator.sdiDevices().map { d in
            SDIDeviceSummary(id: d.id, name: d.info.displayName, connectorCount: d.info.connectorCount,
                             supportsKeying: d.info.supportsExternalKeying, isSimulated: d.info.isSimulated,
                             supportedModes: d.supportedModes.map { VideoModeDescription($0) }, isConnected: d.isConnected,
                             keyRoutes: d.info.keyRoutes.map { SDIKeyRouteSummary(firstConnector: $0.firstConnector, fillConnector: $0.fillConnector, keyConnector: $0.keyConnector) })
        }
        if summaries != sdiDevices { sdiDevices = summaries }
        let maps = coordinator.connectorMaps()
        let rows = maps.mapValues { ConnectorMapPresenter.rows(map: $0, profiles: profiles) }
        if rows != connectorRows { connectorRows = rows }
        let statuses = coordinator.sdiDevices()
        if statuses != sdiStatuses { sdiStatuses = statuses }
        if maps != connectorMapsByDevice { connectorMapsByDevice = maps }
    }

    private func log(_ message: String) {
        messages.append(message)
        if messages.count > 6 { messages.removeFirst() }
        FileHandle.standardError.write(Data("[WORSHIPFLOW] \(message)\n".utf8))
    }

    // MARK: Soak

    func startSoakIfRequested() {
        // `soak` was parsed in init: profiles are not persisted and the operator display is not protected in a soak.
        guard soakTask == nil, let config = soak else { return }
        if let path = config.videoPath { setVideo(URL(fileURLWithPath: path)) }
        var destination = OutputDestination.window
        if let i = config.screenIndex {
            guard NSScreen.screens.indices.contains(i) else {
                FileHandle.standardError.write(Data("--screen \(i) is out of range (\(NSScreen.screens.count) screens)\n".utf8))
                exit(2)
            }
            destination = .display(DisplayOutput.displayID(of: NSScreen.screens[i]))
        }
        let audience = ScreenProfile(name: "Audience", role: .audience, destination: destination)
        soakProfileID = audience.id
        soakProfiles = [audience]
        coordinator.setProfiles(profiles)
        send(.load(SoakDeck.deck))
        send(.trigger(index: 0))
        if !screensOn { startScreens() }
        let started = Date()
        soakTask = Task { @MainActor [weak self] in await self?.runSoak(config, destination: destination, started: started) }
    }

    private func soakReadout() -> ScreenReadout? {
        coordinator.readouts().first { $0.id == soakProfileID }
    }

    private func runSoak(_ config: SoakConfig, destination: OutputDestination, started: Date) async {
        var memory: [UInt64] = []
        if let m = MemoryProbe.residentBytes() { memory.append(m) }
        var lastSlideAt = 0.0, lastSampleAt = 0.0
        var advances = 0, samples = 0, hiddenSamples = 0
        var failure: String?
        let refreshAtStart = soakReadout()?.refreshRate ?? 0
        while true {
            try? await Task.sleep(for: .milliseconds(250))
            let t = Date().timeIntervalSince(started)
            let r = soakReadout()
            samples += 1
            switch r?.state {
            case .running?: break
            case .hidden?: hiddenSamples += 1
            default: failure = "audience output stopped before the soak finished: \(describe(r?.state))"
            }
            if failure != nil { break }
            if t - lastSlideAt >= 5 {
                lastSlideAt = t
                advances += 1
                send(.trigger(index: (show.selectedIndex + 1) % max(1, slides.count)))
            }
            if t - lastSampleAt >= 10 {
                lastSampleAt = t
                if let m = MemoryProbe.residentBytes() { memory.append(m) }
            }
            updateReadouts()
            if t >= config.seconds { break }
        }
        let duration = Date().timeIntervalSince(started)
        if let m = MemoryProbe.residentBytes() { memory.append(m) }
        let final = soakReadout()
        let errors = [final?.renderError].compactMap { $0 }
        let videoFrames = video?.deliveredFrameCount ?? 0
        let videoDiag = video?.diagnostics ?? "none"
        let diag = soakProfileID.flatMap { coordinator.diagnostics(for: $0) } ?? "none"
        stopScreens()

        let modeText: String
        if case .display(let id) = destination, let screen = NSScreen.screens.first(where: { DisplayOutput.displayID(of: $0) == id }) {
            if let dm = CGDisplayCopyDisplayMode(id) {
                modeText = "display output, \(screen.localizedName), \(dm.pixelWidth)x\(dm.pixelHeight) @ \(String(format: "%.2f", dm.refreshRate)) Hz (NSScreen max \(screen.maximumFramesPerSecond) Hz)"
            } else {
                modeText = "display output, \(screen.localizedName)"
            }
        } else {
            modeText = "window output, \(String(format: "%.0f", refreshAtStart)) Hz display"
        }
        var lines: [String] = []
        lines.append("WORSHIPFLOW OUT-002 soak report")
        lines.append("duration: \(String(format: "%.1f", duration)) s (requested \(config.seconds) s)")
        lines.append("display mode: \(modeText)")
        lines.append("slide advances: \(advances)")
        lines.append("video: \(config.videoPath ?? "none"), distinct frames delivered: \(videoFrames)")
        lines.append("presented: \(final?.presented ?? 0)")
        lines.append("dropped: \(final?.dropped ?? 0)")
        lines.append("late: \(final?.late ?? 0)")
        lines.append(String(format: "max interval: %.2f ms (target %.2f ms)", final?.maxIntervalMs ?? 0,
                            (final?.refreshRate ?? 0) > 0 ? 1000 / (final?.refreshRate ?? 1) : 0))
        lines.append("visibility: hidden (occluded) in \(hiddenSamples) of \(samples) samples")
        if let lo = memory.min(), let hi = memory.max() {
            lines.append("memory resident min: \(String(format: "%.1f", Double(lo) / 1_048_576)) MB, max: \(String(format: "%.1f", Double(hi) / 1_048_576)) MB (\(memory.count) samples)")
        } else {
            lines.append("memory: unavailable")
        }
        lines.append("video player: \(videoDiag)")
        lines.append("diagnostics: \(diag)")
        lines.append("render errors: \(errors.isEmpty ? "none" : errors.joined(separator: "; "))")
        var exitCode: Int32 = failure == nil ? 0 : 1
        if failure == nil, (final?.presented ?? 0) == 0 {
            if hiddenSamples > 0 {
                failure = "hidden: the output window was covered (for example by a full-screen app on that display), so no frames were presented and nothing was measured"
                exitCode = 4
            } else {
                failure = "no frames were presented"
                exitCode = 1
            }
        }
        lines.append("status: \(failure ?? "completed")")
        let text = lines.joined(separator: "\n") + "\n"
        let path = config.reportPath ?? defaultReportPath()
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try text.write(toFile: path, atomically: true, encoding: .utf8)
            print(text)
            print("report written to \(path)")
        } catch {
            FileHandle.standardError.write(Data("could not write report to \(path): \(error)\n".utf8))
            exit(3)
        }
        exit(exitCode)
    }

    private func describe(_ state: ScreenState?) -> String {
        switch state {
        case .stopped?, nil: "stopped"
        case .running?: "running"
        case .hidden?: "hidden"
        case .faulted(let m)?: m
        }
    }

    private func defaultReportPath() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return FileManager.default.currentDirectoryPath + "/AI/reports/soak-\(stamp).log"
    }
}
