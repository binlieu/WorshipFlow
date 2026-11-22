// MEDIA-005 (MEDIA-05 / 06): the audio list, the cues and the programme audio device. Like `MediaModel` this keeps the
// state and the rules and plays nothing itself: each cue gets an `AudioCueEngine` from a factory (the app gives it the
// AVAudioEngine-based player, tests a fake) and the model tells it what to do. A failure sets `lastError` with a
// message a volunteer can act on; nothing here throws at the interface.
//
// Rules (all tested without a device):
// - One cue plays at a time. A cue marked "overlap" is the exception: starting it stops nothing, and starting an
//   ordinary cue leaves it playing (an ambient bed under a spoken part).
// - One "programme audio device" for everything the app plays: every cue and the foreground video go to it
//   (`onProgrammeDeviceChange` carries the choice to the video side). Nil is the system default. The choice is
//   stored. If the chosen device is missing, sound goes to the system default, the operator is told, the choice is
//   kept and honoured again when the device returns.
// - Stop (the show stopping) stops the cues. Clear and Clear all do not touch them.
//
// Foundation and Observation only; the views live in the app target.
import Foundation
import Observation
import Domain
import Persistence

/// The system's sound output devices, as the model needs them. The app adapts `MediaEngine.CoreAudioDeviceCatalog`.
public protocol AudioDeviceListing: Sendable {
    func outputDevices() -> [AudioOutputDevice]
    /// Calls `handler`, on any queue, when a device appears or disappears or the default changes. Returns a function
    /// that stops the calls.
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void
}

/// Plays one file for one cue. The app adapts `MediaEngine.AudioCuePlayer`.
@MainActor
public protocol AudioCueEngine: AnyObject {
    /// Opens the file and plays it from `seconds`. Throws, with a readable description, when it cannot.
    func play(url: URL, from seconds: Double, loops: Bool) throws
    func pause()
    func resume()
    func seek(to seconds: Double)
    func stop()
    func setLoops(_ loops: Bool)
    func setLevel(volume: Float, muted: Bool)
    /// A device UID, or nil for the system default. A device that is not connected falls back to the default.
    func setOutputDevice(uid: String?)
    /// The clip played to its end (not called for `stop()`).
    var onFinished: (@MainActor () -> Void)? { get set }
    /// About 20 times a second while it sounds.
    var onLevels: (@MainActor (AudioLevels) -> Void)? { get set }
    /// The device it was told to use is not there; carries the UID.
    var onDeviceLost: (@MainActor (String) -> Void)? { get set }
    /// Playback could not continue; carries a sentence for the operator.
    var onFailure: (@MainActor (String) -> Void)? { get set }
}

/// A file ready to read, with the access to it held until `release()` (security-scoped bookmarks).
public struct AudioFileAccess: Sendable {
    public var url: URL
    public var release: @Sendable () -> Void
    public init(url: URL, release: @escaping @Sendable () -> Void = {}) {
        self.url = url
        self.release = release
    }
}

/// One cue that is sounding or paused.
public struct ActiveCue: Sendable, Equatable {
    public var assetID: UUID
    public var transport: MediaTransport
}

/// What the Audio section shows for a cue that is playing.
public struct AudioReadout: Sendable, Equatable {
    public var assetID: UUID
    public var name: String
    public var status: MediaTransport.Status
    public var position: Double
    public var duration: Double
    public var remaining: Double
    public var isPlaying: Bool { status == .playing }
    /// False for a file whose length is not known: the scrubber is disabled.
    public var canSeek: Bool { duration > 0 }
}

@MainActor
@Observable
public final class AudioModel {
    // MARK: State the interface reads

