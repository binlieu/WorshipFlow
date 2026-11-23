// UI-007d (MEDIA, CUE-33): the markers of the clips in the media bin, and the observer that runs a marker's actions when LIVE playback crosses it.
//
// - Media mode lists, adds (at the playhead), renames, moves and deletes markers; Cues mode edits their actions. Both use this model, which
//   keeps what the library holds (`LibraryStore`'s `mediaMarker` table, schema v15).
// - While a clip that has markers plays on a live layer, an observer (a fast timer in the app, a fake in tests) takes a `PlaybackSample` of each
//   layer and hands it to a `MarkerFeed`. Every marker reached becomes a `MarkerFiring` that the app submits to the Cues command path. The
//   observer exists only while that is the case: nothing ticks while idle, while a clip without markers plays, or while the screens are stopped.
// - A clip that is only previewed in the bin never reaches this model: it reads the live layers only.
// Foundation, Observation and the package's own modules only; the timer lives behind `MarkerScheduling`.
import Foundation
import Observation
import Domain
import CueEngine
import Persistence

/// What the observer needs from a timer, so a test can run without one.
@MainActor
public protocol MarkerScheduling: AnyObject {
    var isRunning: Bool { get }
    /// Calls `handler` every `interval` seconds until `stop`. Does nothing when already running.
    func start(interval: TimeInterval, _ handler: @escaping @MainActor () -> Void)
    func stop()
}

/// The app's timer: a repeating `Timer` on the main run loop, in the common modes so it keeps running while a menu or a drag is open.
@MainActor
public final class TimerMarkerScheduler: MarkerScheduling {
    private var timer: Timer?
    public init() {}
    public var isRunning: Bool { timer != nil }

