// OUT-002: operator state. The show lives in `ShowState`, scenes come from `SceneComposer`, and outputs are run
// by `OutputCoordinator`. This model sends commands and reads status; it never renders. Render threads read an
// immutable `PublishedScenes` snapshot, never this object.
import AppKit
import SwiftUI
import Observation
import Domain
import MediaEngine
import OutputEngine
import RenderEngine
import SDIEngine
import DeckLinkSDI
import Persistence
import OperatorCore
import CueEngine
import CueStore
import MIDIIO
import RemoteControl
import ScriptureEngine
import ScriptureStore

enum LiveMode: Equatable { case stopped, live, cleared, blackout }

struct LibraryProblem: Equatable {
    var path: String
    var message: String
    /// FIX-H item 14: the library was last opened by a newer WorshipFlow. Nothing was written; the screen offers Quit or another library.
    var fromNewerBuild = false
}

struct DisplayChoice: Identifiable, Equatable {
    var id: UInt32
    var name: String
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    static let operatorWindowTitle = "WorshipFlow"
    /// The operator window is found by this identifier (set when its view reaches the window), because its title is the service name.
    static let operatorWindowIdentifier = NSUserInterfaceItemIdentifier("wf-operator-window")
    static var operatorWindow: NSWindow? {
        NSApplication.shared.windows.first { $0.identifier == operatorWindowIdentifier } ?? NSApplication.shared.windows.first { $0.title == operatorWindowTitle }
    }

    /// FIX-O (KI-180): what the outputs were last told, observable one part at a time like the workspace's own (`ObservedShow`). Views read
    /// `showParts.<part>`; `show` is the whole state and depends on every part.
    let showParts = ObservedShow()
    private(set) var show: ShowState {
        get { showParts.state }
        set { showParts.set(newValue) }
    }
    private(set) var readouts: [ScreenReadout] = []
    private(set) var displayChoices: [DisplayChoice] = []
    private(set) var screensOn = false
    /// SDI cards the coordinator can see now (HW-002), and what each connector of each carries.
    private(set) var sdiDevices: [SDIDeviceSummary] = []
    /// The state of the SDI driver and cards (HW-004): shown as one calm line in the Screens panel when there is no driver or no card.
    private(set) var sdiEnvironment: SDIEnvironmentStatus?
    /// What happened the last time the app was asked to change a card's profile for fill and key (KI-054).
    private(set) var sdiProfileNotice: String?
    /// FIX-J item 6: set at launch, once, when the font the output looks name does not resolve to the bundled Inter (it could not be registered).
    private(set) var fontNotice: String? = AppModel.fontCheckAtLaunch()
    func dismissFontNotice() { fontNotice = nil }
    private static func fontCheckAtLaunch() -> String? {
        _ = InterFont.base      // registration comes first, so the check sees what the screens will see
        return OutputFont.check().operatorNotice
    }
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
    /// LIB-005: the open library, for program export and import (they read and write it through its one connection pool).
    @ObservationIgnored private(set) var libraryStore: LibraryStore?
    private(set) var workspaceLoaded = false
    /// Objects (text boxes, shapes, images) on the selected slide (SLIDE-001b). Nil when the workspace is nil.
    private(set) var slideEditor: SlideEditorModel?
    /// The media bin and the background / foreground layers (MEDIA-001). Nil in a soak run, or when the library could not be opened.
    private(set) var media: MediaModel?
    /// The audio list, cues and programme audio device (MEDIA-005 / MEDIA-006). Nil under the same conditions.
    private(set) var audio: AudioModel?
    /// MEDIA-010: the folders the media bin follows, and the player in the Media mode's sidebar.
    private(set) var hotFolders: HotFolderModel?
    private(set) var binPreview: MediaPreviewModel?
    @ObservationIgnored let binPreviewPlayer = AVPreviewPlayer()
    @ObservationIgnored let hotFolderAccess = HotFolderAccess()
    @ObservationIgnored private var knownHotFolderIDs: Set<UUID> = []
    @ObservationIgnored private var hotTick = 0
    /// MEDIA-010: when the live slide's own background started, so a publish does not restart its video.
    @ObservationIgnored private var ownBackgroundStart: (selection: MediaSelection, at: Double)?
    /// Macros, slide actions, the schedule, MIDI and the remote control, and the one command path every show command goes through
    /// (CUE-002b). Nil under the same conditions.
    private(set) var cue: CueModel?
    /// The Scripture view's model: translations, the typed reference, search, keeping a passage (LIB-004c). Nil under the same conditions.
    private(set) var scripture: ScriptureModel?
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