    /// The audio list: the sound files of the media bin, in the order added.
    public private(set) var assets: [MediaAsset] = []
    /// Cues that are sounding or paused, in the order they started.
    public private(set) var activeCues: [ActiveCue] = []
    /// The output devices the system lists now.
    public private(set) var devices: [AudioOutputDevice] = []
    /// What the operator chose; nil is the system default. Kept while that device is unplugged.
    public private(set) var programmeDeviceUID: String?
    /// Set while the chosen device is not connected: why sound is on the system default.
    public private(set) var deviceNotice: String?
    public internal(set) var lastError: String?
    /// R12: set while a write (device, volume, overlap marks) failed and is still waiting to succeed.
    public internal(set) var writeProblem: String?
    public private(set) var volume: Double = 0.8
    public private(set) var isMuted = false
    /// Cues marked "overlap" (they may sound together with others).
    public private(set) var overlapIDs: Set<UUID> = []
    /// Cues set to loop. Not stored: a loop is a choice for this run.
    public private(set) var loopIDs: Set<UUID> = []
    /// The loudest of the sounding cues, per channel; silent when nothing plays.
    public private(set) var levels: AudioLevels = .silent()

    /// The device sound really goes to: the chosen one when it is connected, else the system default (nil).
    public var effectiveDeviceUID: String? {
        guard let uid = programmeDeviceUID, devices.contains(where: { $0.uid == uid }) else { return nil }
        return uid
    }

    /// The cue the transport shows: the one that started last.
    public var currentID: UUID? { activeCues.last?.assetID }

    public func asset(_ id: UUID) -> MediaAsset? { assets.first { $0.id == id } }
    public func isActive(_ id: UUID) -> Bool { activeCues.contains { $0.assetID == id } }

    /// Called on the main actor with the device in effect (nil: system default) after it changed and after loading, so
    /// the app can send the foreground video's sound to the same place.
    @ObservationIgnored public var onProgrammeDeviceChange: (@MainActor (String?) -> Void)?
    /// Called on the main actor after volume or mute changed.
    @ObservationIgnored public var onLevelChange: (@MainActor (_ volume: Float, _ muted: Bool) -> Void)?

    // MARK: Internals

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let listing: any AudioDeviceListing
    @ObservationIgnored private let makeEngine: @MainActor () -> any AudioCueEngine
    @ObservationIgnored private let now: @Sendable () -> Double
    @ObservationIgnored private let isAvailable: @Sendable (MediaAsset) -> Bool
    @ObservationIgnored private let access: @MainActor (MediaAsset) -> AudioFileAccess
    @ObservationIgnored private let writes: RetryingWriteChain
    @ObservationIgnored private var engines: [UUID: any AudioCueEngine] = [:]
    @ObservationIgnored private var releases: [UUID: @Sendable () -> Void] = [:]
    @ObservationIgnored private var cueLevels: [UUID: AudioLevels] = [:]
    @ObservationIgnored private var knownNames: [String: String] = [:]
    @ObservationIgnored private var showIsLive = false
    @ObservationIgnored private var stopObserving: (@Sendable () -> Void)?

    static let deviceKey = "audio.device"
    static let deviceNameKey = "audio.deviceName"
    static let volumeKey = "audio.volume"
    static let mutedKey = "audio.muted"
    static let overlapKey = "audio.overlap"

    /// - Parameters:
    ///   - makeEngine: gives each cue its own player.
    ///   - now: a monotonic clock in seconds.
    ///   - isAvailable: whether the file can be read now.
    ///   - access: opens a file (and holds security-scoped access); the default is the plain path.
    public init(store: LibraryStore, devices: any AudioDeviceListing,
                makeEngine: @escaping @MainActor () -> any AudioCueEngine,
                now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
                isAvailable: @escaping @Sendable (MediaAsset) -> Bool = { FileManager.default.isReadableFile(atPath: $0.path) },
                access: @escaping @MainActor (MediaAsset) -> AudioFileAccess = { AudioFileAccess(url: URL(fileURLWithPath: $0.path)) },
                clock: any SaveClock = RealSaveClock()) {
        self.store = store
        self.listing = devices
        self.makeEngine = makeEngine
        self.now = now
        self.isAvailable = isAvailable
        self.access = access
        writes = RetryingWriteChain(clock: clock, describe: { WorkspaceModel.message(for: $0, doing: $1) })
        writes.onProblemChange = { [weak self] in self?.writeProblem = $0 }
        writes.onFirstFailure = { [weak self] in self?.lastError = $0 }
    }

