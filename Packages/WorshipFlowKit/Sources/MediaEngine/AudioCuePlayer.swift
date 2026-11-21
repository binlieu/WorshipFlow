// MEDIA-005 / MEDIA-006: plays one audio file through its own AVAudioEngine to a chosen sound device, with a level
// meter. One player is one cue; the operator model makes one per cue so cues marked "overlap" can sound together.
//
// Threading: every method and callback is on the main actor. The only code that runs on an audio thread is the
// meter's tap, which touches nothing but a `LevelBox` (a lock around a few numbers); the main actor reads it from a
// 20 Hz timer. AVAudioPlayerNode completion callbacks arrive on an AVFoundation queue and hop to the main actor
// before they touch anything.
//
// Device: the engine's output unit is pointed at the device with `AUAudioUnit.setDeviceID(_:)` while the engine is
// stopped. If the device disappears the player falls back to the system default, says so once (`onDeviceLost`) and
// keeps playing from where it was; when the device returns it goes back to it. `Output.offline` renders the same
// graph with no device at all, for tests and for a silent run.
import Foundation
import AVFoundation
import AudioToolbox
import Domain

public enum AudioCueError: Error, LocalizedError, Equatable {
    case empty(String)
    case engineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .empty(let name): return "\"\(name)\" contains no sound."
        case .engineFailed(let why): return "The sound engine could not start: \(why)"
        }
    }
}

@MainActor
public final class AudioCuePlayer {
    public enum Output: Sendable {
        /// Plays through a real device.
        case hardware
        /// Renders with no device. Nothing is heard; the caller drives time with `renderOffline(seconds:)`, or lets
        /// the player's own timer do it (`pumpsOffline`).
        case offline(sampleRate: Double)
    }

    private enum State { case idle, playing, paused }

    // MARK: Callbacks (main actor)

    /// A clip that does not loop played to its end. Not called for `stop()`.
    public var onFinished: (@MainActor () -> Void)?
    /// About 20 times a second while something plays, and once with silence when it stops.
    public var onLevels: (@MainActor (AudioLevels) -> Void)?
    /// The chosen device is not there. Called once per loss, with the UID that was asked for.
    public var onDeviceLost: (@MainActor (String) -> Void)?
    /// Playback could not continue (for example the engine could not be restarted). The player is idle afterwards.
    public var onFailure: (@MainActor (String) -> Void)?

    // MARK: State

    public private(set) var duration: Double = 0
    public private(set) var loops = false
    /// The device in effect: the chosen one, or nil for the system default (also while the chosen one is missing).
    public private(set) var outputDeviceUID: String?
    public var isPlaying: Bool { state == .playing }
    public var isPaused: Bool { state == .paused }

    private var state: State = .idle
    private let catalog: any AudioDeviceCatalog
    private let output: Output
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let meter = LevelBox()
    private var file: AVAudioFile?
    private var fileName = ""
    private var generation = 0
    /// The frame the current scheduling started at (`node` time zero).
    private var startFrame: AVAudioFramePosition = 0
    private var heldFrame: AVAudioFramePosition = 0
    /// Frames queued on the node since its time zero (offline rendering tops the queue up itself).
    private var queuedFrames: AVAudioFramePosition = 0
    private var volume: Float = 1
    private var muted = false
    private var requestedUID: String?
    private var lossReported = false
    private var graphReady = false
    private var meterTimer: Timer?
    private var stopObserving: (@Sendable () -> Void)?
    private var configObserver: NSObjectProtocol?
    private var offlineBuffer: AVAudioPCMBuffer?
    private var pumpClock: Double = 0
    public var pumpsOffline = false