    @ObservationIgnored private var mediaItemPlayer: MediaItemPlayer?
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
    @ObservationIgnored private var cueTimer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    /// Republishes the stage scenes every second, and exists only while a stage screen shows a clock or timer.
    @ObservationIgnored private var stageTicker: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var mouseMonitor: Any?      // FIX-N item 8
    @ObservationIgnored private var keyUpMonitor: Any?      // FIX-N item 5
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
        return LibraryLocation.defaultURL(applicationSupport: base)
    }

    private func openLibrary() {
        let url = Self.libraryURL()
        do {
            let store = try LibraryStore.open(at: url)
            libraryStore = store
            let model = WorkspaceModel(store: store)
            model.onShowChange = { [weak self] state in self?.showChanged(state) }
            model.onAppearanceChange = { [weak self] in self?.lookChanged() }
            workspace = model
            let editor = SlideEditorModel(workspace: model, imageChooser: { await Self.chooseImagePath() })
            editor.nudgeQuietPeriod = NudgeTiming.quietPeriod(keyRepeatDelay: NSEvent.keyRepeatDelay, floor: 1.0)      // FIX-P item 6: longer than the system's delay until repeat
            editor.reservedFrames = { [weak self] content in
                // Where the audience screen puts this slide's words, so a new object is not dropped on top of them.
                guard let self, !content.primary.isEmpty || content.secondary != nil else { return [] }
                return self.thumbnailScene(for: SlideContent(primary: content.primary, secondary: content.secondary, textFrames: content.textFrames)).textLayers.map(\.frame)
            }
            editor.lyricThemeFrames = { [weak self] content in self?.lyricThemeFrames(for: content) ?? [:] }
            editor.lyricThemeRevision = { [weak self] in self?.appearanceRevision ?? 0 }      // FIX-N item 8: composed again only when the theme or the screens change
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
            // MEDIA-010: the background video has its own sound state, muted until the operator unmutes it.
            media.onBackgroundAudioChange = { [weak self] volume, muted in self?.mediaRegistry.setBackgroundAudio(volume: volume, muted: muted) }
            mediaRegistry.setBackgroundAudio(volume: Float(media.volume), muted: media.backgroundHeardMuted)
            // A new live background brings a cleared one back.
            if let workspace { MediaWiring.connect(workspace: workspace, media: media) }      // R8, FIX-I item 4: Clear all stops the clip and drops the bin's background
            // FIX-G: bookmarks are resolved off the main actor, without UI and without mounting (HotFolderAccess).
            let hot = HotFolderModel(store: store, listing: FileSystemFolderListing(), watching: DispatchFolderWatching(), prober: AppMediaProber(),
                                     access: hotFolderAccess)
            hot.onAssetsChange = { [weak self] byFolder in
                guard let self, let media = self.media else { return }
                for (id, items) in byFolder { media.setHotAssets(id, items) }
                for gone in self.knownHotFolderIDs.subtracting(byFolder.keys) { media.setHotAssets(gone, []) }
                self.knownHotFolderIDs = Set(byFolder.keys)
            }
            hotFolders = hot
            // FIX-G: starts muted every session (its sound would go through the Mac's default output, maybe the house system).
            binPreview = MediaPreviewModel.sessionPreview(player: binPreviewPlayer, silent: CommandLine.arguments.contains("--silent-audio"))
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
            // UI-005b: the playlist's media-file items and announcements loops play through the bin's own models.
            let player = MediaItemPlayer(media: media, audio: audio, preview: { [weak self] id in self?.selectBinItem(id) })
            mediaItemPlayer = player
            model.mediaItemHandler = { [weak player] command in player?.handle(command) ?? .ok }
            model.mediaItemPreflight = { [weak player] kind in player?.runner.preflight(kind) }
            player.runner.onLoopEnded = { [weak model] in model?.mediaItemEnded() }      // FIX-H item 11: the playlist stops showing it live
            makeCue(library: store, workspace: model, settings: settings, stage: stage, media: media)
            makeScripture(library: store, workspace: model)
        } catch {
            // The file is never deleted or replaced: the volunteer can keep it, move it or restore a backup.
            if let newer = error as? LibraryFromNewerBuildError {
                libraryProblem = LibraryProblem(path: url.path, message: newer.message(thisBuild: "\(BuildInfo.current.version), build \(BuildInfo.current.build)"), fromNewerBuild: true)
            } else {
                libraryProblem = LibraryProblem(path: url.path, message: error.localizedDescription)
            }
            log("The library at \(url.path) could not be opened: \(error.localizedDescription)")
        }
    }

    /// CUE-002b: the cue wiring. MIDI and the remote server exist only when the operator turns them on in the Cues mode.
    private func makeCue(library: LibraryStore, workspace: WorkspaceModel, settings: SettingsModel, stage: StageModel, media: MediaModel) {
        let ports = CuePorts(transport: workspace, looks: settings, stage: stage, media: MediaCueAdapter(media: media, audio: audio), midiOut: { nil })
        let cue = CueModel(store: CueStore(library: library), ports: ports, settingsStore: library)
        cue.connect(workspace)
        cue.midiPortsFactory = { try CoreMIDIPorts() }
        cue.hardwareTestIsRunning = { [weak self] in self?.hardwareTestRunning ?? false }
        // Runs and tests may keep the server to the loopback interface and a free port: `--remote-loopback-only`, `--remote-port <n>`.
        let args = CommandLine.arguments
        cue.remoteLoopbackOnly = args.contains("--remote-loopback-only")
        if let i = args.firstIndex(of: "--remote-port"), i + 1 < args.count, let port = UInt16(args[i + 1]) { cue.remotePortOverride = port }
        cue.remoteStateSource = { [weak workspace, weak stage, weak cue] in
            guard let workspace, let cue else { return RemoteState() }
            return RemoteStateBuilder.make(workspace: workspace, stage: stage, macros: cue.macros)
        }
        self.cue = cue
    }

    /// LIB-004c: the scripture model, joined to the workspace before it loads (so a playlist item that is restored can open).
    private func makeScripture(library: LibraryStore, workspace: WorkspaceModel) {
        let model = ScriptureModel(store: ScriptureStore(library: library), stateStore: library)
        model.themeProvider = { [weak self] in self?.scriptureTheme() ?? .fullScreen }
        model.connect(workspace)
        scripture = model
    }

    /// The theme of the audience screen as the operator has it now: its Look's theme, else the built-in full-screen one. Its text
    /// boxes decide how much of a passage fits on a slide.
    private func scriptureTheme() -> Theme {
        let audience = profiles.first { $0.role == .audience && $0.isEnabled } ?? profiles.first { $0.role == .audience }
        let look = audience.map { currentLook?.screenLook(for: $0.id, in: profiles) ?? .standard } ?? .standard
        return ThemeResolver.theme(for: .audience, lookThemeID: look.themeID, presentationThemeID: nil, themes: themes)
    }

    /// Command-J: the Scripture view in Show, with the cursor in the reference field.
    func openScripture() {
        guard let w = workspace else { return }
        w.setMode(.show)
        ui.scriptureOpen = true
        ui.focusScripture += 1
    }

    func startWorkspace() {
        guard let workspace, !workspaceLoaded else { return }
        Task { @MainActor in
            // UI-005b: a library that did not exist before this launch is new: it gets the design's four Looks. Read before the
            // workspace load creates its first library.
            let isNewLibrary = ((try? await libraryStore?.libraries().isEmpty) ?? false)
            await settings?.load()
            await settings?.seedDesignLooks(isNewLibrary: isNewLibrary)
            await stage?.load()
            await resolvePropBookmarks()
            await media?.load()
            // FIX-G: launch never waits on a hot folder (a drive that is gone, a slow network share). The folders fill in when they answer,
            // and a remembered hot-folder background is restored then.
            await hotFolders?.load(waitForScans: false)
            await audio?.load()
            await scripture?.load()
            coordinator.setProfiles(profiles)
            publish()
            updateReadouts()
            await workspace.load()
            await cue?.start()
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
    /// FIX-K: the theme's frame for each language of `content` on the audience screen: what the Edit canvas draws as the lyric boxes. A language with no words has
    /// none, and neither has a theme with a plate (the plate stacks its lines itself and uses no frames). The slide's own frames are left out on purpose.
    func lyricThemeFrames(for content: SlideContent) -> [LyricBox: NormalizedRect] {
        let scene = thumbnailScene(for: SlideContent(primary: content.primary, secondary: content.secondary))
        guard scene.plate == nil else { return [:] }
        // FIX-N item 8: the words' layers are found by position, not by comparing their text (a layer's text may be shaped by the composer): props add
        // their own text layers after the words, so what a slide with no words at all composes is the number to leave out.
        let propLayers = thumbnailScene(for: SlideContent(primary: "", secondary: nil)).textLayers.count
        let layers = Array(scene.textLayers.prefix(max(0, scene.textLayers.count - propLayers)))
        var frames: [LyricBox: NormalizedRect] = [:]
        var index = 0
        if !content.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, index < layers.count {
            frames[.primary] = layers[index].frame
            index += 1
        }
        if let secondary = content.secondary, !secondary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, index < layers.count {
            frames[.secondary] = layers[index].frame
        }
        return frames
    }

    /// FIX-K: an arrow key in Edit moves the selected object or lyric box by one point (ten with Shift). False when nothing is selected there: the key then moves the
    /// slide selection as before.
    func nudgeIfEditing(_ move: SelectionMove, big: Bool) -> Bool {
        guard workspace?.mode == .edit, let editor = slideEditor else { return false }
        let (columns, rows): (Int, Int)
        switch move {
        case .left: (columns, rows) = (-1, 0)
        case .right: (columns, rows) = (1, 0)
        case .up: (columns, rows) = (0, -1)
        case .down: (columns, rows) = (0, 1)
        }
        return editor.nudgeSelection(columns: columns, rows: rows, big: big)
    }

    /// FIX-N item 8: a box is selected on the canvas of the mode that is showing: what an arrow key may nudge although a button has keyboard focus.
    var canvasSelectionForArrows: Bool {
        guard let mode = workspace?.mode else { return false }
        return CanvasArrows.hasSelection(mode: mode, editHasSelection: slideEditor?.selectedObjectID != nil || slideEditor?.selectedLyricBox != nil,
                                         stageTakesArrows: ui.stageTakesArrows)
    }

    /// FIX-N item 8: an arrow key for the canvas that was clicked last. Edit nudges the selected object or lyric box; Stage hands the nudge to its canvas.
    @discardableResult
    func nudgeLastClickedCanvas(_ move: SelectionMove, big: Bool) -> Bool {
        switch workspace?.mode {
        case .edit: return nudgeIfEditing(move, big: big)
        case .stage:
            let (dx, dy): (Int, Int) = switch move { case .left: (-1, 0); case .right: (1, 0); case .up: (0, -1); case .down: (0, 1) }
            return ui.stageArrow?(dx, dy, big) ?? false
        default: return false
        }
    }

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
        await cue?.flushSchedule()
        await cue?.flushRemote()
    }

    /// CUE-002b: before the app goes away, remember the schedule's last look, stop the remote server (the port is released) and
    /// release MIDI (the virtual ports are disposed).
    func stopCue() async {
        await cue?.flushSchedule(force: true)
        await cue?.stopRemote()
        cue?.shutdown()
    }

    /// R4: what may happen now, given whether any screen is open. A soak run counts as open.
    func quitDecision(for request: QuitRequest) -> QuitDecision {
        QuitPolicy.decision(for: request, screensOpen: screensOn || soak != nil)
    }

    /// R4: Hide would take the screens' windows with it.
    var mayHide: Bool { QuitPolicy.mayHide(screensOpen: screensOn || soak != nil) }

    /// The scene a screen is showing now, for the live thumbnails.
    func scene(forScreen id: UUID) -> SceneDescription { sceneBox.read().scene(forScreen: id) }

    /// FIX-I item 5: the stills thumbnails draw their picture and video backgrounds from.
    @ObservationIgnored let thumbnailStills = ThumbnailStills()

    /// FIX-I item 5: which background a thumbnail of `slide` draws (its own, else the presentation's or the theme's) and whether it is missing.
    func thumbnailBackground(for slide: SlideContent) -> ThumbnailBackground {
        let profile = profiles.first { $0.role == .audience && $0.isEnabled } ?? profiles.first { $0.role == .audience }
        let lookTheme = profile.flatMap { currentLook?.screenLook(for: $0.id, in: profiles).themeID }
        let theme = ThemeResolver.theme(for: .audience, lookThemeID: lookTheme, presentationThemeID: workspace?.openThemeID, themes: themes)
        let fromPresentation = lookTheme == nil && workspace?.openThemeID == theme.id
        return ThumbnailBackground.resolve(slide: slide, theme: theme, themeIsThePresentations: fromPresentation,
                                           available: media.map { Set($0.allAssets.map(\.id)) })
    }

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
                               presentationThemeID: workspace?.openThemeID,
                               media: LiveMedia.preview(slide: slide, at: MediaClock.now()))
            .scene(forScreen: profile.id)
    }

    /// The workspace changed the show: publish to every output and open the screens on the first slide.
    private func showChanged(_ state: ShowState) {
        let wasStopped = show.isStopped
        PhaseProbe.time("show=") { show = state }
        PhaseProbe.time("media/audio") {
            media?.showStateChanged(isLive: !state.isStopped, isBlackedOut: state.isBlackedOut)     // Stop takes a playing clip off the screens too; Blackout takes its sound off
            audio?.showStateChanged(isLive: !state.isStopped)     // ... and ends the sound cues (Clear and Clear all leave them)
        }
        // R15: typing, moving the selection and loading a deck change preview only; the screens are republished
        // (every scene composed again) only when what they show changed.
        PhaseProbe.time("imageWarm") { scheduleImageWarm() }
        PhaseProbe.time("syncMedia") { syncMediaPlayers() }          // MEDIA-010: the new live slide may bring its own background (or take it away)
        let publishNow = PhaseProbe.time("gate") { publicationGate.shouldPublish(LiveOutputKey(state: state, notes: workspace?.liveNotes)) }
        if publishNow { publish() }
        PhaseProbe.time("remote") { cue?.remoteStateMayHaveChanged() }     // CUE-002b: phones connected to the remote server see the new slide at once
        PhaseProbe.time("stage") { stage?.showStateChanged(isStopped: state.isStopped) }      // Stop takes the stage message off the stage screens
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
            let missing = await ImageWarmer.warm(scenes: scenes.map(\.scene))
            guard !Task.isCancelled else { return }
            // FIX-J item 2: the text of the selected slide is rasterised too, off the main thread, at each screen's size, so the first live frame draws it warm.
            await TextWarmer.warm(scenes: scenes.flatMap { entry in entry.sizes.map { (entry.scene, $0.width, $0.height) } })
            guard !Task.isCancelled else { return }
            if missing != self.warmedUnreadable {
                self.warmedUnreadable = missing
                self.refreshUnavailableImages()
            }
        }
    }

    /// What each enabled audience and broadcast screen would show if the selected preview slide went live now.
    private func previewScenes() -> [(scene: SceneDescription, sizes: [(width: Int, height: Int)])] {
        guard let deck = show.previewDeck, deck.slides.indices.contains(show.selectedIndex) else { return [] }
        var state = ShowState()
        state.apply(.load(deck))
        state.apply(.trigger(index: show.selectedIndex))
        let screens = profiles.filter { $0.isEnabled && $0.role != .stage }
        let snapshot = PublishedScenes(state: state, clockText: nil, profiles: screens, themes: themes, look: currentLook,
                                       props: props, presentationThemeID: workspace?.openThemeID)
        return screens.map { profile in
            // An SDI screen draws at its card mode's size; a window or display at its own (not known here): the 1080-line frame most are.
            var sizes: [(width: Int, height: Int)] = profile.destination.isSDI || profile.mirrors.contains(where: \.isSDI)
                ? [(profile.videoMode.width, profile.videoMode.height)] : []
            if !profile.destination.isSDI || profile.mirrors.contains(where: { !$0.isSDI }) { sizes.append((1920, 1080)) }
            return (snapshot.scene(forScreen: profile.id), sizes)
        }
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

    var slides: [SlideContent] { showParts.previewDeck?.slides ?? [] }
    var selectedIndex: Int { showParts.selectedIndex }
    var liveIndex: Int? { showParts.liveIndex }
    var mode: LiveMode { showParts.isStopped ? .stopped : (showParts.isBlackedOut ? .blackout : (showParts.isCleared ? .cleared : .live)) }

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
            let appKitFocus = Self.appKitFocus(of: responder)
            let inNativeSearch = textInput && Self.isInsideSearchField(responder)
            let held = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let shift = event.modifierFlags.contains(.shift)
            let key = KeyboardKey(keyCode: event.keyCode)
            let endsCanvasClick = KeyRouting.clearsCanvasClick(keyCode: event.keyCode)      // FIX-P item 6: Tab moves focus on purpose
            let isRepeat = event.isARepeat      // R1: a held key never moves the show
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                if endsCanvasClick { self.ui.canvasLastClicked = false }
                let sheetOpen = self.ui.anySheetOpen || window.attachedSheet != nil
                let inSearch = inNativeSearch || (textInput && self.ui.searchHasFocus)
                // FIX-H item 7: what has focus decides. A control the app drew reports its own focus; an AppKit control is read from the
                // responder chain. A focused control keeps Space, Return and the arrows.
                let focus: FocusedElement = textInput ? (inSearch ? .searchField : .textInput) : (self.ui.focusedControl ?? appKitFocus)
                // FIX-N items 1 and 8: a box is selected on the canvas that has focus, or on the canvas that was clicked last.
                let canvasHasSelection = (window.firstResponder as? StageKeyView)?.takesArrows ?? self.canvasSelectionForArrows
                if self.handleCueKeyTrigger(keyCode: event.keyCode, modifierHeld: held, shift: shift, isRepeat: isRepeat, focus: focus, textInput: textInput, sheetOpen: sheetOpen) { return true }      // UI-006g (CU-21): a macro's function key
                switch KeyRouting.decision(for: key, focus: focus, canvasHasSelection: canvasHasSelection, canvasLastClicked: self.ui.canvasLastClicked, section: self.effectiveKeySection, sheetOpen: sheetOpen, commandModifierDown: held, shiftDown: shift, isRepeat: isRepeat) {
                case .focusShow:
                    self.ui.controlFocusTracker.clear()
                    window.makeFirstResponder(nil)
                    self.ui.focusGrid += 1        // the workspace view puts focus on the slide grid
                    return true
                case .ignore:
                    return true                   // swallowed: not a second Next, and not a beep either
                case .transport(let command):
                    switch command {
                    case .goLive: self.goLive(from: .key)
                    case .next: self.next(from: .key)
                    case .previous: self.previous(from: .key)
                    case .clear: self.clear(from: .key)
                    case .clearAll: self.clearAll(from: .key)
                    case .blackout: self.blackout(from: .key)
                    }
                    return true
                case .nudgeCanvas(let move):
                    _ = self.nudgeLastClickedCanvas(move, big: shift)      // FIX-N item 8: the canvas was clicked last; a button's focus does not take its arrows
                    return true
                case .moveSelection(let move):
                    if self.nudgeIfEditing(move, big: shift) { return true }       // FIX-K: in Edit with an object or lyric box selected, an arrow nudges it
                    self.moveSelection(move)       // FIX-I item 2: Preview only, never the live slide
                    return true
                case .sendBinSelectionLive:
                    self.sendBinSelectionLive()
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
        // FIX-N item 8: every mouse press clears "the canvas was clicked last"; a canvas's own press sets it again (local monitors run before the view's gesture).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.ui.canvasLastClicked = false }
            return event
        }
        // FIX-N items 5 and 8: an arrow key's release ends the Stage canvas's run of nudges, whichever view has the keyboard.
        keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if [123, 124, 125, 126].contains(event.keyCode) { MainActor.assumeIsolated { self?.ui.stageArrowReleased?() } }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateClock(force: false)
                self?.updateReadouts()
                self?.hotFolderTick()
                self?.cue?.tick()                    // CUE-002b: delivers waited stages of macros that have come due
                self?.mediaItemPlayer?.tick()        // FIX-H item 1: an announcements loop moves on, or ends when the foreground is no longer its
            }
        }
        // CUE-002b: once a second the schedule looks at the wall clock, MIDI devices and the remote server report their state; a
        // Mac that wakes from sleep looks at once, so what was missed in its sleep is reported.
        cueTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let cue = self?.cue else { return }
                cue.pollSchedule()
                cue.refreshMIDI()
                cue.refreshRemote()
                cue.remoteStateMayHaveChanged()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cue?.wakeFromSleep() }
        }
    }

    /// FIX-H item 7: what kind of AppKit control is the first responder, for the key router. A pop-up is checked before a button (it is
    /// one). Every kind of AppKit button counts as a button: Space and Return act on it either way.
    static func appKitFocus(of responder: NSResponder?) -> FocusedElement {
        var view = responder as? NSView
        while let current = view {
            switch current {
            case is NSPopUpButton: return FocusedElement.appKit(.popUpButton)
            case is NSButton: return FocusedElement.appKit(.pushButton)
            case is NSSegmentedControl: return FocusedElement.appKit(.segmentedControl)
            case is NSSlider: return FocusedElement.appKit(.slider)
            case is NSTabView: return FocusedElement.appKit(.tabView)
            default: view = current.superview
            }
        }
        return .none
    }

    #if DEBUG || WF_MEASURE
    /// FIX-I (debug hook): the focus the key monitor would compute for this window right now.
    static func keyFocus(window: NSWindow, ui: WorkspaceUIState) -> FocusedElement {
        let responder = window.firstResponder
        if responder is NSText || responder is NSTextField { return .textInput }
        return ui.focusedControl ?? appKitFocus(of: responder)
    }
    #endif

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

    /// UI-005b: the cards for outputs that stopped sending (Retry output, Details), and what the last Retry found per output.
    var faultCards: [OutputFaultCard] { OutputFaultCards.cards(from: readouts) }
    private(set) var retryNotes: [UUID: String] = [:]

    // FIX-I item 7: the card fades five seconds after it appears; the pill and the monitor keep the fault until the output sends again.
    @ObservationIgnored private var faultVisibility = FaultCardVisibility()
    /// The clock the fade reads (injected so a debug run can drive it).
    @ObservationIgnored var faultClock: () -> Date = { Date() }
    /// The screens whose fault card is on show now.
    private(set) var shownFaultIDs: Set<UUID> = []
    var shownFaultCards: [OutputFaultCard] { faultCards.filter { shownFaultIDs.contains($0.screenID) } }

    /// Looks at the cards again: a new fault shows, a card whose five seconds are up fades. Called with every refresh of the readouts.
    func refreshFaultVisibility() {
        let now = faultClock()
        faultVisibility.update(cards: faultCards, now: now)
        let ids = Set(faultVisibility.visibleCards(from: faultCards, now: now).map(\.screenID))
        if ids != shownFaultIDs { withAnimation(.easeOut(duration: 0.35)) { shownFaultIDs = ids } }
    }

    func faultCardPointer(_ over: Bool, screenID: UUID) {
        faultVisibility.setPointerOver(over, screenID: screenID, now: faultClock())
        refreshFaultVisibility()
    }

    func faultCardFocus(_ inside: Bool, screenID: UUID) {
        faultVisibility.setFocusInside(inside, screenID: screenID, now: faultClock())
        refreshFaultVisibility()
    }

    /// A click on a role's pill: the card of its faulted screens shows again, with Retry and Details.
    func showFaultCards(for role: ScreenRole) {
        let now = faultClock()
        for readout in readouts where readout.role == role { faultVisibility.showAgain(screenID: readout.id, now: now) }
        refreshFaultVisibility()
    }

    /// Reopens the failed output once: the card's own output only (FIX-H item 4: a faulted mirror's Retry never restarts the healthy screen).
    /// A failure is said plainly on its card.
    func retryOutput(_ card: OutputFaultCard) {
        startVideoIfNeeded()
        let outcome = OutputFaultCards.retry(card, on: coordinator)
        screensOn = coordinator.isActive
        updateReadouts()
        switch outcome {
        case .reopened: retryNotes[card.screenID] = nil
        case .stillFailing(let text):
            retryNotes[card.screenID] = text
            faultVisibility.showAgain(screenID: card.screenID, now: faultClock())      // the answer to Retry is on the card: let it be read
            refreshFaultVisibility()
        }
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
    /// UI-005b: the AUD, STG and BRD pills of a prop.
    func setProp(_ id: UUID, target: ScreenRole, isOn: Bool) { settings?.setProp(id, target: target, isOn: isOn) }
    @discardableResult
    func addTextProp(name: String, spec: TextPropSpec, targets: Set<ScreenRole>) -> Prop? { settings?.addTextProp(name: name, spec: spec, targets: targets) }
    func updateTextProp(_ id: UUID, name: String, spec: TextPropSpec) { settings?.updateTextProp(id, name: name, spec: spec) }
    func togglePropTarget(_ id: UUID, role: ScreenRole) { settings?.togglePropTarget(id, role: role) }
    func saveTextProp(_ id: UUID, name: String, spec: TextPropSpec, targets: Set<ScreenRole>) -> Bool {
        settings?.saveTextProp(id, name: name, spec: spec, targets: targets) ?? false
    }

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
        syncMediaPlayers()
        appearanceRevision &+= 1          // thumbnails draw the background
        updateMediaTicker(layers)
        publish()
    }

    /// Opens the players for what is chosen to be on the live screens now, closes the rest and hands the registry the layers.
    private func syncMediaPlayers() {
        let layers = effectiveMedia()
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
        closing.forEach { $0.stop() }          // the players that used these files are closed now
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

    /// FIX-M: the file drops being handled, so the next one starts after the last one ended (order is kept).
    @ObservationIgnored private var mediaAddTail: Task<Void, Never>?

    /// Adds files chosen in the panel or dropped on the bin. Each gets a bookmark so access survives a relaunch.
    func addMedia(_ urls: [URL]) {
        guard let media else { return }
        // FIX-M: bookmarks are made off the main thread, and several drops are handled one after the other in the order they arrived.
        let previous = mediaAddTail
        mediaAddTail = Task { @MainActor in
            await previous?.value
            let bookmarks = await Task.detached(priority: .userInitiated) { MediaAccess.bookmarks(for: urls) }.value
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
    // CUE-002b: with the cue wiring every one of them goes through its one serial command path, whatever the source.
    func goLive(from source: CommandSource = .button) {
        if let cue { cue.submit(.goLive, from: source) } else if let w = workspace { Task { await w.goLive() } } else { send(.trigger(index: show.selectedIndex)) }
    }
    func triggerSlide(_ index: Int) {
        if let cue { cue.submit(.triggerSlide(index), from: .button) } else { workspace?.goLive(at: index) }
    }
    func next(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.next), from: source) } else if let w = workspace { Task { await w.next() } } else { send(.next) }
    }
    func previous(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.previous), from: source) } else if let w = workspace { Task { await w.previous() } } else { send(.previous) }
    }
    func clear(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.clear), from: source) } else if let w = workspace { w.clear() } else { send(.clear) }
    }
    /// R8: Clear plus stopping the clip that plays over the slide.
    func clearAll(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.clearAll), from: source) } else if let w = workspace { w.clearAll() } else { send(.clearAll) }
    }
    // MARK: The keyboard's section (FIX-I item 2)

    /// The section the arrows act on. In the Media mode the bin is all there is; in Show a folded bin cannot hold the arrows.
    var effectiveKeySection: KeySection {
        if workspace?.mode == .media { return .mediaBin }
        if workspace?.mode == .show, ui.keySection == .mediaBin, mediaDock.isCollapsed { return .slideGrid }
        return ui.keySection
    }

    /// The bin's items as they are drawn now, in order: the dock's tab in Show, the bin or the chosen hot folder in the Media mode.
    var visibleBinAssets: [MediaAsset] {
        guard let media else { return [] }
        if workspace?.mode == .media {
            guard let folder = ui.binFolderID.flatMap({ hotFolders?.state(of: $0) }) else { return media.visibleAssets }
            guard let kind = media.kindFilter else { return folder.items }
            return folder.items.filter { $0.kind == kind }
        }
        return MediaDock.assets(media.assets, tab: ui.dockTab)
    }

    /// An arrow key: a step of the selection in the keyboard's section. Preview only; nothing on any screen changes.
    func moveSelection(_ move: SelectionMove) {
        switch effectiveKeySection {
        case .slideGrid:
            guard let workspace else { return }
            let columns = ui.gridAsList ? 1 : ui.gridColumns
            Task { await workspace.moveSelection(move, columns: columns) }
        case .mediaBin:
            let items = visibleBinAssets
            let columns = workspace?.mode == .media ? ui.binColumns : max(1, items.count)       // the dock is one row
            let current = ui.binSelection.flatMap { id in items.firstIndex { $0.id == id } }
            guard let target = BinNavigation.target(count: items.count, current: current, move: move, columns: columns) else { return }
            selectBinItem(items[target].id)
        }
    }

    /// Return with the bin as the keyboard's section: the selected item goes live on the layer the bin's switch says, as a double click does.
    func sendBinSelectionLive() {
        guard let id = ui.binSelection, let asset = media?.asset(id) else { return }
        performDockAction(MediaDock.action(for: asset, layer: ui.dockLayer))
    }

    // MARK: The bin's selection and its player (MEDIA-010)

    /// A single click in the bin: select the item and show it in the sidebar player. Nothing goes live.
    func selectBinItem(_ id: UUID?) {
        ui.binSelection = id
        binPreview?.select(id.flatMap { media?.asset($0) })
    }

    /// Leaving the Media mode (or removing the item) puts the preview away.
    func releaseBinPreview() { binPreview?.select(nil); ui.binSelection = nil }

    // MARK: A slide's own background (MEDIA-010)

    /// A tile from the media bin dropped on a slide thumbnail: that slide's own background. An edit to the presentation.
    func setSlideBackground(mediaID: UUID, slideID: UUID) -> Bool {
        guard let asset = media?.asset(mediaID), let selection = SlideBackgroundDrop.selection(for: asset) else {
            media?.report("A sound file cannot be a slide's background. Drop a picture or a video.")
            return false
        }
        return slideEditor?.setBackground(selection, forSlide: slideID) ?? false
    }

    /// A file from Finder dropped on a slide thumbnail: it joins the media bin, then becomes that slide's background.
    func setSlideBackground(fileURLs: [URL], slideID: UUID) -> Bool {
        guard let url = fileURLs.first(where: \.isFileURL), let media else { return false }
        // FIX-M: the drop returns at once; the bookmark, the probe and the library write happen off the main thread, in drop order.
        let previous = mediaAddTail
        mediaAddTail = Task { @MainActor in
            await previous?.value
            let bookmark = await Task.detached(priority: .userInitiated) { MediaAccess.bookmarks(for: [url])[url] }.value
            guard let asset = await media.add(url: url, bookmark: bookmark) else { return }
            _ = setSlideBackground(mediaID: asset.id, slideID: slideID)
        }
        return true
    }

    /// "Use the presentation's background".
    func clearSlideBackground(slideID: UUID) { _ = slideEditor?.setBackground(nil, forSlide: slideID) }

    /// FIX-I item 6: "Set background…" and "Clear this slide's background" from the thumbnail's context menu: one undo step, Preview only.
    func setSlideBackgroundFromMenu(_ selection: MediaSelection?, slideID: UUID) { _ = slideEditor?.setBackgroundFromMenu(selection, forSlide: slideID) }

    // MARK: Hot folders (MEDIA-010)

    /// Points the media bin at a folder, chosen in the system open panel.
    func addHotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for the media bin to follow. Its videos, pictures and sound appear in the bin."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.followFolder(url) }
        }
    }

    func followFolder(_ url: URL) {
        guard let hot = hotFolders else { return }
        Task { @MainActor in
            let started = url.startAccessingSecurityScopedResource()
            let bookmark = HotFolderAccess.bookmark(for: url)
            if started { url.stopAccessingSecurityScopedResource() }
            await hot.add(path: url.path, bookmark: bookmark)
        }
    }

    /// A folder that went missing: choose it again.
    func repointHotFolder(_ id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose the folder this source should follow now."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                Task { @MainActor in
                    let bookmark = HotFolderAccess.bookmark(for: url)
                    await self?.hotFolders?.relocate(id, to: url.path, bookmark: bookmark)
                }
            }
        }
    }

    /// Called twice a second by the app timer: folders with files still being copied are looked at again every two seconds,
    /// every folder every ten (so one that came back is found). Nothing runs while no folder is followed.
    private func hotFolderTick() {
        guard let hot = hotFolders, !hot.folders.isEmpty else { return }
        hotTick &+= 1
        // FIX-G: requests, not waits: a folder that is still being scanned is asked for one more scan, never for a pile of them.
        if hotTick % 20 == 0 { hot.requestRescan() }
        else if hotTick % 4 == 0, hot.pendingCount > 0 { hot.requestRescan() }
    }

    /// MEDIA-010: the three layer clears, through the same serial command path as every other transport command.
    func clearBackground(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.clearBackground), from: source) } else { workspace?.clearBackground(); media?.dropBackgroundOverride() }
    }
    func clearForeground(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.clearForeground), from: source) } else { media?.stopForeground() }
    }
    func clearMusic(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.clearMusic), from: source) } else { audio?.stopAll() }
    }
    /// Command-E (UI-003): the Quick edit tab, for the SELECTED slide, in preview. Never touches what is on screen.
    func openQuickEdit() {
        guard let w = workspace, !w.slides.isEmpty else { return }
        w.setMode(.show)                      // the tab lives in the Show inspector
        if ui.tabs.openQuickEdit(hasSelectedSlide: true) { ui.focusQuickEdit += 1 }
    }

    /// Done (Escape) in the Quick edit tab: the tab goes, keyboard focus returns to the slide grid.
    func closeQuickEdit() {
        ui.tabs.closeQuickEdit()
        ui.focusGrid += 1
    }

    /// Option-Command-E: the popover that deliberately changes the LIVE slide. It lives on the Live monitor in Show.
    func requestLiveQuickEdit() {
        guard workspace?.showParts.liveSlide != nil else { return }
        ui.liveQuickEditRequests += 1
        workspace?.setMode(.show)
        ui.showLiveQuickEdit = true
    }

    /// UI-001: Blackout (the B key, the transport bar).
    func blackout(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.blackout(.toggle)), from: source) } else if let w = workspace { w.blackout() } else { send(.blackout) }
    }
    func stopShow(from source: CommandSource = .button) {
        if let cue { cue.submit(.transport(.stop), from: source) } else if let w = workspace { w.stop() } else { send(.stop) }
    }

    #if DEBUG || WF_MEASURE
    /// FIX-K (debug builds only): how many times the screens were republished, for the drag measurements.
    var debugPublishCount = 0
    #endif

    private func publish() {
        #if DEBUG || WF_MEASURE
        debugPublishCount += 1
        #endif
        sceneRevision &+= 1
        liveRevision &+= 1
        let snapshot = PhaseProbe.time("publish: compose") { makeSnapshot() }
        PhaseProbe.time("publish: box") { sceneBox.publish(snapshot) }
        PhaseProbe.markPublished()
        PhaseProbe.time("publish: ticker") { updateStageTicker() }
    }

    /// One immutable snapshot: every screen's scene for the state, Look, themes, props and stage layouts right now.
    private func makeSnapshot() -> PublishedScenes {
        let stageIDs = profiles.filter { $0.role == .stage }.map(\.id)
        let stageScenes = stage?.stageScenes(forScreens: stageIDs, state: show, notes: workspace?.liveNotes) ?? [:]
        return PublishedScenes(state: show, clockText: clockText, profiles: profiles, themes: themes,
                               look: currentLook, props: props, presentationThemeID: workspace?.shownThemeID,
                               stageScenes: stageScenes, media: media?.layers)
    }

    /// MEDIA-010: what the media registry plays: a live override from the bin, else the live slide's own background, and the
    /// clip over the words. The slide's own background keeps one start time while it stays the same, so a publish never
    /// restarts its video.
    private func effectiveMedia() -> MediaLayers {
        let override = media?.layers ?? MediaLayers()
        let own = show.liveSlideAtPlace?.background
        if override.background != nil || own == nil { ownBackgroundStart = nil; return LiveMedia.playing(override: override, state: show, at: MediaClock.now()) }
        if ownBackgroundStart?.selection != own { ownBackgroundStart = (own!, MediaClock.now()) }
        // FIX-G item 1: a cleared or stopped background is not played (so not heard either).
        return LiveMedia.playing(override: override, state: show, at: ownBackgroundStart!.at)
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
        cueTimer?.invalidate()
        cueTimer = nil
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }     // FIX-E
        wakeObserver = nil
        cue?.shutdown()
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

    // MARK: Show revision 2 (UI-003)

    var mediaDock: MediaDockState { settings?.mediaDock ?? MediaDockState() }
    func setMediaDock(height: Double) { settings?.setMediaDock(height: height) }
    func setMediaDock(collapsed: Bool) { settings?.setMediaDock(collapsed: collapsed) }

    /// Per enabled screen: which layers its Look shows and whether its theme draws a motion background. What the props
    /// chips and the media controller's screen chips are drawn from, so they only say what is true.
    var layerInputs: [ScreenLayerInput] {
        profiles.map { profile in
            let screenLook = currentLook?.screenLook(for: profile.id, in: profiles) ?? .standard
            let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID,
                                            presentationThemeID: workspace?.shownThemeID, themes: themes)
            var isMedia = false
            if case .media = theme.background { isMedia = true }
            return ScreenLayerInput(role: profile.role, isEnabled: profile.isEnabled, visibleLayers: screenLook.visibleLayers,
                                    backgroundIsMedia: isMedia)
        }
    }

    /// FIX-N item 4: the kind of the theme background (a video or a picture) of the first enabled audience or broadcast screen whose Look shows the
    /// background layer, nil when no such screen has one. What the background clear icon says it would clear when nothing else is named.
    var themeBackgroundKindOnScreen: MediaKind? {
        for profile in profiles where profile.isEnabled && profile.role != .stage {
            let screenLook = currentLook?.screenLook(for: profile.id, in: profiles) ?? .standard
            guard screenLook.visibleLayers.contains(.background) else { continue }
            let theme = ThemeResolver.theme(for: profile.role, lookThemeID: screenLook.themeID, presentationThemeID: workspace?.shownThemeID, themes: themes)
            if let kind = ClearIconRule.themeBackgroundKind(theme.background) { return kind }
        }
        return nil
    }

    /// What a click on a media tile does (UI-003). Sound plays as a cue; a picture or video follows the layer choice.
    func performDockAction(_ action: MediaDockAction) {
        switch action {
        case .setBackground(let id): media?.setBackground(id); binPreview?.itemSentLive(id)
        case .playForeground(let id): media?.playForeground(id); binPreview?.itemSentLive(id)
        case .playAudio(let id): audio?.play(id); binPreview?.itemSentLive(id)
        }
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
            displayName: { names[$0] ?? "Display \($0) (not connected)" }, hostName: Self.signalMapHostName()))
    }

    /// The Mac's own name for the signal map. A debug run that writes pictures (the repository is public) shows a neutral name (KI-085).
    private static func signalMapHostName() -> String {
        #if DEBUG || WF_MEASURE
        if snapshotDirectory != nil { return "This Mac" }
        #endif
        return Host.current().localizedName ?? "This Mac"
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
        if r != readouts {
            readouts = r
            // FIX-H item 4: a "did not reopen" note goes with its card (the output came back, was disabled or removed).
            let kept = OutputFaultCards.notes(retryNotes, keepingCardsOf: OutputFaultCards.cards(from: r))
            if kept != retryNotes { retryNotes = kept }
        }
        refreshFaultVisibility()
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
        FileHandle.standardError.write(Data("[WorshipFlow] \(message)\n".utf8))
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
        lines.append("WorshipFlow OUT-002 soak report")
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