    /// Tests: called with the key of each write just before it runs; throwing makes it fail.
    var writeInterceptor: (@Sendable (String) async throws -> Void)? {
        get { writes.interceptor }
        set { writes.interceptor = newValue }
    }

    // MARK: Loading

    /// Reads the stored choices, lists the devices and starts watching them. Tells the app which device is in effect.
    public func load() async {
        let storedUID = (try? await store.state(for: Self.deviceKey)).flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
        let storedName = (try? await store.state(for: Self.deviceNameKey)).flatMap { $0 }
        if let text = (try? await store.state(for: Self.volumeKey)).flatMap({ $0 }), let v = Double(text), v.isFinite {
            volume = min(1, max(0, v))
        }
        if let text = (try? await store.state(for: Self.mutedKey)).flatMap({ $0 }) { isMuted = text == "1" }
        if let text = (try? await store.state(for: Self.overlapKey)).flatMap({ $0 }) {
            overlapIDs = Set(text.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
        }
        refreshDeviceList()
        programmeDeviceUID = storedUID
        if let storedUID, let storedName { knownNames[storedUID] = storedName }
        stopObserving?()
        stopObserving = listing.observeChanges { [weak self] in
            Task { @MainActor in self?.devicesChanged() }
        }
        if programmeDeviceUID != nil, effectiveDeviceUID == nil { reportMissingDevice() }
        onProgrammeDeviceChange?(effectiveDeviceUID)
    }

    /// Stops everything and the device watching. Writes already queued still finish.
    public func shutdown() {
        stopObserving?()
        stopObserving = nil
        stopAll()
    }

    /// Waits until every change made so far has been written.
    public func flush() async { await writes.flush() }

    public func dismissError() { lastError = nil }

    /// The audio assets of the bin (other kinds are ignored). A cue whose file left the bin stops.
    public func setAssets(_ all: [MediaAsset]) {
        assets = all.filter { $0.kind == .audio }
        let ids = Set(assets.map(\.id))
        for cue in activeCues where !ids.contains(cue.assetID) { stop(cue.assetID) }
    }

    // MARK: Playing

    /// Plays the file from the start. A cue that is already playing is left as it is; a paused one resumes. A file that
    /// cannot be read or opened is reported and nothing changes (a cue that was playing keeps playing).
    public func play(_ id: UUID) {
        if let problem = start(id) { lastError = problem }
    }

    /// FIX-H item 6: like `play`, but says why it did not play instead of only setting `lastError`. Nil when it plays.
    public func start(_ id: UUID) -> String? {
        guard let asset = asset(id) else { return nil }
        if isActive(id) { resume(id); return nil }
        guard isAvailable(asset) else { return Self.missingMessage(asset) }
        let file = access(asset)
        let engine = makeEngine()
        wire(engine, for: id)
        engine.setOutputDevice(uid: effectiveDeviceUID)
        engine.setLevel(volume: Float(volume), muted: isMuted)
        let looping = loopIDs.contains(id)
        do {
            try engine.play(url: file.url, from: 0, loops: looping)
        } catch {
            engine.stop()
            file.release()
            return "Could not play \"\(asset.name)\": \(error.localizedDescription) Choose another file, or remove it from the media bin and add it again."
        }
        // It is sounding. Now the cues it replaces stop: an ordinary cue replaces the other ordinary cues.
        if !overlapIDs.contains(id) {
            for other in activeCues where !overlapIDs.contains(other.assetID) { stop(other.assetID) }
        }
        engines[id] = engine
        releases[id] = file.release
        var transport = MediaTransport(duration: asset.duration ?? 0, loops: looping)
        transport.play(at: now())
        activeCues.append(ActiveCue(assetID: id, transport: transport))
        return nil
    }

    public func pause(_ id: UUID) {
        guard let i = index(of: id) else { return }
        activeCues[i].transport.pause(at: now())
        engines[id]?.pause()
    }

    public func resume(_ id: UUID) {
        guard let i = index(of: id), activeCues[i].transport.status(at: now()) == .paused else { return }
        activeCues[i].transport.play(at: now())
        engines[id]?.resume()
    }

    public func seek(_ id: UUID, to seconds: Double) {
        guard let i = index(of: id) else { return }
        let t = now()
        activeCues[i].transport.seek(to: seconds, at: t)
        engines[id]?.seek(to: activeCues[i].transport.position(at: t))
    }

    public func stop(_ id: UUID) {
        guard let i = index(of: id) else { return }
        activeCues.remove(at: i)
        release(id)
    }

    /// Stops every cue, overlap ones included.
    public func stopAll() {
        for cue in activeCues { release(cue.assetID) }
        activeCues.removeAll()
        recomputeLevels()
    }

    /// Whether this cue repeats. Applies to the cue now if it is playing, keeping its place.
    public func setLoops(_ on: Bool, for id: UUID) {
        if on { loopIDs.insert(id) } else { loopIDs.remove(id) }
        guard let i = index(of: id), activeCues[i].transport.loops != on else { return }
        let t = now()
        let old = activeCues[i].transport
        let position = old.position(at: t)
        let status = old.status(at: t)
        var next = MediaTransport(duration: old.duration, loops: on)
        next.play(at: t)
        next.seek(to: position, at: t)
        if status == .paused { next.pause(at: t) }
        activeCues[i].transport = next
        engines[id]?.setLoops(on)
    }

    /// Marks the cue as one that may sound together with others. Stored.
    public func setOverlap(_ on: Bool, for id: UUID) {
        guard on != overlapIDs.contains(id) else { return }
        if on { overlapIDs.insert(id) } else { overlapIDs.remove(id) }
        let text = overlapIDs.map(\.uuidString).sorted().joined(separator: ",")
        persist(key: "overlap", "remember which sounds may overlap") { [store] in try await store.setState(text, for: Self.overlapKey) }
    }

    /// Ends the cues whose clip has reached its end by the clock. True when something ended.
    @discardableResult
    public func tick(now at: Double? = nil) -> Bool {
        let t = at ?? now()
        let ended = activeCues.filter { $0.transport.status(at: t) == .ended }.map(\.assetID)
        for id in ended { stop(id) }
        return !ended.isEmpty
    }

    public func readout(for id: UUID, at time: Double? = nil) -> AudioReadout? {
        guard let cue = activeCues.first(where: { $0.assetID == id }) else { return nil }
        let t = time ?? now()
        return AudioReadout(assetID: id, name: asset(id)?.name ?? "Sound", status: cue.transport.status(at: t),
                            position: cue.transport.position(at: t), duration: cue.transport.duration,
                            remaining: cue.transport.remaining(at: t))
    }

    // MARK: Show

    /// The app says whether the show is running. Cues stop when the show stops (Stop); the change from stopped to
    /// stopped, and Clear or Clear all, do not stop anything.
    public func showStateChanged(isLive: Bool) {
        let was = showIsLive
        showIsLive = isLive
        if was, !isLive { stopAll() }
    }

    // MARK: Level

    public func setVolume(_ value: Double) {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        guard v != volume else { return }
        volume = v
        applyLevel()
        persist(key: "volume", "remember the sound volume") { [store] in try await store.setState(String(v), for: Self.volumeKey) }
    }

    public func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        applyLevel()
        persist(key: "muted", "remember the sound mute") { [store] in try await store.setState(muted ? "1" : "0", for: Self.mutedKey) }
    }

