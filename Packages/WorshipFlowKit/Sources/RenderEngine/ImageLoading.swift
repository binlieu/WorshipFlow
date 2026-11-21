// OUT-003: decoding of image files for the compositor. ImageIO only; no Metal here.
// Decoded pixels are premultiplied BGRA in sRGB, so they can be uploaded to a `.bgra8Unorm` texture and blended
// with the same premultiplied "over" as text.
import Foundation
import CoreGraphics
import ImageIO

struct DecodedImage: Sendable {
    let width: Int
    let height: Int
    /// Premultiplied BGRA, top row first, tightly packed.
    let pixels: [UInt8]
}

enum ImageDecoder {
    /// Longest side kept after decoding. Larger images are scaled down by ImageIO, which bounds memory per image.
    static let maxDimension = 4096

    /// Test seam (R7): lets a test see which thread asks the file system for a modification date.
    nonisolated(unsafe) static var statProbe: (@Sendable (String) -> Void)?

    static func modificationDate(of path: String) -> Date? {
        statProbe?(path)
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func decode(path: String) -> DecodedImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        var longest = maxDimension
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 {
            longest = min(maxDimension, max(w, h))
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))   // converts to sRGB, premultiplies
            return true
        }
        return drawn ? DecodedImage(width: width, height: height, pixels: pixels) : nil
    }
}

/// Result of one load attempt. `modified` is read before decoding, so a change during the decode is noticed later.
struct ImageLoadOutcome: Sendable {
    let path: String
    let modified: Date?
    let image: DecodedImage?
    /// A re-check found the file exactly as the cached texture already has it (no new pixels, nothing to upload).
    var unchanged = false
}

/// Process-wide store of decoded images (R10): one decode per file, however many screens show it. Entries are
/// pixels, not textures, so it is device independent; each compositor uploads its own texture from them.
/// Bounded: the least recently used go first.
// @unchecked Sendable: every stored property is guarded by `lock`.
final class SharedImageStore: @unchecked Sendable {
    static let shared = SharedImageStore()
    static let entryLimit = 32
    static let byteLimit = 192 * 1024 * 1024
    /// An image that was warmed for a scene about to go live is the last to be evicted for this long (seconds).
    static let pinDuration = 60.0

    private struct Entry {
        var image: DecodedImage
        var modified: Date?
        var lastUsed: Int
        var bytes: Int
        /// Uptime until which the entry is the last to be evicted (set by warming).
        var pinnedUntil = 0.0
    }
    private final class Gate {
        let lock = NSLock()
        var users = 0
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var gates: [String: Gate] = [:]
    private var counter = 0
    private var bytes = 0
    private var decodes = 0

    /// Files decoded by this store so far (tests and diagnostics).
    var decodeCount: Int { lock.lock(); defer { lock.unlock() }; return decodes }
    var entryCount: Int { lock.lock(); defer { lock.unlock() }; return entries.count }

    /// Whatever is held for `path`, without touching the file system. Safe on a render thread.
    func peek(_ path: String) -> (image: DecodedImage, modified: Date?)? {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[path] else { return nil }
        counter += 1
        e.lastUsed = counter
        entries[path] = e
        return (e.image, e.modified)
    }

