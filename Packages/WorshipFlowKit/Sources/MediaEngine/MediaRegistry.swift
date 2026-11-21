// MEDIA-002: resolves a media-bin id to an open source, so a render thread can ask for "the current frame of
// asset X" without knowing about files, players or decoders.
//
// Control side (main actor): `register` the assets, then `apply` the `MediaLayers` state after every change.
// Render side (any thread): `currentPixelBuffer(for:layer:)`, a lookup that never opens a file or decodes.
import Foundation
import CoreVideo
import Domain

// @unchecked Sendable: all mutable state is guarded by `lock`; sources are themselves thread-safe.
public final class MediaRegistry: @unchecked Sendable {
    private struct Location {
        var kind: MediaKind
        var url: URL
        var duration: Double?
    }

    private struct Slot {
        var assetID: UUID
        var source: VideoPlayerSource?     // nil for a still
    }

    /// Stills decoded so far, least recently used dropped first. Stills the layers use are never dropped.
    private struct StillEntry {
        var buffer: CVPixelBuffer
        var lastUsed: Int
    }

    public static let defaultStillLimit = 8

    private let lock = NSLock()
    private let stillLimit: Int
    private let decodeQueue = DispatchQueue(label: "WorshipFlow.media.stills", qos: .userInitiated)
    private var locations: [UUID: Location] = [:]
    private var slots: [MediaLayerSlot: Slot] = [:]
    private var stills: [UUID: StillEntry] = [:]
    private var decoding: Set<UUID> = []
    private var failed: Set<UUID> = []
    private var useCounter = 0
    private var foregroundEnded: (@Sendable () -> Void)?
    private var foregroundVolume: Float = 1
    private var foregroundMuted = false

    public init(stillLimit: Int = MediaRegistry.defaultStillLimit) {
        self.stillLimit = max(2, stillLimit)
    }

    // MARK: Assets

    public func register(_ asset: MediaAsset) {
        register(id: asset.id, kind: asset.kind, url: URL(fileURLWithPath: asset.path), duration: asset.duration)
    }

    public func register(id: UUID, kind: MediaKind, url: URL, duration: Double? = nil) {
        lock.lock(); defer { lock.unlock() }
        locations[id] = Location(kind: kind, url: url, duration: duration)
        failed.remove(id)
    }

    /// Forgets an asset and closes whatever was open for it.
    public func unregister(_ id: UUID) {
        lock.lock()
        locations[id] = nil
        stills[id] = nil
        failed.remove(id)
        let closing = slots.filter { $0.value.assetID == id }.map(\.key)
        for slot in closing { slots[slot] = nil }
        lock.unlock()
    }

    /// Ids that were chosen but could not be opened or decoded (missing file, unsupported content).
    public var unavailableAssetIDs: Set<UUID> { lock.lock(); defer { lock.unlock() }; return failed }

    /// Called when a foreground clip reaches its end by the player's own report. May run on any thread; call
    /// `MediaLayers.tick` then, to take the foreground out of the scene.
    public func setOnForegroundEnded(_ handler: (@Sendable () -> Void)?) {
        lock.lock(); foregroundEnded = handler; lock.unlock()
    }

    /// MEDIA-001: the level of the foreground clip's audio (default output device). Applies to the open foreground
    /// source at once and to every one opened later, before it starts playing. A background is always muted.
    public func setForegroundAudio(volume: Float, muted: Bool) {
        let level = volume.isFinite ? min(1, max(0, volume)) : 0
        lock.lock()
        foregroundVolume = level
        foregroundMuted = muted
        let source = slots[.foreground]?.source
        lock.unlock()
        source?.volume = level
        source?.isMuted = muted
    }

    // MARK: Control side

    /// Makes the open sources match `layers`: opens what was newly chosen, closes what was dropped and hands each
    /// source its transport. Cheap when nothing changed. Call it from the control side, not from a render thread.
    public func apply(_ layers: MediaLayers, at now: Double = MediaClock.now()) {
        applySlot(.background, layers.background, at: now)
        applySlot(.foreground, layers.foreground, at: now)
        trimStills()
    }

