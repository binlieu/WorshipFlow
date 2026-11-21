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

    public var visibleAssets: [MediaAsset] {
        guard let kindFilter else { return assets }
        return assets.filter { $0.kind == kindFilter }
    }

    public func asset(_ id: UUID) -> MediaAsset? { assets.first { $0.id == id } }

    /// Called on the main actor after the bin's contents change (add, rename, remove, load).
    @ObservationIgnored public var onAssetsChange: (@MainActor ([MediaAsset]) -> Void)?
    /// Called on the main actor after every change to the layers, so the app can open and close players and publish scenes.
    @ObservationIgnored public var onLayersChange: (@MainActor (MediaLayers) -> Void)?
    /// Called on the main actor after the volume or mute changed.
    @ObservationIgnored public var onAudioChange: (@MainActor (_ volume: Float, _ muted: Bool) -> Void)?

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
        onAssetsChange?(assets)
        guard let text = try? await store.state(for: Self.backgroundKey), let id = UUID(uuidString: text) else { return }
        guard let asset = asset(id) else { return }     // the asset was removed: nothing to restore
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

    private func reload() async {
        guard let all = await attempt("read the media bin", { try await self.store.mediaAssets(kind: nil) }) else { return }
        assets = all
        onAssetsChange?(assets)
    }

    // MARK: Background

    /// Starts the item looping behind the slides. Persisted, so the next launch brings it back.
    public func setBackground(_ id: UUID) {
        guard let asset = asset(id), usable(asset, as: "a background") else { return }
        if layers.background?.selection == MediaSelection(asset: asset) { return }
        layers.setBackground(MediaSelection(asset: asset), at: now())
        persistBackground(asset.id)
        layersChanged()
    }

    public func clearBackground() {
        let had = layers.background != nil
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
        guard let asset = asset(id), usable(asset, as: "a video or picture on the screens") else { return }
        guard showIsLive else {
            lastError = "Take a slide live first, then play \"\(asset.name)\": the screens are stopped, so nobody would see it."
            return
        }
        layers.startForeground(MediaSelection(asset: asset), at: now())
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
        guard layers.foreground != nil else { return }
        layers.stopForeground()
        layersChanged()
    }

    /// Ends a clip that has finished. Returns true when something changed (the words come back on the screens).
    @discardableResult
    public func tick(now at: Double? = nil) -> Bool {
        guard layers.tick(at: at ?? now()) else { return false }
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
        layers.stopForeground()
        layersChanged()
        return true
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
    }

    /// R17: the screens were closed. The clip playing over the slide stops (its sound with it); the background stays
    /// chosen, so it plays again when the screens open.
    public func screensClosed() { stopForeground() }

    public func setVolume(_ value: Double) {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        guard v != volume else { return }
        volume = v
        onAudioChange?(Float(volume), isMuted || isMutedByBlackout)
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

    // MARK: Helpers

    private func usable(_ asset: MediaAsset, as use: String) -> Bool {
        guard asset.kind != .audio else {
            lastError = "\"\(asset.name)\" is a sound file. Sound files are kept in the bin but cannot be used as \(use) yet."
            return false
        }
        guard isAvailable(asset) else {
            lastError = Self.missingMessage(asset, what: "The file")
            return false
        }
        return true
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

    private func layersChanged() { onLayersChange?(layers) }

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
