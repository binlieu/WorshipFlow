// OUT-002: operator state. The show lives in `ShowState`, scenes come from `SceneComposer`, and outputs are run
// by `OutputCoordinator`. This model sends commands and reads status; it never renders. Render threads read an
// immutable `PublishedScenes` snapshot, never this object.
import AppKit
import Observation
import Domain
import MediaEngine
import OutputEngine

enum LiveMode: Equatable { case stopped, live, cleared }

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
    private(set) var profiles: [ScreenProfile] = []
    private(set) var readouts: [ScreenReadout] = []
    private(set) var displayChoices: [DisplayChoice] = []
    private(set) var screensOn = false
    private(set) var videoURL: URL?
    private(set) var messages: [String] = []
    /// Themes the operator can choose per screen. Only the built-in ones until a theme editor exists.
    let themes: [Theme] = Theme.builtIn
    private(set) var looks: [Look] = [Look(id: UUID(), name: "Standard")]
    private(set) var selectedLookID = UUID()
    private(set) var props: [Prop] = []
    /// Image files that are missing or unreadable: from the files checked here and from what the outputs reported.
    private(set) var unavailableImages: [String] = []

    @ObservationIgnored private let sceneBox: SceneBox
    @ObservationIgnored private let store = ScreenProfileStore.standard
    @ObservationIgnored private let lookStore = LookStore.standard
    @ObservationIgnored private var propBookmarks: [UUID: Data] = [:]
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
        var state = ShowState()
        state.apply(.load(SampleSlides.deck))
        show = state
        sceneBox = SceneBox(PublishedScenes(state: state, clockText: nil))
        selectedLookID = looks[0].id
        soak = SoakConfig.parse(CommandLine.arguments)   // known before profiles load, so a soak never writes settings
        refreshDisplayChoices()
        loadProfiles()
        loadLooks()
        updateClock(force: true)
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
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            // Only real windows (operator or output window), never menus, panels or sheets; never while typing.
            guard let window = event.window, window.canBecomeMain, !(window.firstResponder is NSText) else { return event }
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                switch event.keyCode {
                case 36, 76: self.goLive(); return true     // return, keypad enter
                case 124, 49: self.next(); return true      // right arrow, space
                case 123: self.previous(); return true      // left arrow
                case 53: self.clear(); return true          // escape
                default: return false
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

    // MARK: Profiles

    private func loadProfiles() {
        switch store.load() {
        case .loaded(let loaded):
            profiles = loaded
        case .missing:
            profiles = ScreenProfile.defaults(displays: NSScreen.screens.map(DisplayOutput.displayID(of:)),
                                              operatorDisplay: operatorDisplayID())
            persistProfiles()
        case .unreadable(let why):
            log("Screen settings could not be read, using defaults. The file is left as it is until you change a screen. (\(why))")
            profiles = ScreenProfile.defaults(displays: NSScreen.screens.map(DisplayOutput.displayID(of:)),
                                              operatorDisplay: operatorDisplayID())
        }
        coordinator.setProfiles(profiles)
    }

    private func persistProfiles() {
        guard soak == nil else { return }
        do { try store.save(profiles) } catch { log("Screen settings could not be saved: \(error.localizedDescription)") }
    }

    func updateProfile(_ profile: ScreenProfile) {
        guard let i = profiles.firstIndex(where: { $0.id == profile.id }), profiles[i] != profile else { return }
        profiles[i] = profile
        persistProfiles()
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

    // MARK: Looks and props (OUT-003)

    var currentLook: Look? { looks.first { $0.id == selectedLookID } }

    func screenLook(for screenID: UUID) -> ScreenLook { currentLook?.screenLook(for: screenID) ?? .standard }

    func selectLook(_ id: UUID) {
        guard id != selectedLookID, looks.contains(where: { $0.id == id }) else { return }
        selectedLookID = id
        lookChanged()
    }

    /// Creates a Look that starts as a copy of the current one and selects it.
    func addLook() {
        var look = currentLook ?? Look(id: UUID(), name: "Look")
        look.id = UUID()
        look.name = "Look \(looks.count + 1)"
        looks.append(look)
        selectedLookID = look.id
        lookChanged()
    }

    func renameLook(_ id: UUID, to name: String) {
        guard let i = looks.firstIndex(where: { $0.id == id }), looks[i].name != name else { return }
        looks[i].name = name
        persistLooks()
    }

    /// The last Look cannot be deleted: a screen always has one.
    func deleteLook(_ id: UUID) {
        guard looks.count > 1, let i = looks.firstIndex(where: { $0.id == id }) else { return }
        looks.remove(at: i)
        if selectedLookID == id { selectedLookID = looks[min(i, looks.count - 1)].id }
        lookChanged()
    }

    func setTheme(_ themeID: UUID?, forScreen screenID: UUID) {
        editScreenLook(screenID) { $0.themeID = themeID }
    }

    func setLayer(_ layer: LayerKind, visible: Bool, forScreen screenID: UUID) {
        editScreenLook(screenID) { if visible { $0.visibleLayers.insert(layer) } else { $0.visibleLayers.remove(layer) } }
    }

    private func editScreenLook(_ screenID: UUID, _ change: (inout ScreenLook) -> Void) {
        guard let i = looks.firstIndex(where: { $0.id == selectedLookID }) else { return }
        var screenLook = looks[i].screenLook(for: screenID)
        let before = screenLook
        change(&screenLook)
        guard screenLook != before else { return }
        looks[i].screens[screenID] = screenLook
        lookChanged()
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
        let id = UUID()
        _ = url.startAccessingSecurityScopedResource()   // an open-panel URL is already accessible; keep access for the prop's lifetime
        scopedURLs[id] = url
        do {
            propBookmarks[id] = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            log("Could not remember access to \(url.lastPathComponent) across launches: \(error.localizedDescription)")
        }
        props.append(Prop(id: id, name: url.deletingPathExtension().lastPathComponent, imagePath: url.path,
                          frame: NormalizedRect(x: 0.86, y: 0.04, width: 0.1, height: 0.1), opacity: 1, isOn: true))
        lookChanged()
    }

    func setProp(_ id: UUID, isOn: Bool) {
        guard let i = props.firstIndex(where: { $0.id == id }), props[i].isOn != isOn else { return }
        props[i].isOn = isOn
        lookChanged()
    }

    func removeProp(_ id: UUID) {
        guard let i = props.firstIndex(where: { $0.id == id }) else { return }
        props.remove(at: i)
        propBookmarks[id] = nil
        scopedURLs.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        lookChanged()
    }

    /// One publish and one save per operator change.
    private func lookChanged() {
        publish()
        persistLooks()
        updateReadouts()
    }

    private func persistLooks() {
        guard soak == nil else { return }
        let library = LookLibrary(looks: looks, selectedLookID: selectedLookID,
                                  props: props.map { StoredProp(prop: $0, bookmark: propBookmarks[$0.id]) })
        do { try lookStore.save(library) } catch { log("Looks could not be saved: \(error.localizedDescription)") }
    }

    private func loadLooks() {
        switch lookStore.load() {
        case .missing:
            break
        case .unreadable(let why):
            log("Looks could not be read, using defaults. The file is left as it is until you change a Look or prop. (\(why))")
        case .loaded(let library):
            if !library.looks.isEmpty {
                looks = library.looks
                selectedLookID = looks.contains { $0.id == library.selectedLookID } ? (library.selectedLookID ?? looks[0].id) : looks[0].id
            }
            props = library.props.map { stored in
                var prop = stored.prop
                if let data = stored.bookmark {
                    var stale = false
                    if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                        _ = url.startAccessingSecurityScopedResource()
                        scopedURLs[prop.id] = url
                        prop.imagePath = url.path   // follows the file if it was moved or renamed
                        propBookmarks[prop.id] = stale
                            ? ((try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)) ?? data)
                            : data
                    } else {
                        propBookmarks[prop.id] = data
                    }
                }
                return prop
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

    func goLive() { send(.trigger(index: show.selectedIndex)) }
    func next() { send(.next) }
    func previous() { send(.previous) }
    func clear() { send(.clear) }
    func stopShow() { send(.stop) }
    func select(_ index: Int) { send(.select(index: index)) }

    private func publish() {
        sceneBox.publish(PublishedScenes(state: show, clockText: clockText, profiles: profiles, themes: themes,
                                         look: currentLook, props: props))
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
        profiles = [audience]
        coordinator.setProfiles(profiles)
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
