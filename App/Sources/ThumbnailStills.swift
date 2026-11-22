// FIX-I item 5: the pictures behind the words in slide thumbnails. A slide's own picture or video is drawn as ONE still frame, taken off the
// main thread by the same thumbnailer the media bin uses (an image-generator frame: no player, no decoder kept open), and cached by file
// path, modification date and size in a bounded cache. Nothing here is ever the live picture: the Live monitor keeps reading the media registry.
import AppKit
import CoreVideo
import Domain
import MediaEngine
import OperatorCore
import OutputEngine

/// A BGRA frame handed to the render queue. Immutable once made.
// @unchecked Sendable: the buffer is filled once, before it is published, and only read after that.
struct StillBuffer: @unchecked Sendable { let buffer: CVPixelBuffer }

final class ThumbnailStills: MediaFrameSource, @unchecked Sendable {
    // @unchecked Sendable: `cache`, `current` and `running` are touched only under `lock`.
    private let lock = NSLock()
    private var cache = StillCache<StillBuffer>(limit: 24)
    private var current: [UUID: StillCacheKey] = [:]
    private var running: [StillCacheKey: Task<StillBuffer?, Never>] = [:]
    /// How many stills were taken from a file (cache hits are not counted), for the cost measurement.
    private(set) var loadCount = 0
    private(set) var openedPlayers = 0       // always 0: kept so the measurement can state it

    /// The still for `media`, or nil while it is not loaded (or its file is gone). Called on the render queue; never waits.
    func currentPixelBuffer(for media: SceneMedia, layer: MediaLayerSlot) -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard let key = current[media.assetID] else { return nil }
        return cache.value(for: key)?.buffer
    }

    /// The identity of the still that is loaded for the asset now (path, modification date, size); nil before it has loaded.
    func loadedKey(for assetID: UUID) -> StillCacheKey? {
        lock.lock(); defer { lock.unlock() }
        guard let key = current[assetID], cache.value(for: key) != nil else { return nil }
        return key
    }

    /// Takes the still for `asset` if it is not cached for the file as it is now. True when a still is available afterwards.
    func ensure(_ asset: MediaAsset) async -> Bool {
        let access = MediaAccess.open(asset)
        let attributes = try? FileManager.default.attributesOfItem(atPath: access.url.path)
        access.stop()
        guard let attributes else { return false }                       // the file is gone: the missing-media state, no background
        let key = StillCacheKey(path: asset.path, modified: attributes[.modificationDate] as? Date, size: (attributes[.size] as? NSNumber)?.int64Value)
        let (hit, task) = claim(key: key, asset: asset)
        if hit { return true }
        let made = await task?.value
        finish(key: key, assetID: asset.id, made: made ?? nil)
        return (made ?? nil) != nil
    }

    /// Under the lock: a cached still (true), or the task that takes it (started now, or already running for another thumbnail).
    private func claim(key: StillCacheKey, asset: MediaAsset) -> (hit: Bool, task: Task<StillBuffer?, Never>?) {
        lock.withLock {
            if cache.value(for: key) != nil { current[asset.id] = key; return (true, nil) }
            if let existing = running[key] { return (false, existing) }
            loadCount += 1
            let task = Task.detached(priority: .utility) { () -> StillBuffer? in
                let access = MediaAccess.open(asset)
                defer { access.stop() }
                guard let image = try? await MediaThumbnailer.thumbnail(url: access.url, kind: asset.kind, maxPixelSize: 640) else { return nil }
                return Self.buffer(from: image)
            }
            running[key] = task
            return (false, task)
        }
    }

    private func finish(key: StillCacheKey, assetID: UUID, made: StillBuffer?) {
        lock.withLock {
            running[key] = nil
            if let made { cache.insert(made, for: key); current[assetID] = key }
        }
    }

    private static func buffer(from image: CGImage) -> StillBuffer? {
        let attributes: [CFString: Any] = [kCVPixelBufferMetalCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any]]
        var made: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &made) == kCVReturnSuccess,
              let buffer = made, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return StillBuffer(buffer: buffer)
    }
}