    private func applySlot(_ slot: MediaLayerSlot, _ layer: MediaLayer?, at now: Double) {
        guard let layer else {
            lock.lock(); let old = slots.removeValue(forKey: slot); lock.unlock()
            old?.source?.stop()
            return
        }
        let id = layer.selection.assetID
        lock.lock()
        let existing = slots[slot]
        let location = locations[id]
        lock.unlock()

        if let existing, existing.assetID == id {
            existing.source?.apply(layer.transport, at: now)
            return
        }
        existing?.source?.stop()
        guard let location, location.kind == layer.selection.kind else {
            markFailed(id, closing: slot)
            return
        }
        switch location.kind {
        case .video:
            do {
                lock.lock(); let level = foregroundVolume, silent = foregroundMuted; lock.unlock()
                let source = try VideoPlayerSource(url: location.url, loops: layer.transport.loops,
                                                   duration: layer.selection.duration ?? location.duration,
                                                   muted: slot == .background || silent)
                if slot == .foreground { source.volume = level }     // before it plays: no burst at full volume
                if slot == .foreground {
                    source.setOnEnded { [weak self] in self?.notifyForegroundEnded() }
                }
                lock.lock(); slots[slot] = Slot(assetID: id, source: source); failed.remove(id); lock.unlock()
                source.apply(layer.transport, at: now)
            } catch {
                markFailed(id, closing: slot)
            }
        case .image:
            lock.lock(); slots[slot] = Slot(assetID: id, source: nil); lock.unlock()
            requestStill(id, url: location.url)
        case .audio:
            markFailed(id, closing: slot)
        }
    }

    private func markFailed(_ id: UUID, closing slot: MediaLayerSlot) {
        lock.lock(); slots[slot] = nil; failed.insert(id); lock.unlock()
    }

    private func notifyForegroundEnded() {
        lock.lock(); let handler = foregroundEnded; lock.unlock()
        handler?()
    }

    /// The source playing in `slot`, for diagnostics and tests. Nil for a still or an empty slot.
    public func videoSource(in slot: MediaLayerSlot) -> VideoPlayerSource? {
        lock.lock(); defer { lock.unlock() }
        return slots[slot]?.source
    }

    /// Closes everything. Registered assets stay registered.
    public func closeAll() {
        lock.lock()
        let open = slots.values.compactMap(\.source)
        slots.removeAll()
        stills.removeAll()
        failed.removeAll()
        lock.unlock()
        for source in open { source.stop() }
    }

    // MARK: Render side

    /// The frame to draw for `media` in `layer`, or nil when there is none yet (still decoding, player not ready,
    /// file unavailable, or the media is not what that layer currently holds). Never opens a file and never waits.
    public func currentPixelBuffer(for media: SceneMedia, layer: MediaLayerSlot) -> CVPixelBuffer? {
        lock.lock()
        guard let slot = slots[layer], slot.assetID == media.assetID else { lock.unlock(); return nil }
        switch media {
        case .video:
            let source = slot.source
            lock.unlock()
            return source?.latestPixelBuffer()
        case .image:
            useCounter += 1
            let counter = useCounter
            defer { lock.unlock() }
            guard var entry = stills[media.assetID] else { return nil }
            entry.lastUsed = counter
            stills[media.assetID] = entry
            return entry.buffer
        }
    }

    // MARK: Stills

    private func requestStill(_ id: UUID, url: URL) {
        lock.lock()
        if stills[id] != nil || decoding.contains(id) { lock.unlock(); return }
        decoding.insert(id)
        lock.unlock()
        decodeQueue.async { [weak self] in
            let buffer = StillImageLoader.pixelBuffer(url: url)
            guard let self else { return }
            self.lock.lock()
            self.decoding.remove(id)
            if let buffer, self.locations[id] != nil {
                self.useCounter += 1
                self.stills[id] = StillEntry(buffer: buffer, lastUsed: self.useCounter)
                self.failed.remove(id)
            } else if buffer == nil {
                self.failed.insert(id)
            }
            self.lock.unlock()
        }
    }

    /// Keeps the number of decoded stills bounded. A still held by a layer is never dropped.
    private func trimStills() {
        lock.lock(); defer { lock.unlock() }
        let held = Set(slots.values.map(\.assetID))
        while stills.count > stillLimit {
            guard let victim = stills.filter({ !held.contains($0.key) }).min(by: { $0.value.lastUsed < $1.value.lastUsed }) else { return }
            stills[victim.key] = nil
        }
    }

    /// Number of decoded stills held (tests and diagnostics).
    public var decodedStillCount: Int { lock.lock(); defer { lock.unlock() }; return stills.count }
}
