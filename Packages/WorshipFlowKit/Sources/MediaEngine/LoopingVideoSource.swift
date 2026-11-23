// OUT-001: seamless looping video source. AVPlayerLooper decodes on AVFoundation's own queues; an
// AVPlayerItemVideoOutput hands the newest decoded BGRA frame to whichever output asks for it.
import Foundation
import AVFoundation
import CoreVideo
import Metal

public enum MediaError: Error, Sendable, Equatable {
    case fileNotFound(String)
    case noTextureCache
}

/// Thread-safe. Several outputs may call `latestPixelBuffer()` concurrently from their render threads.
// @unchecked Sendable: AVQueuePlayer/AVPlayerLooper are only mutated in init, start() and stop() (callers
// serialise those on the main actor); everything read from render threads goes through `lock`.
public final class LoopingVideoSource: @unchecked Sendable {
    public let url: URL
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    private let lock = NSLock()
    private var output: AVPlayerItemVideoOutput?
    private var outputItem: AVPlayerItem?
    private var latest: CVPixelBuffer?
    private var observation: NSKeyValueObservation?
    private var delivered = 0
    private var itemChanges: [Double] = []   // OUT-002d: media-clock times the current item was replaced after the first

    public init(url: URL) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw MediaError.fileNotFound(url.path) }
        self.url = url
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
        // The looper swaps the current item at every loop boundary; keep one output on whichever item is current.
        observation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            self?.attachOutput(to: player.currentItem)
        }
    }

    deinit {
        observation?.invalidate()
        player.pause()
        looper.disableLooping()
    }

    private func attachOutput(to item: AVPlayerItem?) {
        lock.lock()
        defer { lock.unlock() }
        if let old = output, let oldItem = outputItem { oldItem.remove(old) }
        // OUT-002d: the looper replaces the current item at each loop boundary; remember when (bounded), for the soak report.
        if outputItem != nil, item != nil, itemChanges.count < 2_000 { itemChanges.append(CACurrentMediaTime()) }
        output = nil
        outputItem = nil
        guard let item else { return }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        out.suppressesPlayerRendering = true
        item.add(out)
        output = out
        outputItem = item
    }

    /// Player state for diagnostics (rate, time control status, current item status, error).
    public var diagnostics: String {
        let item = player.currentItem
        let err: Error? = item?.error ?? player.error ?? looper.error
        let status = item.map { String($0.status.rawValue) } ?? "no item"
        let time = String(format: "%.2f", player.currentTime().seconds)
        return "rate \(player.rate), control \(player.timeControlStatus.rawValue), item status \(status), time \(time), looper \(looper.status.rawValue), error \(err.map { "\($0)" } ?? "none")"
    }

    /// Media-clock times at which the player's current item was replaced after the first, which is where the looper starts the next pass
    /// (OUT-002d, reporting only; at most 2,000). Items set up when playback starts may add an early entry.
    public var itemChangeTimes: [Double] { lock.lock(); defer { lock.unlock() }; return itemChanges }

    public func start() { player.play() }
    public func stop() { player.pause() }

    /// Number of distinct frames delivered so far (diagnostics).
    public var deliveredFrameCount: Int { lock.lock(); defer { lock.unlock() }; return delivered }

    /// The newest decoded frame, or the previous one if nothing new has arrived. Never blocks on decoding.
    public func latestPixelBuffer() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if let out = output {
            let t = out.itemTime(forHostTime: CACurrentMediaTime())
            if t.isValid, out.hasNewPixelBuffer(forItemTime: t),
               let buffer = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) {
                latest = buffer
                delivered += 1
            }
        }
        return latest
    }
}

/// Wraps a CVMetalTextureCache. One per render thread. The `keepAlive` object must outlive GPU use of `texture`.
public final class VideoTextureConverter {
    public struct Frame {
        public let texture: MTLTexture
        public let keepAlive: CVMetalTexture
    }

    private let cache: CVMetalTextureCache

    public init(device: MTLDevice) throws {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            throw MediaError.noTextureCache
        }
        self.cache = cache
    }

    public func texture(from buffer: CVPixelBuffer) -> Frame? {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil,
                                                               .bgra8Unorm, width, height, 0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return nil }
        return Frame(texture: texture, keepAlive: cvTexture)
    }

    public func flush() { CVMetalTextureCacheFlush(cache, 0) }
}
