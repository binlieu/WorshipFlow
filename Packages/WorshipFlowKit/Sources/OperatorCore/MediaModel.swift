// MEDIA-001 (MEDIA-01 / 02 / 03): the media bin and the two media layers. The bin is a list of references to files
// (removing one never touches the file); the layers are the pure `MediaLayers` value from Domain. This model never
// plays anything: it keeps the state, tells the app when it changed (`onLayersChange`), and the app opens players.
// A failure sets `lastError` with a message a volunteer can act on; nothing here throws at the interface.
// Foundation and Observation only; the views live in the app target.
import Foundation
import Observation
import Domain
import Persistence

/// What a prober learned about a file. The app adapts `MediaEngine.MediaProbe` to this; tests use a fake.
public struct MediaProbeResult: Sendable, Equatable {
    public var kind: MediaKind
    public var duration: Double?
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(kind: MediaKind, duration: Double? = nil, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.kind = kind
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// How a player is doing, as the app reads it from the media registry. `.starting` is normal for a video until an
/// output has pulled its first frame.
public enum ClipAvailability: Sendable, Equatable {
    case notOpen, starting, delivering
    case failed(String)
    case stalled
}

public protocol MediaProber: Sendable {
    /// Reads the file's header. Throws an error whose `localizedDescription` says what is wrong with the file.
    func probe(url: URL) async throws -> MediaProbeResult
}

/// What the transport strip shows for the clip playing in the foreground.
public struct ForegroundReadout: Sendable, Equatable {
    public var assetID: UUID
    public var name: String
    public var status: MediaTransport.Status
    public var position: Double
    public var duration: Double
    public var remaining: Double
    public var isPlaying: Bool { status == .playing }
    /// False for a clip whose length is not known: the scrubber is disabled.
    public var canSeek: Bool { duration > 0 }
}

@MainActor
@Observable
public final class MediaModel {
    // MARK: State the interface reads

    /// The bin, in the order added.
    public private(set) var assets: [MediaAsset] = []
    /// Nil shows every kind.
    public var kindFilter: MediaKind?
    public private(set) var layers = MediaLayers()
    public internal(set) var lastError: String?
    /// R12: set while a write (the remembered background) failed and is still waiting to succeed, with the reason.
    public internal(set) var writeProblem: String?
    /// Foreground audio, 0...1 and mute (default output device). A background loop is always muted.
    public private(set) var volume: Double = 0.5
    public private(set) var isMuted = false
    /// FIX-D (coordinator decision): Blackout is on, so the foreground clip's sound is off. The operator's own volume and mute
    /// choices are not changed; the sound comes back at the level it had when Blackout lifts.
    public private(set) var isMutedByBlackout = false
    /// True while a slide is live or cleared. A clip is only played over a running show, and stops with it.
    public private(set) var showIsLive = false
    /// FIX-H item 1: how many times anything started a clip or picture over the screens (a bin choice, the dock, a cue, a folder, a
    /// playlist loop). A loop compares it with the count after its own start to see that nobody else has taken the foreground.
    public private(set) var foregroundStarts = 0
    /// UI-003: the clip over the slide starts again when it ends, until it is stopped or replaced. Only ever true while
    /// the clip it was chosen for is still the foreground.
    public var foregroundLoops: Bool {
        guard let id = loopingAssetID else { return false }
        return layers.foreground?.selection.assetID == id
    }
    private var loopingAssetID: UUID?

    // MARK: MEDIA-010 state
    /// MEDIA-010: the background video's sound. A background starts muted, which stays until the operator unmutes it.
    public private(set) var isBackgroundMuted = true
    /// The state the player is given: the operator's choice, or silent while Blackout is on.
    public var backgroundHeardMuted: Bool { isBackgroundMuted || isMutedByBlackout }
    /// MEDIA-010: a live background chosen in the bin (or by a cue or folder) is on. It is a live override: it never writes to
    /// the presentation, and it stays until it is dropped or replaced.
    public var hasLiveBackgroundOverride: Bool { layers.background != nil }
    /// The hot folder playing its videos one after another, if one is.
    public var playingFolderID: UUID? { folderPlay?.folderID }
    @ObservationIgnored private var hotAssetsByFolder: [UUID: [MediaAsset]] = [:]
    /// FIX-G: hot items that the folder no longer lists but that are on a layer now. They stay registered (so the player is not
    /// closed under a clip that is on air) until the layer lets go of them.
    @ObservationIgnored private var retainedHot: [UUID: MediaAsset] = [:]
    /// FIX-G: the remembered background was not found when the bin loaded (a hot folder item: the folders load later, and launch does
    /// not wait for them). It is restored as soon as the item is listed, unless the operator chose something else meanwhile.
    @ObservationIgnored private var pendingBackgroundID: UUID?
    @ObservationIgnored private var folderPlay: FolderPlay?

    /// Which layer a hot folder plays on.
    public enum FolderLayer: Sendable, Equatable { case background, foreground }
    private struct FolderPlay { var folderID: UUID; var layer: FolderLayer; var current: String; var reported: Set<String> = [] }

    public var visibleAssets: [MediaAsset] {
        guard let kindFilter else { return assets }
        return assets.filter { $0.kind == kindFilter }
    }

    public func asset(_ id: UUID) -> MediaAsset? {
        assets.first { $0.id == id } ?? hotAssetsByFolder.values.lazy.flatMap { $0 }.first { $0.id == id } ?? retainedHot[id]
    }

    /// MEDIA-010: the bin's items and the items of every hot folder, for the registry and the audio list.
    public var allAssets: [MediaAsset] {
        assets + hotAssetsByFolder.keys.sorted { $0.uuidString < $1.uuidString }.flatMap { hotAssetsByFolder[$0] ?? [] }
            + retainedHot.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Called on the main actor after the bin's contents change (add, rename, remove, load).
    @ObservationIgnored public var onAssetsChange: (@MainActor ([MediaAsset]) -> Void)?
    /// Called on the main actor after every change to the layers, so the app can open and close players and publish scenes.
    @ObservationIgnored public var onLayersChange: (@MainActor (MediaLayers) -> Void)?
    /// Called on the main actor after the volume or mute changed.
    @ObservationIgnored public var onAudioChange: (@MainActor (_ volume: Float, _ muted: Bool) -> Void)?
    /// MEDIA-010: called after the background video's sound changed (its mute, the volume, Blackout). `muted` is the state to
    /// be heard, Blackout included.
    @ObservationIgnored public var onBackgroundAudioChange: (@MainActor (_ volume: Float, _ muted: Bool) -> Void)?
    /// MEDIA-010: a new live background was chosen. The app uses it to bring a cleared background back.
    @ObservationIgnored public var onBackgroundChosen: (@MainActor () -> Void)?

    // MARK: Internals

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let prober: any MediaProber
    @ObservationIgnored private let now: @Sendable () -> Double
    @ObservationIgnored private let isAvailable: @Sendable (MediaAsset) -> Bool
    @ObservationIgnored private let writes: RetryingWriteChain

    static let backgroundKey = "media.background"

    /// - Parameters:
    ///   - now: a monotonic clock in seconds (the same one the players use).
    ///   - isAvailable: whether the file can be read now. Tests inject their own; the default asks the file system.
    public init(store: LibraryStore, prober: any MediaProber,
                now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
                isAvailable: @escaping @Sendable (MediaAsset) -> Bool = { FileManager.default.isReadableFile(atPath: $0.path) },
                clock: any SaveClock = RealSaveClock()) {
        self.store = store
        self.prober = prober
        self.now = now
        self.isAvailable = isAvailable
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

    /// Reads the bin and brings the chosen background back. The foreground is never restored.
    public func load() async {
        guard let all = await attempt("read the media bin", { try await self.store.mediaAssets(kind: nil) }) else { return }
        assets = all
        onAssetsChange?(allAssets)
        guard let text = try? await store.state(for: Self.backgroundKey), let id = UUID(uuidString: text) else { return }
        guard let asset = asset(id) else {
            // Removed from the bin, or an item of a hot folder that has not been listed yet: wait for it (FIX-G).
            pendingBackgroundID = id
            return
        }
        restoreRemembered(asset)
    }

    private func restoreRemembered(_ asset: MediaAsset) {
        pendingBackgroundID = nil
        guard isAvailable(asset) else {
            // The choice stays stored, so it comes back when the drive does; this run shows the theme's own background.
            lastError = Self.missingMessage(asset, what: "The background")
            return
        }
        guard asset.kind != .audio else { return }
        layers.setBackground(MediaSelection(asset: asset), at: now())
        layersChanged()
    }

    /// Waits until every change made so far has been written. A write that failed earlier is tried again now (R12).
    public func flush() async { await writes.flush() }

    public func dismissError() { lastError = nil }

    /// MEDIA-010: a message for the operator from the interface (a refused drop).
    public func report(_ text: String) { lastError = text }

    // MARK: The bin

    /// Adds one file. The same path returns the existing entry. Returns nil, with `lastError` set, when the file cannot
    /// be used; nothing changes then.
    @discardableResult
    public func add(url: URL, bookmark: Data? = nil) async -> MediaAsset? {
        let name = url.deletingPathExtension().lastPathComponent
        let info: MediaProbeResult
        do { info = try await prober.probe(url: url) } catch {
            lastError = "Could not add \"\(url.lastPathComponent)\" to the media bin: \(error.localizedDescription) The file was not added."
            return nil
        }
        let label = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? url.lastPathComponent : name
        guard let added = await attempt("add \"\(url.lastPathComponent)\" to the media bin", {
            try await self.store.addMediaAsset(name: label, kind: info.kind, path: url.path, bookmark: bookmark,
                                               duration: info.duration, pixelWidth: info.pixelWidth, pixelHeight: info.pixelHeight)
        }) else { return nil }
        await reload()
        return added
    }

    /// Adds several files in order. Files that cannot be used are reported together in `lastError`; the rest are added.
    @discardableResult
    public func add(urls: [URL], bookmarks: [URL: Data] = [:]) async -> [MediaAsset] {
        var added: [MediaAsset] = []
        var failures: [String] = []
        for url in urls {
            lastError = nil
            if let asset = await add(url: url, bookmark: bookmarks[url]) { added.append(asset) }
            else if let message = lastError { failures.append(message) }
        }
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
        return added
    }

    public func rename(_ id: UUID, to name: String) async {
        guard asset(id) != nil else { return }
        guard await attempt("rename the media item", { try await self.store.renameMediaAsset(id: id, to: name) }) != nil else { return }
        await reload()
    }

    /// Removes the reference. The file on disk is never touched. A removed asset leaves the layers it was in.
    public func remove(_ id: UUID) async {
        guard asset(id) != nil else { return }
        if layers.background?.selection.assetID == id { clearBackground() }
        if layers.foreground?.selection.assetID == id { stopForeground() }
        guard await attempt("remove the media item", { try await self.store.removeMediaAsset(id: id) }) != nil else { return }
        await reload()
    }

    /// FIX-G: what removing the item would do to slides that use it as their own background, to show before asking. Reads only.
    public func removalImpact(_ id: UUID) async -> SlideBackgroundRemovalImpact {
        let name = asset(id)?.name ?? "This item"
        let uses = (await attempt("look for slides that use the media item", { try await self.store.slidesUsingBackground(of: id) })) ?? []
        return SlideBackgroundRemovalImpact(itemName: name, uses: uses)
    }

    private func reload() async {
        guard let all = await attempt("read the media bin", { try await self.store.mediaAssets(kind: nil) }) else { return }
        assets = all
        onAssetsChange?(allAssets)
    }

    // MARK: Background

    /// Starts the item looping behind the slides. Persisted, so the next launch brings it back.
    public func setBackground(_ id: UUID) {
        guard let asset = asset(id), usable(asset, as: "a background") else { return }
        pendingBackgroundID = nil
        endFolderPlay(on: .background)
        if layers.background?.selection == MediaSelection(asset: asset) { return }
        layers.setBackground(MediaSelection(asset: asset), at: now())
        persistBackground(asset.id)
        layersChanged()
        onBackgroundChosen?()
    }

    /// MEDIA-010: drops the live override (the inspector's button); the slide's own background shows again.
    public func dropBackgroundOverride() { clearBackground() }

    public func clearBackground() {
        endFolderPlay(on: .background)
        let had = layers.background != nil
        pendingBackgroundID = nil
        layers.setBackground(nil, at: now())
        persistBackground(nil)
        if had { layersChanged() }
    }

    private func persistBackground(_ id: UUID?) {
        let text = id?.uuidString
        persist(key: "background", "remember the background") { [store] in try await store.setState(text, for: Self.backgroundKey) }
    }

    // MARK: Foreground

    /// Plays the item once over the slides, from the start. Refused, with a message, while the screens are stopped.
    public func playForeground(_ id: UUID) {
        if let problem = startForeground(id) { lastError = problem }
    }

    /// FIX-H item 6: like `playForeground`, but says why it did not play instead of only setting `lastError`. Nil when it plays.
    public func startForeground(_ id: UUID) -> String? {
        guard let asset = asset(id) else { return nil }
        if let problem = unusableReason(asset, as: "a video or picture on the screens") { return problem }
        guard showIsLive else {
            return "Take a slide live first, then play \"\(asset.name)\": the screens are stopped, so nobody would see it."
        }
        endFolderPlay(on: .foreground)
        loopingAssetID = nil                      // a new clip plays once unless the operator asks otherwise
        layers.startForeground(MediaSelection(asset: asset), at: now())
        foregroundStarts += 1
        layersChanged()
        return nil
    }

    /// UI-003: loop or stop looping the clip over the slide. Nothing is playing: nothing to loop.
    public func setForegroundLoops(_ on: Bool) {
        guard let f = layers.foreground else { loopingAssetID = nil; return }
        loopingAssetID = on ? f.selection.assetID : nil
    }

    /// UI-003: back to the start of the clip, playing.
    public func restartForeground() {
        guard layers.foreground != nil else { return }
        layers.seekForeground(to: 0, at: now())
        layers.resumeForeground(at: now())
        layersChanged()
    }

    public func pause() {
        guard layers.foreground != nil else { return }
        layers.pauseForeground(at: now())
        layersChanged()
    }

    public func resume() {
        guard layers.foreground != nil else { return }
        layers.resumeForeground(at: now())
        layersChanged()
    }

    public func seek(to seconds: Double) {
        guard layers.foreground != nil else { return }
        layers.seekForeground(to: seconds, at: now())
        layersChanged()
    }

    public func stopForeground() {
        endFolderPlay(on: .foreground)
        loopingAssetID = nil
        guard layers.foreground != nil else { return }
        layers.stopForeground()
        layersChanged()
    }

    // MARK: Background loop controls (UI-003)

    public func pauseBackground() {
        guard layers.background != nil else { return }
        layers.pauseBackground(at: now())
        layersChanged()
    }

    public func resumeBackground() {
        guard layers.background != nil else { return }
        layers.resumeBackground(at: now())
        layersChanged()
    }

    public func seekBackground(to seconds: Double) {
        guard layers.background != nil else { return }
        layers.seekBackground(to: seconds, at: now())
        layersChanged()
    }

    public func restartBackground() {
        guard layers.background != nil else { return }
        layers.seekBackground(to: 0, at: now())
        layers.resumeBackground(at: now())
        layersChanged()
    }

    /// The background video's clock for the controller row. Nil for a picture, or with no background.
    public func backgroundReadout(at time: Double? = nil) -> ForegroundReadout? {
        guard let b = layers.background, b.selection.kind == .video else { return nil }
        let t = time ?? now()
        return ForegroundReadout(assetID: b.selection.assetID, name: asset(b.selection.assetID)?.name ?? "Background",
                                 status: b.transport.status(at: t), position: b.transport.position(at: t),
                                 duration: b.transport.duration, remaining: b.transport.remaining(at: t))
    }

    /// Ends a clip that has finished. Returns true when something changed (the words come back on the screens).
    @discardableResult
    public func tick(now at: Double? = nil) -> Bool {
        let t = at ?? now()
        if advanceFolderIfDue(at: t) { return true }
        if restartLoopingClipIfEnded(at: t) { return true }
        guard layers.tick(at: t) else { return false }
        layersChanged()
        return true
    }

    /// The player reported the end of the clip. Ends it too, so a clip whose length is not stored (and which the clock
    /// therefore never ends) does not stay on the screens. A late report from a clip that was replaced is ignored: when
    /// the length is known the clip must be within a second of its end.
    @discardableResult
    public func playerReportedEnd(now at: Double? = nil) -> Bool {
        guard let foreground = layers.foreground else { return false }
        let t = at ?? now()
        let transport = foreground.transport
        if transport.duration > 0, transport.remaining(at: t) > 1.0 { return false }
        if folderPlay?.layer == .foreground { advanceFolder(at: t); return true }
        if foregroundLoops { restartForegroundNow(foreground, at: t); return true }
        layers.stopForeground()
        layersChanged()
        return true
    }

    /// A clip set to loop that reached its end plays again from the start instead of leaving the screens.
    private func restartLoopingClipIfEnded(at t: Double) -> Bool {
        guard foregroundLoops, let f = layers.foreground, f.transport.status(at: t) == .ended else { return false }
        restartForegroundNow(f, at: t)
        return true
    }

    private func restartForegroundNow(_ f: MediaLayer, at t: Double) {
        layers.startForeground(f.selection, at: t)
        layersChanged()
    }

    /// Position, duration and status of the foreground clip at `time` (now by default); nil when there is none.
    public func foregroundReadout(at time: Double? = nil) -> ForegroundReadout? {
        guard let f = layers.foreground else { return nil }
        let t = time ?? now()
        return ForegroundReadout(assetID: f.selection.assetID, name: asset(f.selection.assetID)?.name ?? "Clip",
                                 status: f.transport.status(at: t), position: f.transport.position(at: t),
                                 duration: f.transport.duration, remaining: f.transport.remaining(at: t))
    }

    // MARK: Show and audio

    /// The app says whether the show is running. A clip stops when the show does (Stop empties every screen).
    public func showStateChanged(isLive: Bool, isBlackedOut: Bool = false) {
        showIsLive = isLive
        if !isLive { stopForeground() }
        // Blackout also takes the clip's sound off the speakers (the picture is already black), and a clip started during
        // Blackout starts silent; lifting Blackout (or Stop, which ends it) puts the operator's level back.
        let blackout = isLive && isBlackedOut
        guard blackout != isMutedByBlackout else { return }
        isMutedByBlackout = blackout
        onAudioChange?(Float(volume), isMuted || isMutedByBlackout)
        onBackgroundAudioChange?(Float(volume), backgroundHeardMuted)
    }

    /// R17: the screens were closed. The clip playing over the slide stops (its sound with it); the background stays
    /// chosen, so it plays again when the screens open.
    public func screensClosed() { stopForeground() }

    public func setVolume(_ value: Double) {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        guard v != volume else { return }
        volume = v
        onAudioChange?(Float(volume), isMuted || isMutedByBlackout)
        onBackgroundAudioChange?(Float(volume), backgroundHeardMuted)
    }

    /// MEDIA-010: mute or unmute the background video's sound. The choice holds across Next and a new background; Blackout
    /// silences it meanwhile and the choice comes back when it lifts.
    public func setBackgroundMuted(_ muted: Bool) {
        guard muted != isBackgroundMuted else { return }
        isBackgroundMuted = muted
        onBackgroundAudioChange?(Float(volume), backgroundHeardMuted)
    }

    public func setMuted(_ muted: Bool) {
        guard muted != isMuted else { return }
        isMuted = muted
        onAudioChange?(Float(volume), isMuted || isMutedByBlackout)
    }

    // MARK: Problems found while playing

    /// The player could not open these files (moved, unplugged, damaged). The layer that holds one is taken out, so the
    /// screens show the words and the theme's own background instead of a hole, and the operator is told.
    public func reportUnavailable(_ ids: Set<UUID>) {
        var changed = false
        if let f = layers.foreground, ids.contains(f.selection.assetID) {
            layers.stopForeground()
            lastError = Self.playbackMessage(asset(f.selection.assetID), what: "The video or picture")
            changed = true
        }
        if let b = layers.background, ids.contains(b.selection.assetID) {
            layers.setBackground(nil, at: now())      // the stored choice is kept: it returns when the file does
            lastError = Self.playbackMessage(asset(b.selection.assetID), what: "The background")
            changed = true
        }
        if changed { layersChanged() }
    }

    /// A player's availability changed. A foreground clip that failed or stalled ends, so the words come back, and the
    /// operator is told which file. A background that failed or stalled is reported and taken out (the theme's own
    /// background shows); its choice stays stored. Other states, and other assets, change nothing.
    public func availabilityChanged(_ id: UUID, _ state: ClipAvailability) {
        let why: String
        switch state {
        case .failed(let reason): why = reason
        case .stalled: why = "it stopped playing and could not be restarted."
        case .notOpen, .starting, .delivering: return
        }
        var changed = false
        if let f = layers.foreground, f.selection.assetID == id {
            layers.stopForeground()
            lastError = Self.playbackMessage(asset(id), what: "The video or picture", why: why)
            changed = true
        }
        if let b = layers.background, b.selection.assetID == id {
            layers.setBackground(nil, at: now())
            lastError = Self.playbackMessage(asset(id), what: "The background", why: why)
            changed = true
        }
        if changed { layersChanged() }
    }

    // MARK: Hot folders (MEDIA-010)

    /// The items of one hot folder, as the folder model last saw them. An empty list forgets the folder. Items are not in
    /// the bin and are never stored here; they can be chosen, played and found like bin items.
    public func setHotAssets(_ folderID: UUID, _ items: [MediaAsset]) {
        let previous = hotAssetsByFolder[folderID] ?? []
        if items.isEmpty { hotAssetsByFolder[folderID] = nil } else { hotAssetsByFolder[folderID] = items }
        // FIX-G: an item that is on a layer stays registered while it plays, whatever this scan says.
        let onLayers = idsOnLayers
        let listed = Set(items.map(\.id))
        for old in previous where onLayers.contains(old.id) && !listed.contains(old.id) { retainedHot[old.id] = old }
        for id in listed { retainedHot[id] = nil }
        onAssetsChange?(allAssets)
        if let pending = pendingBackgroundID, layers.background == nil, let asset = asset(pending) { restoreRemembered(asset) }
    }

    private var idsOnLayers: Set<UUID> {
        Set([layers.background?.selection.assetID, layers.foreground?.selection.assetID].compactMap { $0 })
    }

    /// A retained item that no layer holds any more goes (and the registry is told).
    private func releaseRetainedHot() {
        guard !retainedHot.isEmpty else { return }
        let held = idsOnLayers
        let before = retainedHot.count
        retainedHot = retainedHot.filter { held.contains($0.key) }
        if retainedHot.count != before { onAssetsChange?(allAssets) }
    }

    /// Plays the folder's videos one after another in name order, and again from the first after the last. Refused, with a
    /// message, when the folder has no video, or for the foreground while the screens are stopped.
    public func playFolder(_ folderID: UUID, on layer: FolderLayer) {
        let videos = folderVideos(folderID)
        guard !videos.isEmpty else {
            lastError = "This folder has no videos to play yet. Videos that are still being copied in are played when they are complete."
            return
        }
        if layer == .foreground, !showIsLive {
            lastError = "Take a slide live first, then play the folder over the words: the screens are stopped, so nobody would see it."
            return
        }
        // FIX-G: a file that cannot be read is skipped, and said so once; if none can be played it stops and says so.
        let skipped = videos.filter { !isAvailable($0) }.map(\.name)
        guard let first = videos.first(where: { isAvailable($0) }) else {
            lastError = "None of the videos in this folder can be played: \(Self.quoted(skipped)) could not be read. Check that the drive or folder is connected."
            return
        }
        endFolderPlay(on: layer)
        pendingBackgroundID = layer == .background ? nil : pendingBackgroundID
        folderPlay = FolderPlay(folderID: folderID, layer: layer, current: first.name, reported: Set(skipped))
        if !skipped.isEmpty { lastError = Self.skippedMessage(skipped) }
        startFolderClip(first, on: layer)
        if layer == .background { onBackgroundChosen?() }
    }

    private static func quoted(_ names: [String]) -> String { names.map { "\"\($0)\"" }.joined(separator: ", ") }
    private static func skippedMessage(_ names: [String]) -> String {
        "\(quoted(names)) could not be read and was skipped; the folder goes on with the next video."
    }

    public func stopFolder() {
        guard let play = folderPlay else { return }
        folderPlay = nil
        switch play.layer {
        case .background: clearBackground()
        case .foreground: stopForeground()
        }
    }

    private func folderVideos(_ id: UUID) -> [MediaAsset] {
        (hotAssetsByFolder[id] ?? []).filter { $0.kind == .video }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A choice or a clear on the layer the folder plays on ends the folder play; it is never replaced behind the operator's back.
    private func endFolderPlay(on layer: FolderLayer) {
        if folderPlay?.layer == layer { folderPlay = nil }
    }

    private func startFolderClip(_ asset: MediaAsset, on layer: FolderLayer) {
        switch layer {
        case .background: layers.setBackground(MediaSelection(asset: asset), at: now(), loops: false)
        case .foreground:
            loopingAssetID = nil
            layers.startForeground(MediaSelection(asset: asset), at: now())
            foregroundStarts += 1
        }
        layersChanged()
    }

    /// Moves to the next video, in the order as the folder is now. Nothing to play (the folder emptied or went missing) ends it.
    private func advanceFolder(at t: Double) {
        guard let play = folderPlay else { return }
        let all = folderVideos(play.folderID)
        let queue = all.filter { isAvailable($0) }
        // FIX-G: a file that went bad since the last time is skipped and reported once.
        let newlySkipped = all.filter { !isAvailable($0) && !play.reported.contains($0.name) }.map(\.name)
        if !newlySkipped.isEmpty {
            folderPlay?.reported.formUnion(newlySkipped)
            lastError = Self.skippedMessage(newlySkipped)
        }
        guard !queue.isEmpty else {
            if !all.isEmpty { lastError = "None of the videos in this folder can be played now: \(Self.quoted(all.map(\.name))) could not be read." }
            folderPlay = nil
            switch play.layer {
            case .background: layers.setBackground(nil, at: t)
            case .foreground: layers.stopForeground()
            }
            layersChanged()
            return
        }
        let next = queue.first { $0.name.localizedStandardCompare(play.current) == .orderedDescending } ?? queue[0]
        folderPlay?.current = next.name
        startFolderClip(next, on: play.layer)
    }

    private func advanceFolderIfDue(at t: Double) -> Bool {
        guard let play = folderPlay else { return false }
        switch play.layer {
        case .background:
            guard let b = layers.background else { folderPlay = nil; return false }
            guard b.transport.status(at: t) == .ended else { return false }
        case .foreground:
            guard let f = layers.foreground else { folderPlay = nil; return false }
            guard f.transport.status(at: t) == .ended else { return false }
        }
        advanceFolder(at: t)
        return true
    }

    // MARK: Helpers

    private func usable(_ asset: MediaAsset, as use: String) -> Bool {
        guard let problem = unusableReason(asset, as: use) else { return true }
        lastError = problem
        return false
    }

    private func unusableReason(_ asset: MediaAsset, as use: String) -> String? {
        guard asset.kind != .audio else {
            return "\"\(asset.name)\" is a sound file. Sound files are kept in the bin but cannot be used as \(use) yet."
        }
        guard isAvailable(asset) else { return Self.missingMessage(asset, what: "The file") }
        return nil
    }

    private static func missingMessage(_ asset: MediaAsset, what: String) -> String {
        "\(what) for \"\(asset.name)\" is missing or cannot be read: \(asset.path). Check that the drive or folder is connected, or remove it from the media bin and add it again."
    }

    private static func playbackMessage(_ asset: MediaAsset?, what: String, why: String? = nil) -> String {
        let name = asset.map { "\"\($0.name)\"" } ?? "chosen"
        let path = asset.map { " (\($0.path))" } ?? ""
        if let why {
            return "\(what) \(name)\(path) stopped working: \(why) The screens show the slide as usual; choose another item from the media bin."
        }
        return "\(what) \(name) could not be opened\(path). It may have been moved, deleted or damaged. The screens show the slide as usual; choose another item from the media bin."
    }

    private func layersChanged() {
        releaseRetainedHot()
        onLayersChange?(layers)
    }

    private func persist(key: String, _ what: String, _ operation: @escaping @Sendable () async throws -> Void) {
        writes.persist(key: key, what: what, operation)
    }

    private func attempt<T>(_ what: String, _ body: () async throws -> T) async -> T? {
        do { return try await body() } catch {
            lastError = WorkspaceModel.message(for: error, doing: what)
            return nil
        }
    }
}

// FIX-H items 1 and 6: the picture layer as the playlist runner sees it.
extension MediaModel: ForegroundPort {
    public func name(of assetID: UUID) -> String? { asset(assetID)?.name }
    public func isReadable(_ assetID: UUID) -> Bool { asset(assetID).map { isAvailable($0) } ?? false }
    public var foregroundAssetID: UUID? { layers.foreground?.selection.assetID }
}
