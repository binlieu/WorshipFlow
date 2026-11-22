// FIX-J item 2 (UI-005h): the text cache's pieces. A least-recently-used cache that gives up one entry at a time, and the store of rasters
// (and fit decisions) that the selected slide's text is prepared into ahead of Go Live, so the first live frame of any output finds them.
import Foundation
import Domain

/// A bounded cache that, when full, drops the least recently used entry, one entry per insert (never all at once).
struct LRUCache<Key: Hashable, Value> {
    // A class, so that marking an entry as used is one field write, not a second hash and dictionary store on every frame.
    private final class Slot { let value: Value; var used: Int; init(value: Value, used: Int) { self.value = value; self.used = used } }
    private var slots: [Key: Slot] = [:]
    private var clock = 0
    let limit: Int
    /// Entries dropped since the cache was made (for tests and diagnostics).
    private(set) var evictions = 0

    init(limit: Int) { self.limit = max(1, limit) }

    var count: Int { slots.count }

    mutating func value(for key: Key) -> Value? {
        guard let slot = slots[key] else { return nil }
        clock += 1
        slot.used = clock
        return slot.value
    }

    /// Stores `value`. When the cache is full and `key` is new, the entry used longest ago goes first. Returns how many entries were dropped (0 or 1).
    @discardableResult
    mutating func insert(_ value: Value, for key: Key) -> Int {
        var dropped = 0
        if slots[key] == nil, slots.count >= limit, let victim = slots.min(by: { $0.value.used < $1.value.used })?.key {
            slots[victim] = nil
            evictions += 1
            dropped = 1
        }
        clock += 1
        slots[key] = Slot(value: value, used: clock)
        return dropped
    }

    mutating func removeAll() { slots.removeAll(keepingCapacity: true) }
}

/// What a text bitmap is made from: the words, the style at the output's size, the width it wraps at and its alignment.
struct TextRasterKey: Hashable {
    let text: String
    let style: TextStyle
    let maxWidth: Int
    let alignment: TextAlignment
}

struct FitLayerKey: Hashable {
    let text: String
    let style: TextStyle
    let frame: NormalizedRect
    let alignment: TextAlignment
    let inPlate: Bool
    let floor: Double
}

/// What a fit decision depends on: the words and blocks, the plate, and the aspect ratio (as the width at the 1080-line reference).
struct FitKey: Hashable {
    let layers: [FitLayerKey]
    let plate: TextPlate?
    let referenceWidth: Int
}

/// Rasters and fit decisions prepared ahead of time by `TextWarmer`, shared by every compositor in the process (an output's own compositor takes
/// a text bitmap from here instead of running Core Text on its first frame). Only the warmer puts anything in: an output's own frames do not, so
/// a compositor that was never warmed behaves exactly as before. Bounded by size, least recently used first. Safe from any thread.
// @unchecked Sendable: every access to the stores is under `lock`.
final class SharedTextStore: @unchecked Sendable {
    static let shared = SharedTextStore()

    private struct Entry { let raster: RasterizedText; let bytes: Int; var used: Int }
    private let lock = NSLock()
    private var rasters: [TextRasterKey: Entry] = [:]
    private var bytes = 0
    private var clock = 0
    private var fits = LRUCache<FitKey, TextFitStatus>(limit: 256)
    static let byteLimit = 192 * 1024 * 1024

    func raster(for key: TextRasterKey) -> RasterizedText? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = rasters[key] else { return nil }
        clock += 1
        entry.used = clock
        rasters[key] = entry
        return entry.raster
    }

    func put(_ raster: RasterizedText, for key: TextRasterKey) {
        let size = raster.pixels.count
        guard size <= Self.byteLimit / 4 else { return }
        lock.lock(); defer { lock.unlock() }
        if let old = rasters[key] { bytes -= old.bytes }
        clock += 1
        rasters[key] = Entry(raster: raster, bytes: size, used: clock)
        bytes += size
        while bytes > Self.byteLimit, let victim = rasters.min(by: { $0.value.used < $1.value.used })?.key {
            bytes -= rasters[victim]?.bytes ?? 0
            rasters[victim] = nil
        }
    }

    func fit(for key: FitKey) -> TextFitStatus? {
        lock.lock(); defer { lock.unlock() }
        return fits.value(for: key)
    }

    func put(_ status: TextFitStatus, for key: FitKey) {
        lock.lock(); defer { lock.unlock() }
        fits.insert(status, for: key)
    }
}

/// Prepares the text of scenes before they go live: runs the fit and the Core Text layout and drawing for each scene at the output's size on a
/// background queue, into the store every compositor reads. The app calls it for the selected (Preview) slide of each screen, so the first
/// live frame is as warm as the later ones. Nothing waits for it: Go Live never blocks on it, and a frame that comes first simply does the work itself.
public enum TextWarmer {
    /// `scenes`: each scene with the pixel size of the output it will be drawn on.
    public static func warm(scenes: [(SceneDescription, Int, Int)]) async {
        guard !scenes.isEmpty else { return }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                warmNow(scenes: scenes)
                continuation.resume()
            }
        }
    }

    /// The same, on the calling thread (a background queue: never the main thread).
    public static func warmNow(scenes: [(SceneDescription, Int, Int)]) {
        guard !scenes.isEmpty, let compositor = try? Compositor() else { return }
        compositor.publishesRasters = true
        for (scene, width, height) in scenes where width > 0 && height > 0 {
            _ = try? compositor.layoutReport(scene: scene, width: width, height: height)
        }
    }
}