    private func applyLevel() {
        for engine in engines.values { engine.setLevel(volume: Float(volume), muted: isMuted) }
        onLevelChange?(Float(volume), isMuted)
    }

    // MARK: Programme audio device (MEDIA-006)

    /// Reads the device list again (the picker calls this when it opens).
    public func refreshDevices() { devicesChanged() }

    /// Chooses where the sound goes; nil is the system default. A device that is not connected is not chosen: the sound
    /// stays on the system default and the operator is told.
    public func chooseDevice(_ uid: String?) {
        refreshDeviceList()
        let before = effectiveDeviceUID
        if let uid, !devices.contains(where: { $0.uid == uid }) {
            programmeDeviceUID = nil
            deviceNotice = nil
            lastError = "The sound device \"\(knownNames[uid] ?? uid)\" is not connected, so the sound plays through the system default. Connect it and choose it again."
            storeDeviceChoice(nil)
        } else {
            programmeDeviceUID = uid
            deviceNotice = nil
            storeDeviceChoice(uid)
        }
        if effectiveDeviceUID != before { applyDevice() }
    }

    private func storeDeviceChoice(_ uid: String?) {
        let name = uid.flatMap { knownNames[$0] }
        persist(key: "device", "remember the sound device") { [store] in
            try await store.setState(uid, for: Self.deviceKey)
            try await store.setState(name, for: Self.deviceNameKey)
        }
    }