    /// The decoded image for `path`, decoding only when nothing current is held. Reads the file system: never call it
    /// from a render thread. Concurrent calls for the same path wait for one decode; different paths run in parallel.
    /// `decoded` is false when the held decode was current and served as it was.
    /// `willDecode` runs just before a decode starts, so a caller's counter is up to date before the image can be seen.
    func load(_ path: String, pin: Bool = false, willDecode: () -> Void = {}) -> (outcome: ImageLoadOutcome, decoded: Bool) {
        let gate = enter(path)
        defer { leave(path, gate) }
        let modified = ImageDecoder.modificationDate(of: path)
        lock.lock()
        if let modified, var e = entries[path], e.modified == modified {
            counter += 1
            e.lastUsed = counter
            if pin { e.pinnedUntil = ProcessInfo.processInfo.systemUptime + Self.pinDuration }
            entries[path] = e
            lock.unlock()
            return (ImageLoadOutcome(path: path, modified: modified, image: e.image), false)
        }
        lock.unlock()
        willDecode()
        let image = ImageDecoder.decode(path: path)
        lock.lock()
        decodes += 1
        if let old = entries[path] { bytes -= old.bytes; entries[path] = nil }
        if let image {
            counter += 1
            let size = image.width * image.height * 4
            entries[path] = Entry(image: image, modified: modified, lastUsed: counter, bytes: size,
                                  pinnedUntil: pin ? ProcessInfo.processInfo.systemUptime + Self.pinDuration : 0)
            bytes += size
            let nowUp = ProcessInfo.processInfo.systemUptime
            while entries.count > Self.entryLimit || bytes > Self.byteLimit, entries.count > 1,
                  let victim = entries.min(by: { ($0.value.pinnedUntil > nowUp ? 1 : 0, $0.value.lastUsed) < ($1.value.pinnedUntil > nowUp ? 1 : 0, $1.value.lastUsed) }),
                  victim.key != path {
                bytes -= victim.value.bytes
                entries[victim.key] = nil
            }
        }
        lock.unlock()
        return (ImageLoadOutcome(path: path, modified: modified, image: image), true)
    }

    private func enter(_ path: String) -> Gate {
        lock.lock()
        let gate = gates[path] ?? Gate()
        gates[path] = gate
        gate.users += 1
        lock.unlock()
        gate.lock.lock()
        return gate
    }

    private func leave(_ path: String, _ gate: Gate) {
        gate.lock.unlock()
        lock.lock()
        gate.users -= 1
        if gate.users == 0 { gates[path] = nil }
        lock.unlock()
    }
}

/// Thread-safe hand-off between background loads and the render thread, plus the counters the tests and the
/// operator window read.
// @unchecked Sendable: every stored property is guarded by `lock`.
final class ImageLoadCenter: @unchecked Sendable {
    private let lock = NSLock()
    private var finished: [ImageLoadOutcome] = []
    private var pending: Set<String> = []
    private var decodes = 0
    private var unavailable: Set<String> = []
    private let store: SharedImageStore

    init(store: SharedImageStore = .shared) { self.store = store }

    /// Files this center had to decode itself (a file another screen already decoded does not count).
    var decodeCount: Int { lock.lock(); defer { lock.unlock() }; return decodes }
    var unavailablePaths: Set<String> { lock.lock(); defer { lock.unlock() }; return unavailable }

    /// Loads on the calling thread. Used by offscreen rendering; the live path uses `requestInBackground`.
    func decodeNow(_ path: String) -> ImageLoadOutcome {
        let (outcome, _) = store.load(path, willDecode: countDecode)
        record(outcome)
        return outcome
    }

    /// Wraps what the shared store already holds as an outcome, without touching the file system. Nil when it holds nothing.
    func cachedOutcome(_ path: String) -> ImageLoadOutcome? {
        guard let hit = store.peek(path) else { return nil }
        lock.lock(); unavailable.remove(path); lock.unlock()
        return ImageLoadOutcome(path: path, modified: hit.modified, image: hit.image)
    }

    /// Loads (or re-checks) `path` on a background queue. `since` is the modification date of the texture the caller
    /// already has: a file that still has that date comes back as `unchanged`, with no pixels.
    func requestInBackground(_ path: String, since: Date? = nil) {
        lock.lock()
        guard pending.insert(path).inserted else { lock.unlock(); return }
        lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            let (loaded, _) = store.load(path, willDecode: countDecode)
            var outcome = loaded
            if let since, loaded.image != nil, loaded.modified == since { outcome.unchanged = true }
            lock.lock()
            if loaded.image == nil { unavailable.insert(path) } else { unavailable.remove(path) }
            pending.remove(path)
            finished.append(outcome)
            lock.unlock()
        }
    }

    private func countDecode() { lock.lock(); decodes += 1; lock.unlock() }

    private func record(_ outcome: ImageLoadOutcome) {
        lock.lock()
        if outcome.image == nil { unavailable.insert(outcome.path) } else { unavailable.remove(outcome.path) }
        lock.unlock()
    }

    func takeFinished() -> [ImageLoadOutcome] {
        lock.lock(); defer { lock.unlock() }
        guard !finished.isEmpty else { return [] }
        let out = finished
        finished = []
        return out
    }
}