    public func start(interval: TimeInterval, _ handler: @escaping @MainActor () -> Void) {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { handler() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// A marker that live playback reached: what the Cues command path runs.
public struct MarkerFiring: Sendable, Equatable {
    public var assetID: UUID
    public var clipName: String
    public var markerID: UUID
    public var markerName: String?
    /// The marker's time in the clip, seconds.
    public var time: Double
    public var actions: [CueAction]

    public init(assetID: UUID, clipName: String, markerID: UUID, markerName: String?, time: Double, actions: [CueAction]) {
        self.assetID = assetID
        self.clipName = clipName
        self.markerID = markerID
        self.markerName = markerName
        self.time = time
        self.actions = actions
    }

    /// "Lower third on" (or "marker at 00:12.5" without a name), then the clip, as the activity list writes it.
    public var summary: String {
        let name = markerName.map { "\"\($0)\"" } ?? "marker"
        return "\(name) at \(MediaTimeText.format(time)) in \(clipName): \(actions.count) action\(actions.count == 1 ? "" : "s")"
    }
}

/// The stored actions text of a marker, as cue actions.
public enum MarkerActions {
    /// Nil when the text is not readable as a list of actions (the marker then runs nothing and says so).
    public static func decode(_ text: String) -> [CueAction]? {
        (try? JSONDecoder().decode(CueActionList.self, from: Data(text.utf8)))?.actions
    }

    /// Why these actions may not be a marker's: one that moves the show (directly or through a macro) could advance it on every pass of a loop.
    /// The same rule as for slide actions, in the words of a marker. Nil when they are allowed.
    public static func refusal(for actions: [CueAction], library: MacroLibrary) -> String? {
        SlideActionSet.validate(actions, library: library).first.map {
            $0.message.replacingOccurrences(of: "A slide action", with: "A marker's action")
                .replacingOccurrences(of: "so a slide could then advance itself", with: "so a clip could then advance the show by itself")
                .replacingOccurrences(of: "a slide could then advance itself", with: "a clip could then advance the show by itself")
        }
    }

    public static func encode(_ actions: [CueAction]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(CueActionList(actions: actions)) else { return nil }
        return MediaMarker.validatedActions(String(decoding: data, as: UTF8.self))
    }
}

@MainActor
@Observable
public final class MediaMarkerModel {
    /// Markers by clip, each list in time order. Loaded on demand and when the bin changes.
    public private(set) var markersByAsset: [UUID: [MediaMarker]] = [:]
    /// True while the observer is running (shown nowhere; the tests and the app's ticker policy read it).
    public var isObserving: Bool { scheduler.isRunning }

    /// How often the observer looks at a live clip: a marker runs within this much of its time (plus the player's own lag).
    public static let observerInterval: TimeInterval = 0.05

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let media: MediaModel
    @ObservationIgnored private let scheduler: any MarkerScheduling
    @ObservationIgnored private var sampleSource: (@MainActor (MediaLayerSlot) -> PlaybackSample?)?
    @ObservationIgnored private var onFire: @MainActor (MarkerFiring) -> Void
    @ObservationIgnored private var feed = MarkerFeed()
    @ObservationIgnored private var loading: Set<UUID> = []

    /// - Parameters:
    ///   - sample: how a live layer is looked at. Nil asks the media model (its transports and its clock); a test injects the position.
    ///   - fire: called on the main actor for each marker reached; the app submits it to the Cues command path.
    public init(store: LibraryStore, media: MediaModel, scheduler: any MarkerScheduling,
                sample: (@MainActor (MediaLayerSlot) -> PlaybackSample?)? = nil,
                fire: @escaping @MainActor (MarkerFiring) -> Void) {
        self.store = store
        self.media = media
        self.scheduler = scheduler
        self.sampleSource = sample
        self.onFire = fire
        media.onPlaybackChange = { [weak self] in self?.refresh() }
        media.onPlaybackWillChange = { [weak self] in self?.lastLook() }
    }

    public func setFire(_ handler: @escaping @MainActor (MarkerFiring) -> Void) { onFire = handler }
    public func setSample(_ source: (@MainActor (MediaLayerSlot) -> PlaybackSample?)?) { sampleSource = source }

    // MARK: Reading

    public func markers(for assetID: UUID) -> [MediaMarker] { markersByAsset[assetID] ?? [] }

    /// What the marker runs; empty when it runs nothing or its stored text cannot be read.
    public func actions(of markerID: UUID) -> [CueAction] {
        guard let marker = markersByAsset.values.lazy.flatMap({ $0 }).first(where: { $0.id == markerID }) else { return [] }
        return MarkerActions.decode(marker.actions) ?? []
    }

    /// True when the stored actions text of the marker cannot be read (written by a newer version, or damaged): it runs nothing.
    public func actionsAreUnreadable(_ markerID: UUID) -> Bool {
        guard let marker = markersByAsset.values.lazy.flatMap({ $0 }).first(where: { $0.id == markerID }) else { return false }
        return MarkerActions.decode(marker.actions) == nil
    }

    public func load(_ assetID: UUID) async {
        guard !loading.contains(assetID) else { return }
        loading.insert(assetID)
        defer { loading.remove(assetID) }
        do { markersByAsset[assetID] = try await store.mediaMarkers(forAsset: assetID) }
        catch StoreError.notFound { markersByAsset[assetID] = nil }
        catch { media.report(WorkspaceModel.message(for: error, doing: "read the markers of the clip")) }
        changed(assetID)
    }

    /// Reads the markers of every video in `assets` that has none loaded, and forgets those of clips that left the bin.
    public func syncAssets(_ assets: [MediaAsset]) async {
        let ids = Set(assets.map(\.id))
        for gone in markersByAsset.keys where !ids.contains(gone) { markersByAsset[gone] = nil }
        for asset in assets where asset.kind == .video && markersByAsset[asset.id] == nil { await load(asset.id) }
        refresh()
    }

    // MARK: Editing (Media mode adds, renames, moves and deletes; Cues mode sets the actions)

    @discardableResult
    public func add(to assetID: UUID, at time: Double, name: String? = nil) async -> MediaMarker? {
        guard let added = await attempt("add the marker", { try await self.store.addMediaMarker(forAsset: assetID, time: time, name: name) }) else { return nil }
        await load(assetID)
        return added
    }

    public func move(_ id: UUID, to time: Double) async {
        guard let marker = find(id), await attempt("move the marker", { try await self.store.moveMediaMarker(id: id, to: time) }) != nil else { return }
        await load(marker.assetID)
    }

    public func rename(_ id: UUID, to name: String?) async {
        guard let marker = find(id), await attempt("rename the marker", { try await self.store.renameMediaMarker(id: id, to: name) }) != nil else { return }
        await load(marker.assetID)
    }

    public func delete(_ id: UUID) async {
        guard let marker = find(id) else { return }
        guard await attempt("delete the marker", { try await self.store.deleteMediaMarker(id: id) }) != nil else { return }
        await load(marker.assetID)
    }

    /// Stores the actions the marker runs. An action that moves the show is refused, directly or through a macro (the slide-actions rule: a clip
    /// that loops would advance the show on every pass); nothing is written then and the reason is returned (it is for the editor that asked, so
    /// it is not put on the Media mode's banner). Nil when the actions were saved (a storage failure is shown on the banner and also returns nil).
    @discardableResult
    public func setActions(_ actions: [CueAction], for id: UUID, macros: MacroLibrary = MacroLibrary()) async -> String? {
        guard let marker = find(id) else { return "That marker is no longer there." }
        if let why = MarkerActions.refusal(for: actions, library: macros) { return why }
        guard let text = MarkerActions.encode(actions) else { return "These actions could not be stored." }
        guard await attempt("save the marker's actions", { try await self.store.setMediaMarkerActions(id: id, actions: text) }) != nil else { return nil }
        await load(marker.assetID)
        return nil
    }

    private func find(_ id: UUID) -> MediaMarker? { markersByAsset.values.lazy.flatMap { $0 }.first { $0.id == id } }

    private func attempt<T>(_ what: String, _ body: () async throws -> T) async -> T? {
        do { return try await body() } catch {
            media.report(WorkspaceModel.message(for: error, doing: what))
            return nil
        }
    }

    // MARK: Observing live playback

    /// A marker list changed: the layers that play the clip are told, and the observer is started or stopped as needed.
    private func changed(_ assetID: UUID) {
        for slot in MediaLayerSlot.allCases {
            guard let live = lookAt(slot), live.assetID == assetID else { continue }
            feed.markersChanged(slot, markers: playbackMarkers(assetID))
        }
        refresh()
    }

    private func playbackMarkers(_ assetID: UUID) -> [PlaybackMarker] {
        markers(for: assetID).map { PlaybackMarker(id: $0.id, time: $0.time, actions: MarkerActions.decode($0.actions) ?? []) }
    }

    private func lookAt(_ slot: MediaLayerSlot) -> PlaybackSample? {
        if let sampleSource { return sampleSource(slot) }
        return media.playbackSample(slot)
    }

    /// The observer is needed exactly while a layer plays, live, a clip that has markers.
    public var needsObserver: Bool {
        MediaLayerSlot.allCases.contains { slot in
            guard let s = lookAt(slot), s.isPlaying else { return false }
            return !markers(for: s.assetID).isEmpty
        }
    }

    /// Starts or stops the observer to match `needsObserver`. Called when the layers, the show state or the markers change.
    public func refresh() {
        if needsObserver {
            scheduler.start(interval: Self.observerInterval) { [weak self] in self?.tick() }
        } else if scheduler.isRunning {
            scheduler.stop()
            // A layer that is only paused (it has markers and its clock is still) keeps its place, so resuming it does not start a new pass and
            // run a marker it just ran (L5). Every other layer is forgotten.
            for slot in MediaLayerSlot.allCases {
                if let s = lookAt(slot), !s.isPlaying, !markers(for: s.assetID).isEmpty { continue }
                feed.forget(slot)
            }
        }
    }

    /// FIX-W (M1): one more look, just before a pause, a Stop or the clip's end changes the layers. Only while the observer runs; nothing ticks otherwise.
    private func lastLook() {
        guard scheduler.isRunning else { return }
        tick()
    }

    /// One look at each live layer. Every marker reached is handed to the fire callback.
    public func tick() {
        for slot in MediaLayerSlot.allCases {
            let sample = lookAt(slot)
            let list = sample.map { playbackMarkers($0.assetID) } ?? []
            let reached = feed.poll(slot, sample: list.isEmpty ? nil : sample, markers: list)
            guard let sample, !reached.isEmpty else { continue }
            let name = media.asset(sample.assetID)?.name ?? "clip"
            for marker in reached {
                let stored = markers(for: sample.assetID).first { $0.id == marker.id }
                onFire(MarkerFiring(assetID: sample.assetID, clipName: name, markerID: marker.id, markerName: stored?.name,
                                    time: marker.time, actions: marker.actions))
            }
        }
    }
}
