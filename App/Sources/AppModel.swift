// OUT-001: operator state and output lifecycle. All outputs render off the main thread; this model only
// starts and stops them and reads their statistics.
import AppKit
import Observation
import Domain
import MediaEngine
import OutputEngine

enum LiveMode: Equatable { case stopped, live, cleared }

struct OutputReadout: Identifiable, Equatable {
    var id: String { name }
    var name: String
    var status: String
    var presented: Int
    var dropped: Int
    var late: Int
    var maxIntervalMs: Double
    var refreshHz: Double
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let slides = SampleSlides.all
    var selectedIndex = 0
    private(set) var mode: LiveMode = .stopped
    private(set) var screens: [NSScreen] = NSScreen.screens
    var selectedScreenIndex = 0
    var showSecondWindow = false {
        didSet { if oldValue != showSecondWindow { syncSecondWindow() } }
    }
    private(set) var videoURL: URL?
    private(set) var readouts: [OutputReadout] = []
    private(set) var messages: [String] = []

    @ObservationIgnored private let box = LiveBox()
    @ObservationIgnored private var video: LoopingVideoSource?
    @ObservationIgnored private var audienceOutput: (any OutputTarget)?
    @ObservationIgnored private var stageOutput: (any OutputTarget)?
    @ObservationIgnored private var readoutTimer: Timer?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var soakTask: Task<Void, Never>?
    @ObservationIgnored private(set) var soak: SoakConfig?

    private init() {
        selectedScreenIndex = defaultScreenIndex()
    }

    // MARK: Setup

