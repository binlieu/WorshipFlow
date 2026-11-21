// OUT-002: operator state. The show lives in `ShowState`, scenes come from `SceneComposer`, and outputs are run
// by `OutputCoordinator`. This model sends commands and reads status; it never renders. Render threads read an
// immutable `PublishedScenes` snapshot, never this object.
import AppKit
import Observation
import Domain
import MediaEngine
import OutputEngine
import Persistence
import OperatorCore

enum LiveMode: Equatable { case stopped, live, cleared }

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

    private(set) var show = ShowState()
    private(set) var readouts: [ScreenReadout] = []
    private(set) var displayChoices: [DisplayChoice] = []
    private(set) var screensOn = false
    private(set) var videoURL: URL?
    private(set) var messages: [String] = []
    /// Screen profiles, Looks, props and custom themes, stored in the library (APP-001). Nil in a soak run, or when
    /// the library file could not be opened.
    private(set) var settings: SettingsModel?
    /// The one screen a soak run drives; a soak never reads or writes settings.
    @ObservationIgnored private var soakProfiles: [ScreenProfile] = []
    /// Image files that are missing or unreadable: from the files checked here and from what the outputs reported.
    private(set) var unavailableImages: [String] = []
    /// The operator workspace (OUT-004). Nil in a soak run, or when the library file could not be opened.
    private(set) var workspace: WorkspaceModel?
    private(set) var workspaceLoaded = false
    /// Set when the library file could not be opened: the path and a message. The file is left untouched.
    private(set) var libraryProblem: LibraryProblem?
    /// Bumped on every publish, so previews know to re-read their scene.
    private(set) var sceneRevision = 0
    /// Sheets and focus requests shared by the menus and the views.
    let ui = WorkspaceUIState()

    @ObservationIgnored private let sceneBox: SceneBox
    @ObservationIgnored private var scopedURLs: [UUID: URL] = [:]   // security-scoped access held while the prop exists
    @ObservationIgnored private lazy var coordinator: OutputCoordinator = makeCoordinator()
    @ObservationIgnored private var video: LoopingVideoSource?
    @ObservationIgnored private var clockText = ""
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var soakTask: Task<Void, Never>?
    @ObservationIgnored private(set) var soak: SoakConfig?
    @ObservationIgnored private var soakProfileID: UUID?

    private init() {
        sceneBox = SceneBox(PublishedScenes(state: ShowState(), clockText: nil))
        soak = SoakConfig.parse(CommandLine.arguments)   // known first, so a soak never opens a library or writes settings
        refreshDisplayChoices()
        updateClock(force: true)
        if soak == nil { openLibrary() }
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
            workspace = model
            let settings = SettingsModel(store: store, legacy: LegacySettingsFiles(libraryURL: url), defaultProfiles: { [weak self] in
                ScreenProfile.defaults(displays: NSScreen.screens.map(DisplayOutput.displayID(of:)),
                                       operatorDisplay: self?.operatorDisplayID())
            })
            settings.onProfilesChange = { [weak self] in self?.profilesChanged() }
            settings.onAppearanceChange = { [weak self] in self?.lookChanged() }
            self.settings = settings
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
            await resolvePropBookmarks()
            coordinator.setProfiles(profiles)
            publish()
            updateReadouts()
            await workspace.load()
            workspaceLoaded = true
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

    /// Writes unsaved typing and the saved place. Called when the app loses focus and before it quits.
    func flushWorkspace() async { await workspace?.flush() }

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
                               presentationThemeID: workspace?.openThemeID)
            .scene(forScreen: profile.id)
    }

    /// The workspace changed the show: publish to every output and open the screens on the first slide.
    private func showChanged(_ state: ShowState) {
        let wasStopped = show.isStopped
        show = state
        publish()
        if wasStopped, !show.isStopped, !screensOn { startScreens() }
    }

    private func makeCoordinator() -> OutputCoordinator {
        let c = OutputCoordinator(
            displays: { [weak self] in self?.displaySnapshot() ?? DisplaySnapshot(available: [], operatorDisplay: nil) },
            makeTarget: { [weak self] profile, destination in
                guard let self else { throw OutputSetupError.modelGone }
                return try self.makeTarget(profile, destination)
            },
            sleepGuard: SleepGuard())
        c.onChange = { [weak self] in self?.updateReadouts() }
        return c
    }

    private enum OutputSetupError: Error, LocalizedError {
        case modelGone, displayGone
        var errorDescription: String? {
            switch self {
            case .modelGone: "The app is shutting down."
            case .displayGone: "The display is no longer connected."
            }
        }
    }

    // MARK: Derived state for the UI

    var slides: [SlideContent] { show.previewDeck?.slides ?? [] }
    var selectedIndex: Int { show.selectedIndex }
    var liveIndex: Int? { show.liveIndex }
    var mode: LiveMode { show.isStopped ? .stopped : (show.isCleared ? .cleared : .live) }

    // MARK: Setup

    func installSystemHooks() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only real windows (operator or output window), never menus or panels.
            guard let window = event.window, window.canBecomeMain else { return event }
            let responder = window.firstResponder
            let textInput = responder is NSText || responder is NSTextField
            let inSearch = textInput && Self.isInsideSearchField(responder)
            let held = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let key = KeyboardKey(keyCode: event.keyCode)
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                let sheetOpen = self.ui.anySheetOpen || window.attachedSheet != nil
                switch KeyRouting.decision(for: key, textInputFocused: textInput, searchFieldFocused: inSearch,
                                           sheetOpen: sheetOpen, commandModifierDown: held) {
                case .transport(let command):
                    switch command {
                    case .goLive: self.goLive()
                    case .next: self.next()
                    case .previous: self.previous()
                    case .clear: self.clear()
                    }
                    return true
                case .leaveSearch:
                    self.ui.leaveSearch += 1      // the workspace view clears the search and puts focus on the slide grid
                    return true
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
        let window = NSApplication.shared.windows.first { $0.title == Self.operatorWindowTitle && $0.isVisible }
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
        switch destination {
        case .window: return "Window"
        case .display(let id): return displayChoices.first { $0.id == id }?.name ?? "Display \(id) (not connected)"
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
    var settingsError: String? { settings?.lastError }
    func dismissSettingsError() { settings?.dismissError() }

    func updateProfile(_ profile: ScreenProfile) {
        if let settings {
            settings.updateProfile(profile)
        } else if let i = soakProfiles.firstIndex(where: { $0.id == profile.id }), soakProfiles[i] != profile {
            soakProfiles[i] = profile
            profilesChanged()
        }
    }

    private func profilesChanged() {
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

    /// Files the live scenes need that cannot be read now, plus what the outputs reported. Sorted, no duplicates.
    private func imageProblems(reported: [String]) -> [String] {
        var paths = Set(reported)
        var needed = Set(props.filter(\.isOn).map(\.imagePath))
        for theme in themes { if case .image(let path) = theme.background { needed.insert(path) } }
        for path in needed where !FileManager.default.isReadableFile(atPath: path) { paths.insert(path) }
        return paths.sorted()
    }

    // MARK: Video

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background video to loop"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { self?.setVideo(url) }
        }
    }

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
    func stopShow() { if let w = workspace { w.stop() } else { send(.stop) } }

    private func publish() {
        sceneRevision &+= 1
        sceneBox.publish(PublishedScenes(state: show, clockText: clockText, profiles: profiles, themes: themes,
                                         look: currentLook, props: props, presentationThemeID: workspace?.liveThemeID))
    }

    private func updateClock(force: Bool) {
        let text = Date.now.formatted(date: .omitted, time: .shortened)
        guard force || text != clockText else { return }
        clockText = text
        publish()
    }

    // MARK: Screens

    func startScreens() {
        startVideoIfNeeded()
        coordinator.start()
        screensOn = true
        updateReadouts()
    }

    func stopScreens() {
        coordinator.stop()
        video?.stop()
        screensOn = false
        updateReadouts()
    }

    func shutdown() { stopScreens() }

    private func makeTarget(_ profile: ScreenProfile, _ destination: OutputDestination) throws -> any OutputTarget {
        let box = sceneBox
        let role = profile.role
        let screenID = profile.id
        let provider: SceneProvider = { box.read().scene(forScreen: screenID) }
        let source: (any VideoSourceFactory)? = role != .stage ? video : nil
        switch destination {
        case .display(let id):
            guard let screen = NSScreen.screens.first(where: { DisplayOutput.displayID(of: $0) == id }) else {
                throw OutputSetupError.displayGone
            }
            return DisplayOutput(screen: screen, name: profile.name, sceneProvider: provider, videoSource: source)
        case .window:
            let index = profiles.filter { $0.destination == .window }.firstIndex { $0.id == profile.id } ?? 0
            return WindowOutput(name: profile.name, sceneProvider: provider, videoSource: source, cascadeIndex: index)
        }
    }

    func updateReadouts() {
        let r = coordinator.readouts()
        if r != readouts { readouts = r }
        let problems = imageProblems(reported: r.flatMap(\.unavailableImagePaths))
        if problems != unavailableImages { unavailableImages = problems }
        if screensOn != coordinator.isActive { screensOn = coordinator.isActive }
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