    private func refreshDeviceList() {
        devices = listing.outputDevices()
        for d in devices { knownNames[d.uid] = d.name }
    }

    private func devicesChanged() {
        let before = effectiveDeviceUID
        refreshDeviceList()
        let after = effectiveDeviceUID
        if programmeDeviceUID != nil {
            if after == nil { if deviceNotice == nil { reportMissingDevice() } } else { deviceNotice = nil }
        }
        if after != before { applyDevice() }
    }

    private func reportMissingDevice() {
        guard let uid = programmeDeviceUID else { return }
        let name = knownNames[uid] ?? uid
        let playing = activeCues.isEmpty ? "Sound will play" : "Sound is still playing"
        let text = "The sound device \"\(name)\" is not connected. \(playing) through the system default, and moves back to \"\(name)\" when it is connected again."
        deviceNotice = text
        lastError = text
    }

    private func applyDevice() {
        let uid = effectiveDeviceUID
        for engine in engines.values { engine.setOutputDevice(uid: uid) }
        onProgrammeDeviceChange?(uid)
    }

    // MARK: Helpers

    private func wire(_ engine: any AudioCueEngine, for id: UUID) {
        engine.onFinished = { [weak self, weak engine] in
            guard let self, let engine, self.engines[id] === engine else { return }
            self.stop(id)
        }
        engine.onLevels = { [weak self, weak engine] levels in
            guard let self, let engine, self.engines[id] === engine else { return }
            self.cueLevels[id] = levels
            self.recomputeLevels()
        }
        engine.onDeviceLost = { [weak self, weak engine] uid in
            guard let self, let engine, self.engines[id] === engine else { return }
            if uid == self.programmeDeviceUID, self.deviceNotice == nil { self.reportMissingDevice() }
        }
        engine.onFailure = { [weak self, weak engine] message in
            guard let self, let engine, self.engines[id] === engine else { return }
            self.stop(id)
            self.lastError = message
        }
    }

    private func index(of id: UUID) -> Int? { activeCues.firstIndex { $0.assetID == id } }

    /// Lets go of the engine and the file access of a cue that is no longer in `activeCues`.
    private func release(_ id: UUID) {
        let engine = engines.removeValue(forKey: id)
        engine?.stop()
        releases.removeValue(forKey: id)?()
        cueLevels[id] = nil
        recomputeLevels()
    }

    private func recomputeLevels() {
        let live = activeCues.compactMap { cueLevels[$0.assetID] }
        levels = live.dropFirst().reduce(live.first ?? .silent()) { $0.combined(with: $1) }
    }

    private static func missingMessage(_ asset: MediaAsset) -> String {
        "The file for \"\(asset.name)\" is missing or cannot be read: \(asset.path). Check that the drive or folder is connected, or remove it from the media bin and add it again."
    }

    private func persist(key: String, _ what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        writes.persist(key: key, what: what, operation)
    }
}

// FIX-H item 6: the sound player as the playlist runner sees it.
extension AudioModel: AudioPlayerPort {
    public func name(of assetID: UUID) -> String? { asset(assetID)?.name }
    public func startSound(_ assetID: UUID) -> String? { start(assetID) }
    public func isReadable(_ assetID: UUID) -> Bool { asset(assetID).map { isAvailable($0) } ?? false }
}
