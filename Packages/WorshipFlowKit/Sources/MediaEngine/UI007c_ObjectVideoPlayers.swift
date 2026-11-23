// UI-007c (SLIDE, MEDIA): the players behind video objects on a slide. A video object plays inside its frame while its slide is on a screen, looped and
// muted unless the operator says otherwise. Like the registry's two layer slots, the control side (main actor) says which clips should be open
// (`apply`), and the render side only looks a frame up (`pixelBuffer(for:)`): no file is opened and nothing is decoded on a render thread, and the
// decoding itself is AVFoundation's, on its own queues.
//
// At most `limit` clips are open at once, so a slide with many video objects cannot take the machine; the clips after the limit draw nothing and
// are reported in `skipped`.
import Foundation
import CoreVideo
import Domain

/// One clip a screen's scene asks for.
public struct ObjectVideoRequest: Sendable, Equatable, Hashable {
    public var assetID: UUID
    public var url: URL
    public var loops: Bool
    public var muted: Bool
    public var duration: Double?

    public init(assetID: UUID, url: URL, loops: Bool = true, muted: Bool = true, duration: Double? = nil) {
        self.assetID = assetID
        self.url = url
        self.loops = loops
        self.muted = muted
        self.duration = duration
    }
}

// @unchecked Sendable: all mutable state is guarded by `lock`; the sources are themselves thread-safe.
public final class ObjectVideoPlayers: @unchecked Sendable {
    /// Most clips open at once.
    public static let limit = 4

    private struct Open {
        var request: ObjectVideoRequest
        var source: VideoPlayerSource
    }

    private let lock = NSLock()
    private var open: [UUID: Open] = [:]
    private var failedIDs: Set<UUID> = []
    private var skippedIDs: Set<UUID> = []
    private var audioDeviceUID: String?
    private var availabilityChanged: (@Sendable (UUID) -> Void)?

    public init() {}

    /// Called when a clip fails to open or its player fails, may run on any thread.
    public func setOnAvailabilityChange(_ handler: (@Sendable (UUID) -> Void)?) {
        lock.lock(); availabilityChanged = handler; lock.unlock()
    }

    // MARK: Control side

    /// Makes the open clips match `requests`: opens what is new (looping and playing at once), reopens a clip whose loop or sound setting changed, and
    /// closes the rest. Cheap when nothing changed. Call it from the control side, never from a render thread.
    public func apply(_ requests: [ObjectVideoRequest]) {
        var wanted: [UUID: ObjectVideoRequest] = [:]
        var skipped: Set<UUID> = []
        for request in requests where wanted[request.assetID] == nil {
            if wanted.count < Self.limit { wanted[request.assetID] = request } else { skipped.insert(request.assetID) }
        }
        lock.lock()
        skippedIDs = skipped
        let current = open
        let device = audioDeviceUID
        lock.unlock()

        var closing: [VideoPlayerSource] = []
        var kept: [UUID: Open] = [:]
        for (id, held) in current {
            if let want = wanted[id], want == held.request { kept[id] = held } else { closing.append(held.source) }
        }
        var opened: [UUID: Open] = [:]
        var failed: Set<UUID> = []
        for (id, request) in wanted where kept[id] == nil {
            do {
                let source = try VideoPlayerSource(url: request.url, loops: request.loops, duration: request.duration, muted: request.muted)
                source.audioOutputDeviceUniqueID = device
                source.setOnHealthChange { [weak self] _ in self?.notify(id) }
                source.play()
                opened[id] = Open(request: request, source: source)
            } catch {
                failed.insert(id)
            }
        }
        lock.lock()
        open = kept.merging(opened) { a, _ in a }
        failedIDs = failedIDs.intersection(wanted.keys).subtracting(opened.keys).union(failed)       // a clip that opens now is no longer failed (REVIEW-5 L1)
        lock.unlock()
        for source in closing { source.stop() }
        for id in failed { notify(id) }
    }

    /// The sound device the clips that are not muted play to (the same one the foreground clip uses). Nil is the system default.
    public func setAudioDevice(uid: String?) {
        let value = (uid?.isEmpty ?? true) ? nil : uid
        lock.lock()
        audioDeviceUID = value
        let sources = open.values.map(\.source)
        lock.unlock()
        for source in sources { source.audioOutputDeviceUniqueID = value }
    }

    /// Closes everything.
    public func closeAll() {
        lock.lock()
        let sources = open.values.map(\.source)
        open.removeAll()
        failedIDs.removeAll()
        skippedIDs.removeAll()
        lock.unlock()
        for source in sources { source.stop() }
    }

    /// Closes the clip of an asset that left the bin.
    public func close(_ assetID: UUID) {
        lock.lock()
        let held = open.removeValue(forKey: assetID)
        failedIDs.remove(assetID)
        lock.unlock()
        held?.source.stop()
    }

    // MARK: Observation

    /// The asset ids that are open now.
    public var openAssetIDs: Set<UUID> { lock.lock(); defer { lock.unlock() }; return Set(open.keys) }
    /// Clips that could not be opened, or whose player failed after opening, or are not advancing.
    public var unavailableAssetIDs: Set<UUID> {
        lock.lock()
        var ids = failedIDs
        let sources = open.map { ($0.key, $0.value.source) }
        lock.unlock()
        for (id, source) in sources where source.playbackHealth != .healthy { ids.insert(id) }
        return ids
    }
    /// Clips that were asked for beyond `limit` and so are not drawn.
    public var skippedAssetIDs: Set<UUID> { lock.lock(); defer { lock.unlock() }; return skippedIDs }

    // MARK: Render side

    /// The newest decoded frame of a clip, or nil when there is none yet (still opening, no such clip, failed). Never opens a file and never waits.
    public func pixelBuffer(for assetID: UUID) -> CVPixelBuffer? {
        lock.lock()
        let source = open[assetID]?.source
        lock.unlock()
        return source?.latestPixelBuffer()
    }

    private func notify(_ id: UUID) {
        lock.lock(); let handler = availabilityChanged; lock.unlock()
        handler?(id)
    }
}
