// MEDIA-02 / MEDIA-03: a video player driven by a `MediaTransport`. Decoding happens on AVFoundation's own queues;
// an AVPlayerItemVideoOutput hands the newest decoded BGRA frame to whichever output asks for it, so no thread that
// renders ever waits for a decoder.
import Foundation
import AVFoundation
import CoreVideo
import Domain

/// The clock transports run on: monotonic seconds since boot, unaffected by changes to the wall clock.
public enum MediaClock {
    public static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Thread-safe. `latestPixelBuffer()` may be called from several render threads at once; the control methods are
/// meant for the main actor but are safe from anywhere.
// @unchecked Sendable: AVPlayer, AVPlayerLooper and the output are touched under `lock` or only in init/deinit;
// every mutable field below is guarded by `lock`.
public final class VideoPlayerSource: @unchecked Sendable {
    public let url: URL
    public let loops: Bool

    private let clock: @Sendable () -> Double
    private let player: AVPlayer
    private var looper: AVPlayerLooper?
    private let lock = NSLock()

    private var transport: MediaTransport
    private var playerEnded = false
    /// Seeks issued and not yet finished. The rate is changed only when none is pending: asking an AVPlayer to play
    /// while a seek is in flight can leave it frozen at the seek target.
    private var pendingSeeks = 0
    private var wantsPlaying = false
    private var endedHandler: (@Sendable () -> Void)?
    private var output: AVPlayerItemVideoOutput?
    private var outputItem: AVPlayerItem?
    private var latest: CVPixelBuffer?
    private var delivered = 0
    private var itemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - duration: Seconds, when known (the media bin stores it). Needed for the transport to report the end and the
    ///     remaining time by itself; without it the end is still reported, from the player.
    ///   - muted: A background loop is normally muted; a foreground clip is not.
    public init(url: URL, loops: Bool, duration: Double? = nil, muted: Bool = true,
                clock: @escaping @Sendable () -> Double = MediaClock.now) throws {
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw MediaError.fileNotFound(url.path) }
        self.url = url
        self.loops = loops
        self.clock = clock
        self.transport = MediaTransport(duration: duration ?? 0, loops: loops)
        let item = AVPlayerItem(url: url)
        if loops {
            let queue = AVQueuePlayer()
            self.player = queue
            self.looper = AVPlayerLooper(player: queue, templateItem: item)
        } else {
            self.player = AVPlayer(playerItem: item)
            player.actionAtItemEnd = .pause          // keep the last frame on screen
        }
        player.isMuted = muted
        player.automaticallyWaitsToMinimizeStalling = false
        // The looper swaps the current item at every loop boundary; keep one output on whichever item is current.
        itemObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
            self?.attachOutput(to: player.currentItem)
        }
        if !loops {
            endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                                 object: item, queue: nil) { [weak self] _ in
                self?.playerReachedEnd()
            }
        }
    }

    deinit {
        itemObservation?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        looper?.disableLooping()
    }

    private func attachOutput(to item: AVPlayerItem?) {
        lock.lock()
        defer { lock.unlock() }
        if let old = output, let oldItem = outputItem { oldItem.remove(old) }
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

    private func playerReachedEnd() {
        lock.lock()
        playerEnded = true
        let handler = endedHandler
        lock.unlock()
        handler?()
    }

    // MARK: State

    /// Called once each time a clip that does not loop reaches its end. May run on any thread.
    public func setOnEnded(_ handler: (@Sendable () -> Void)?) {
        lock.lock(); endedHandler = handler; lock.unlock()
    }

    /// A copy of the transport as last applied or commanded.
    public var currentTransport: MediaTransport { lock.lock(); defer { lock.unlock() }; return transport }

    public func status(at now: Double? = nil) -> MediaTransport.Status {
        lock.lock(); defer { lock.unlock() }
        if playerEnded { return .ended }
        return transport.status(at: now ?? clock())
    }

    public func position(at now: Double? = nil) -> Double {
        lock.lock(); defer { lock.unlock() }
        return transport.position(at: now ?? clock())
    }

    public var isMuted: Bool {
        get { player.isMuted }
        set { player.isMuted = newValue }
    }

    /// 0...1. The audio goes to the system's default output; choosing another device comes with the audio slice.
    public var volume: Float {
        get { player.volume }
        set { player.volume = min(1, max(0, newValue)) }
    }

    // MARK: Control

    public func play() { command { $0.play(at: $1) } }
    public func pause() { command { $0.pause(at: $1) } }
    public func seek(to seconds: Double) { command { $0.seek(to: seconds, at: $1) } }

    public func stop() {
        lock.lock()
        transport.stop()
        playerEnded = false
        wantsPlaying = false
        latest = nil
        pendingSeeks += 1
        lock.unlock()
        player.pause()
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in self?.seekFinished() }
    }

    private func command(_ change: (inout MediaTransport, Double) -> Void) {
        let now = clock()
        lock.lock()
        var next = transport
        let reachedEnd = playerEnded
        // The player may have reached the end a moment before the transport's clock says so: agree with the player.
        if playerEnded { next.seek(to: next.duration, at: now) }
        change(&next, now)
        lock.unlock()
        apply(next, at: now, forceSeek: reachedEnd)
    }

    /// Makes the player follow `new`: seeks when the position moved by more than playing would have moved it, then
    /// plays or pauses to match the status. Does nothing when `new` equals what is already applied.
    public func apply(_ new: MediaTransport, at now: Double) { apply(new, at: now, forceSeek: false) }

    /// `forceSeek`: the player sits at the end of its item, so even a seek to a nearby position must be issued.
    private func apply(_ new: MediaTransport, at now: Double, forceSeek: Bool) {
        lock.lock()
        let previous = transport
        if previous == new { lock.unlock(); return }
        let target = new.position(at: now)
        let status = new.status(at: now)
        let moved = forceSeek || abs(previous.position(at: now) - target) > 0.05
        transport = new
        playerEnded = false          // a new instruction supersedes the end the player reported
        wantsPlaying = status == .playing
        if moved { pendingSeeks += 1 }
        let settled = pendingSeeks == 0
        lock.unlock()

        if moved {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
                        toleranceAfter: .zero) { [weak self] _ in self?.seekFinished() }
        }
        if settled { applyRate() }
    }

    private func seekFinished() {
        lock.lock()
        pendingSeeks = max(0, pendingSeeks - 1)
        let settled = pendingSeeks == 0
        lock.unlock()
        if settled { applyRate() }
    }

    /// Plays or pauses the player to match the latest instruction.
    private func applyRate() {
        lock.lock(); let play = wantsPlaying; lock.unlock()
        if play { player.play() } else { player.pause() }
    }

    // MARK: Frames

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

    /// Player state for diagnostics.
    public var diagnostics: String {
        let item = player.currentItem
        let err: Error? = item?.error ?? player.error ?? looper?.error
        let status = item.map { String($0.status.rawValue) } ?? "no item"
        let time = String(format: "%.2f", player.currentTime().seconds)
        return "rate \(player.rate), control \(player.timeControlStatus.rawValue), item status \(status), time \(time), error \(err.map { "\($0)" } ?? "none")"
    }
}