    func installSystemHooks() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let handled: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                switch event.keyCode {
                case 124, 49: self.next(); return true      // right arrow, space
                case 123: self.previous(); return true     // left arrow
                case 53: self.clear(); return true          // escape
                default: return false
                }
            }
            return handled ? nil : event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshScreens() }
        }
        readoutTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateReadouts() }
        }
    }

    private func defaultScreenIndex() -> Int {
        // Prefer a display that is not the one carrying the operator window.
        let all = NSScreen.screens
        if all.count > 1, let main = NSScreen.main, let idx = all.firstIndex(where: { $0 != main }) { return idx }
        return 0
    }

    func refreshScreens() {
        screens = NSScreen.screens
        if selectedScreenIndex >= screens.count { selectedScreenIndex = defaultScreenIndex() }
    }

    var screenNames: [String] {
        screens.enumerated().map { i, s in
            let f = s.frame
            return "\(i): \(s.localizedName) (\(Int(f.width))x\(Int(f.height)) @ \(s.maximumFramesPerSecond) Hz)"
        }
    }

    var chosenScreenIsOperatorScreen: Bool {
        guard screens.indices.contains(selectedScreenIndex) else { return false }
        return screens[selectedScreenIndex] == NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain })?.screen
    }

    // MARK: Video

    func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a background video to loop"
        if panel.runModal() == .OK, let url = panel.url { setVideo(url) }
    }

    func setVideo(_ url: URL?) {
        video?.stop()
        video = nil
        videoURL = nil
        guard let url else { return }
        do {
            let source = try LoopingVideoSource(url: url)
            video = source
            videoURL = url
            if mode != .stopped { source.start() }
            // Running outputs captured the previous source; restart them so they pick up the new one.
            if mode != .stopped { restartOutputs() }
        } catch {
            log("Could not open video: \(error)")
        }
    }

    // MARK: Live control

    func goLive() {
        guard mode == .stopped else { return }
        publish(cleared: false)
        video?.start()
        mode = .live
        startOutputs(displayScreen: screens.indices.contains(selectedScreenIndex) ? screens[selectedScreenIndex] : nil)
    }

    func stopLive() {
        audienceOutput?.stop(); audienceOutput = nil
        stageOutput?.stop(); stageOutput = nil
        video?.stop()
        mode = .stopped
        updateReadouts()
    }

    func clear() {
        guard mode != .stopped else { return }
        mode = .cleared
        box.update { $0.cleared = true }
    }

    func next() { move(to: selectedIndex + 1) }
    func previous() { move(to: selectedIndex - 1) }

    func select(_ index: Int) { move(to: index) }

    private func move(to index: Int) {
        guard slides.indices.contains(index) else { return }
        selectedIndex = index
        if mode != .stopped { mode = .live; publish(cleared: false) }
    }

    private func publish(cleared: Bool) {
        let current = slides[selectedIndex]
        let next = slides.indices.contains(selectedIndex + 1) ? slides[selectedIndex + 1] : nil
        box.update { $0.current = current; $0.next = next; $0.cleared = cleared }
    }

    // MARK: Outputs

    private func startOutputs(displayScreen: NSScreen?, forceWindow: Bool = false) {
        let box = self.box
        let source: (any VideoSourceFactory)? = video
        let audienceScene: SceneProvider = { SceneBuilder.audience(box.read()) }

        let useDisplay = !forceWindow && displayScreen != nil && (screens.count > 1 || soak != nil)
        let audience: any OutputTarget
        if useDisplay, let screen = displayScreen {
            audience = DisplayOutput(screen: screen, name: "Audience display", sceneProvider: audienceScene, videoSource: source)
        } else {
            if !forceWindow { log("Single display (or none chosen): audience output runs in a window.") }
            audience = WindowOutput(name: "Audience window", sceneProvider: audienceScene, videoSource: source)
        }
        attach(audience)
        audienceOutput = audience
        syncSecondWindow()
    }

    private func restartOutputs() {
        let screen = screens.indices.contains(selectedScreenIndex) ? screens[selectedScreenIndex] : nil
        let wasCleared = mode == .cleared
        audienceOutput?.stop(); audienceOutput = nil
        stageOutput?.stop(); stageOutput = nil
        video?.start()
        startOutputs(displayScreen: screen)
        if wasCleared { box.update { $0.cleared = true } }
    }

    private func syncSecondWindow() {
        guard mode != .stopped else { return }
        if showSecondWindow, stageOutput == nil {
            let box = self.box
            let stage = WindowOutput(name: "Stage window", sceneProvider: { SceneBuilder.stage(box.read()) })
            attach(stage)
            stageOutput = stage
        } else if !showSecondWindow, let stage = stageOutput {
            stage.stop()
            stageOutput = nil
        }
    }

    private func attach(_ output: any OutputTarget) {
        output.onStatusChange = { [weak self, weak output] status in
            guard let self, let output else { return }
            guard case .stopped(let reason) = status else { return }
            if let reason { self.log("\(output.name): \(reason)") }
            self.outputStopped(output)
        }
        do {
            try output.start()
        } catch {
            log("\(output.name) failed to start: \(error)")
        }
    }

    private func outputStopped(_ output: any OutputTarget) {
        if let a = audienceOutput, a === output { audienceOutput = nil }
        if let s = stageOutput, s === output {
            stageOutput = nil
            if showSecondWindow { showSecondWindow = false }
        }
        if audienceOutput == nil && stageOutput == nil && mode != .stopped {
            video?.stop()
            mode = .stopped
        }
        updateReadouts()
    }

    private func log(_ message: String) {
        messages.append(message)
        if messages.count > 6 { messages.removeFirst() }
        FileHandle.standardError.write(Data("[WORSHIPFLOW] \(message)\n".utf8))
    }

    private func readout(_ o: any OutputTarget) -> OutputReadout {
        let s = o.statistics
        let status: String
        switch o.status {
        case .idle: status = "idle"
        case .running: status = "running"
        case .stopped(let r): status = r == nil ? "stopped" : "stopped: \(r ?? "")"
        }
        return OutputReadout(name: o.name, status: status, presented: s.presentedFrames, dropped: s.droppedFrames,
                             late: s.lateFrames, maxIntervalMs: s.maxInterval * 1000, refreshHz: o.refreshRate)
    }

    func updateReadouts() {
        var r: [OutputReadout] = []
        if let a = audienceOutput { r.append(readout(a)) }
        if let s = stageOutput { r.append(readout(s)) }
        if r != readouts { readouts = r }
    }

    // MARK: Soak

    func startSoakIfRequested() {
        guard soak == nil, let config = SoakConfig.parse(CommandLine.arguments) else { return }
        soak = config
        if let path = config.videoPath { setVideo(URL(fileURLWithPath: path)) }
        refreshScreens()
        selectedIndex = 0
        var screen: NSScreen?
        if let i = config.screenIndex {
            guard screens.indices.contains(i) else {
                FileHandle.standardError.write(Data("--screen \(i) is out of range (\(screens.count) screens)\n".utf8))
                exit(2)
            }
            screen = screens[i]
        }
        publish(cleared: false)
        video?.start()
        mode = .live
        let started = Date()
        startOutputs(displayScreen: screen, forceWindow: screen == nil)
        soakTask = Task { @MainActor [weak self] in await self?.runSoak(config, screen: screen, started: started) }
    }

    private func runSoak(_ config: SoakConfig, screen: NSScreen?, started: Date) async {
        var memory: [UInt64] = []
        if let m = MemoryProbe.residentBytes() { memory.append(m) }
        var lastSlideAt = 0.0, lastSampleAt = 0.0
        var advances = 0
        var failure: String?
        let refreshAtStart = (audienceOutput?.refreshRate ?? 0)
        while true {
            try? await Task.sleep(for: .milliseconds(250))
            let t = Date().timeIntervalSince(started)
            if audienceOutput == nil { failure = "audience output stopped before the soak finished"; break }
            if t - lastSlideAt >= 5 {
                lastSlideAt = t
                advances += 1
                move(to: (selectedIndex + 1) % slides.count)
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
        let finals = [audienceOutput, stageOutput].compactMap { $0 }.map { readout($0) }
        let errors = [audienceOutput, stageOutput].compactMap { $0?.lastRenderError }
        let videoFrames = video?.deliveredFrameCount ?? 0
        let videoDiag = video?.diagnostics ?? "none"
        let diag = [audienceOutput, stageOutput].compactMap { $0 }.map { "\($0.name): \($0.diagnostics)" }
        stopLive()

        let modeText: String
        if let screen {
            let id = DisplayOutput.displayID(of: screen)
            if let dm = CGDisplayCopyDisplayMode(id) {
                modeText = "display output, \(screen.localizedName), \(dm.pixelWidth)x\(dm.pixelHeight) @ \(String(format: "%.2f", dm.refreshRate)) Hz (NSScreen max \(screen.maximumFramesPerSecond) Hz)"
            } else {
                modeText = "display output, \(screen.localizedName)"
            }
        } else {
            modeText = "window output, \(String(format: "%.0f", refreshAtStart)) Hz display"
        }
        var lines: [String] = []
        lines.append("WORSHIPFLOW OUT-001 soak report")
        lines.append("duration: \(String(format: "%.1f", duration)) s (requested \(config.seconds) s)")
        lines.append("display mode: \(modeText)")
        lines.append("slide advances: \(advances)")
        lines.append("video: \(config.videoPath ?? "none"), distinct frames delivered: \(videoFrames)")
        if let f = finals.first {
            lines.append("presented: \(f.presented)")
            lines.append("dropped: \(f.dropped)")
            lines.append("late: \(f.late)")
            lines.append(String(format: "max interval: %.2f ms (target %.2f ms)", f.maxIntervalMs, f.refreshHz > 0 ? 1000 / f.refreshHz : 0))
        } else {
            lines.append("presented: 0\ndropped: 0\nlate: 0\nmax interval: 0 ms")
        }
        for f in finals.dropFirst() {
            lines.append("\(f.name): presented \(f.presented), dropped \(f.dropped), late \(f.late), max interval \(String(format: "%.2f", f.maxIntervalMs)) ms")
        }
        if let lo = memory.min(), let hi = memory.max() {
            lines.append("memory resident min: \(String(format: "%.1f", Double(lo) / 1_048_576)) MB, max: \(String(format: "%.1f", Double(hi) / 1_048_576)) MB (\(memory.count) samples)")
        } else {
            lines.append("memory: unavailable")
        }
        lines.append("video player: \(videoDiag)")
        lines.append("diagnostics: \(diag.isEmpty ? "none" : diag.joined(separator: "; "))")
        lines.append("render errors: \(errors.isEmpty ? "none" : errors.joined(separator: "; "))")
        if failure == nil, (finals.first?.presented ?? 0) == 0 {
            failure = "no frames were presented (the output window may be occluded, for example behind a full-screen app on that display)"
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
        exit(failure == nil ? 0 : 1)
    }

    private func defaultReportPath() -> String {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.currentDirectoryPath + "/AI/reports"
        return dir + "/soak-\(stamp).log"
    }
}