    public init(catalog: any AudioDeviceCatalog, output: Output = .hardware) {
        self.catalog = catalog
        self.output = output
        engine.attach(node)
        if case .offline(let rate) = output {
            let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            try? engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            offlineBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)
        }
        // The meter: a tap on the main mixer, after the cue's own volume. It runs on an audio queue and only fills `meter`.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block: Self.tapBlock(meter))
        stopObserving = catalog.observeChanges { [weak self] in
            Task { @MainActor in self?.deviceListChanged() }
        }
        if case .hardware = output {
            configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.engineConfigurationChanged() }
            }
        }
    }

    /// Stops playing and lets go of the device list listener. Call before dropping the player.
    public func shutdown() {
        stop()
        stopObserving?()
        stopObserving = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
    }

    // MARK: Transport

    /// Opens the file and plays it from `seconds`. Throws, leaving the player idle, when the file cannot be read or has
    /// no sound; the error's description says what is wrong.
    public func play(url: URL, from seconds: Double = 0, loops: Bool) throws {
        endPlayback(silenceMeter: false)
        let opened: AVAudioFile
        do { opened = try AVAudioFile(forReading: url) } catch {
            publishLevels(.silent())
            throw error
        }
        guard opened.length > 0 else { throw AudioCueError.empty(url.lastPathComponent) }
        file = opened
        fileName = url.lastPathComponent
        duration = Double(opened.length) / opened.processingFormat.sampleRate
        self.loops = loops
        var frame = Self.frame(for: seconds, in: opened)
        if frame >= opened.length { frame = 0 }            // asked to start at or past the end: from the top
        startFrame = frame
        heldFrame = frame
        resolveDevice(report: true)
        do {
            try startEngine(format: opened.processingFormat)
        } catch {
            file = nil
            duration = 0
            throw AudioCueError.engineFailed(error.localizedDescription)
        }
        applyLevel()
        schedule(from: frame)
        node.play()
        state = .playing
        startMeterTimer()
    }

    public func pause() {
        guard state == .playing else { return }
        heldFrame = currentFrame()
        node.pause()
        state = .paused
    }

    public func resume() {
        guard state == .paused, file != nil else { return }
        node.play()
        state = .playing
        startMeterTimer()
    }

    /// Jumps to `seconds` (clamped to the file). Keeps playing or stays paused, as it was.
    public func seek(to seconds: Double) {
        guard let file, state != .idle else { return }
        let frame = Self.frame(for: seconds, in: file)
        if state == .playing, frame >= file.length, !loops { finish(); return }
        let target = (loops && frame >= file.length) ? 0 : frame
        node.stop()
        startFrame = target
        heldFrame = target
        schedule(from: target)
        if state == .playing { node.play() }
    }

    /// Stops and forgets the file. The device is released. Not reported as an ending.
    public func stop() {
        endPlayback(silenceMeter: true)
    }

    public func setLoops(_ loops: Bool) {
        guard loops != self.loops else { return }
        guard file != nil, state != .idle else { self.loops = loops; return }
        // Where we are is read under the old setting (a looping position wraps). What is queued depends on the setting
        // (a looping cue always has its next pass queued), so it is queued again from here.
        let frame = state == .playing ? currentFrame() : heldFrame
        self.loops = loops
        node.stop()
        startFrame = frame
        heldFrame = frame
        schedule(from: frame)
        if state == .playing { node.play() }
    }

    /// 0...1 and mute; applied now and to every file played later.
    public func setLevel(volume: Float, muted: Bool) {
        self.volume = volume.isFinite ? min(1, max(0, volume)) : 0
        self.muted = muted
        applyLevel()
    }

    /// Seconds into the file. Where it stopped while paused; zero when idle. A looping file wraps.
    public var position: Double {
        guard let file, state != .idle else { return 0 }
        let rate = file.processingFormat.sampleRate
        let frame = state == .playing ? currentFrame() : heldFrame
        return Double(frame) / rate
    }

    // MARK: Device

    /// Sends the sound to the device with this UID, or to the system default when nil. A device that is not connected
    /// falls back to the default and is reported through `onDeviceLost`; the request is remembered, so the sound moves
    /// to the device when it appears.
    public func setOutputDevice(uid: String?) {
        let value = (uid?.isEmpty ?? true) ? nil : uid
        requestedUID = value
        lossReported = false
        resolveDevice(report: true)
    }

    private func deviceListChanged() {
        guard requestedUID != nil else { return }
        resolveDevice(report: true)
    }

    private func engineConfigurationChanged() {
        guard state != .idle, file != nil else { return }
        resolveDevice(report: true)
        restartEngine()
    }

    /// Works out which device is in effect and, if it changed, moves a running engine to it.
    private func resolveDevice(report: Bool) {
        var effective: String?
        if let want = requestedUID {
            if catalog.deviceID(forUID: want) != nil {
                effective = want
                lossReported = false
            } else if report, !lossReported {
                lossReported = true
                onDeviceLost?(want)
            }
        }
        let changed = effective != outputDeviceUID
        outputDeviceUID = effective
        if changed, state != .idle { restartEngine() }
    }

    /// The device to give the output unit: the chosen one, or whichever the system has as default right now.
    private func hardwareDeviceID() -> UInt32? {
        if let uid = outputDeviceUID, let id = catalog.deviceID(forUID: uid) { return id }
        return catalog.outputDevices().first(where: \.isDefault).flatMap { catalog.deviceID(forUID: $0.uid) }
    }

    // MARK: Engine

    /// (Re)connects the player to the mixer for this file's format and starts the engine, with the device set first.
    private func startEngine(format: AVAudioFormat) throws {
        node.stop()
        engine.stop()
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try applyHardwareDevice()
        engine.prepare()
        try engine.start()
        graphReady = true
    }

    private func applyHardwareDevice() throws {
        guard case .hardware = output, let id = hardwareDeviceID() else { return }
        // Only when it differs: setting the device makes the unit reinitialise.
        let unit = engine.outputNode.auAudioUnit
        if unit.deviceID != id { try unit.setDeviceID(id) }
    }

    /// After a device change or the system reconfiguring the engine: stop, point at the device, start, and carry on from
    /// the same place. Failing to do so ends the cue and says why.
    private func restartEngine() {
        guard let file, state != .idle else { return }
        guard case .hardware = output else { return }     // offline rendering has no device to move
        let frame = state == .playing ? currentFrame() : heldFrame
        let wasPlaying = state == .playing
        do {
            try startEngine(format: file.processingFormat)
            applyLevel()
            startFrame = frame
            heldFrame = frame
            schedule(from: frame)
            if wasPlaying { node.play() }
        } catch {
            endPlayback(silenceMeter: true)
            onFailure?("The sound could not continue on the new output: \(error.localizedDescription)")
        }
    }

    private func applyLevel() {
        node.volume = muted ? 0 : volume
    }

    // MARK: Closures AVFoundation calls on its own threads
    // These are built in `nonisolated` functions on purpose: a closure written inside a main-actor method is itself
    // main-actor isolated, and the runtime traps when an audio queue calls it.

    /// The meter's tap. Touches nothing but `box`.
    nonisolated private static func tapBlock(_ box: LevelBox) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { return }
            let channels = Int(buffer.format.channelCount)
            guard channels > 0 else { return }
            for c in 0..<2 {
                box.add(UnsafeBufferPointer(start: data[min(c, channels - 1)], count: frames), channel: c)
            }
        }
    }

    /// Called when the player node has finished playing a scheduled segment; hops to the main actor.
    nonisolated private static func completionHandler(_ owner: AudioCuePlayer, generation: Int)
        -> @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void {
        { [weak owner] _ in Task { @MainActor in owner?.segmentPlayed(generation: generation) } }
    }

    // MARK: Scheduling and position

    private static func frame(for seconds: Double, in file: AVAudioFile) -> AVAudioFramePosition {
        guard seconds.isFinite else { return 0 }
        let f = AVAudioFramePosition((max(0, seconds) * file.processingFormat.sampleRate).rounded())
        return min(f, file.length)
    }

    /// The frame being played now, from the player node's own sample clock.
    private func currentFrame() -> AVAudioFramePosition {
        guard let file else { return 0 }
        var played: AVAudioFramePosition = 0
        // playerTime(forNodeTime:) raises on a time that is not valid yet (before the first render), so check first.
        if let nodeTime = node.lastRenderTime, nodeTime.isSampleTimeValid || nodeTime.isHostTimeValid,
           let player = node.playerTime(forNodeTime: nodeTime), player.isSampleTimeValid {
            played = max(0, player.sampleTime)
        }
        let absolute = startFrame + played
        if loops { return absolute % max(1, file.length) }
        return min(absolute, file.length)
    }

    /// Queues the file from `frame`. A looping cue also queues its next pass, so the loop has no gap; each time a pass
    /// has been played another is queued. Callbacks from an earlier scheduling (before a stop or seek) are ignored.
    private func schedule(from frame: AVAudioFramePosition) {
        guard let file else { return }
        generation &+= 1
        let mine = generation
        queuedFrames = 0
        if frame < file.length { queue(file, from: frame, generation: mine) }
        if loops { queue(file, from: 0, generation: mine) }
    }

    private func queue(_ file: AVAudioFile, from frame: AVAudioFramePosition, generation mine: Int) {
        let count = AVAudioFrameCount(file.length - frame)
        queuedFrames += AVAudioFramePosition(count)
        if case .offline = output {
            // Offline rendering never reports that the sound was played back, and reports consumption long before the
            // end, so `renderOffline` watches the node's clock instead (see `maintainOffline`).
            node.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil)
        } else {
            node.scheduleSegment(file, startingFrame: frame, frameCount: count, at: nil, completionCallbackType: .dataPlayedBack,
                                 completionHandler: Self.completionHandler(self, generation: mine))
        }
    }

    private func segmentPlayed(generation mine: Int) {
        guard mine == generation, state == .playing, let file else { return }
        if loops {
            queue(file, from: 0, generation: mine)
        } else {
            finish()
        }
    }

    private func finish() {
        endPlayback(silenceMeter: true)
        onFinished?()
    }

    private func endPlayback(silenceMeter: Bool) {
        generation &+= 1
        node.stop()
        if graphReady { engine.stop(); graphReady = false }
        state = .idle
        file = nil
        duration = 0
        startFrame = 0
        heldFrame = 0
        stopMeterTimer()
        _ = meter.take()
        if silenceMeter { publishLevels(.silent()) }
    }

    // MARK: Meter

    /// The levels since the last take (tests, and `pollMeter`). Never touches the audio thread's data except under its lock.
    func takeMeter() -> AudioLevels { meter.take() ?? .silent() }

    func pollMeter() {
        if let levels = meter.take() { publishLevels(levels) }
    }

    private func publishLevels(_ levels: AudioLevels) { onLevels?(levels) }

    private func startMeterTimer() {
        guard meterTimer == nil else { return }
        if case .offline = output, !pumpsOffline { return }
        pumpClock = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func tick() {
        if case .offline = output, pumpsOffline, state == .playing {
            let now = ProcessInfo.processInfo.systemUptime
            let elapsed = min(0.25, max(0, now - pumpClock))
            pumpClock = now
            try? renderOffline(seconds: elapsed)
        }
        pollMeter()
    }

    // MARK: Offline rendering (tests, silent runs)

    /// Renders `seconds` of the graph with no device, driving the player node and the meter. Only for `.offline`.
    func renderOffline(seconds: Double) throws {
        guard case .offline(let rate) = output, let buffer = offlineBuffer else { return }
        var remaining = AVAudioFrameCount(max(0, seconds) * rate)
        while remaining > 0, engine.isRunning {
            if maintainOffline() { return }
            let chunk = min(remaining, buffer.frameCapacity)
            let status = try engine.renderOffline(chunk, to: buffer)
            if status == .error { throw AudioCueError.engineFailed("offline render failed") }
            if status == .insufficientDataFromInputNode || status == .cannotDoInCurrentContext { break }
            remaining -= chunk
        }
        _ = maintainOffline()
    }

    /// What the completion callbacks do on a device, done from the node's clock: ends a clip that does not loop once
    /// its last frame has been rendered, and keeps a looping clip's next passes queued. True when the clip ended.
    private func maintainOffline() -> Bool {
        guard state == .playing, let file else { return false }
        var played: AVAudioFramePosition = 0
        if let t = node.lastRenderTime, t.isSampleTimeValid || t.isHostTimeValid,
           let p = node.playerTime(forNodeTime: t), p.isSampleTimeValid { played = max(0, p.sampleTime) }
        if !loops {
            guard startFrame + played >= file.length else { return false }
            finish()
            return true
        }
        while queuedFrames < played + 2 * file.length { queue(file, from: 0, generation: generation) }
        return false
    }
}
