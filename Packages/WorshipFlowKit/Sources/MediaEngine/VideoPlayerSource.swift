// MEDIA-02 / MEDIA-03: a video player driven by a `MediaTransport`. Decoding happens on AVFoundation's own queues;
// an AVPlayerItemVideoOutput hands the newest decoded BGRA frame to whichever output asks for it, so no thread that
// renders ever waits for a decoder.
import Foundation
import AVFoundation
import CoreVideo
import os
import Domain

/// The clock transports run on: monotonic seconds since boot, unaffected by changes to the wall clock.
public enum MediaClock {
    public static func now() -> Double { ProcessInfo.processInfo.systemUptime }
}

/// Whether a source can still be expected to deliver frames (R9).
public enum PlaybackHealth: Sendable, Equatable {
    case healthy
    /// The item or the player failed (a broken, truncated or unsupported file). `String` says why.
    case failed(String)
    /// The player was told to play and did not advance, and the watchdog's re-seeks did not help.
    case stalled
}

/// A lock that knows whether the calling thread holds it, so a test can prove no AVFoundation call is made under it (R18).
// @unchecked Sendable: `mutex` is the lock; `owner` is itself lock-guarded.
final class TrackedLock: @unchecked Sendable {
    private let mutex = NSLock()
    private let owner = OSAllocatedUnfairLock<UInt32>(initialState: 0)
    private static var thisThread: UInt32 { pthread_mach_thread_np(pthread_self()) }

    func lock() { mutex.lock(); owner.withLock { $0 = Self.thisThread } }
    func unlock() { owner.withLock { $0 = 0 }; mutex.unlock() }
    var isHeldByCurrentThread: Bool { owner.withLock { $0 == Self.thisThread } }
}

/// Test seam: told, for each AVFoundation call a `VideoPlayerSource` makes, whether the calling thread held its lock.
enum AVFoundationCallProbe {
    private static let observer = OSAllocatedUnfairLock<(@Sendable (_ lockHeld: Bool) -> Void)?>(initialState: nil)
    static func set(_ handler: (@Sendable (_ lockHeld: Bool) -> Void)?) { observer.withLock { $0 = handler } }
    static func note(lockHeld: Bool) { let h = observer.withLock { $0 }; h?(lockHeld) }
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
    private let lock = TrackedLock()
    /// Marks an AVFoundation call for the test seam. The rule (R18): no call into AVFoundation while `lock` is held,
    /// because AVFoundation's KVO callbacks come back on other threads and take the same lock.
    private func avf() { AVFoundationCallProbe.note(lockHeld: lock.isHeldByCurrentThread) }

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
    private var statusObservation: NSKeyValueObservation?      // the current item's status, replaced with the item
    private var looperObservation: NSKeyValueObservation?
    private var failureObserver: NSObjectProtocol?
    private var health: PlaybackHealth = .healthy
    private var healthHandler: (@Sendable (PlaybackHealth) -> Void)?
    /// Bumped by `stop()`: a frame fetched before it must not be stored after it.
    private var epoch = 0
    private var endObserver: NSObjectProtocol?
    // Stall watchdog (MEDIA-001): see `watchForStall()`.
    private var stallCheckedAt = 0.0
    private var stallLastTime = -1.0
    private var stallSince = 0.0
    private var stallRecoveryCount = 0
    private var consecutiveStallRecoveries = 0
    private var lastRecoveryTarget: Double?

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
        if let looper {
            looperObservation = looper.observe(\.status, options: [.initial, .new]) { [weak self] looper, _ in
                if looper.status == .failed { self?.setHealth(.failed(Self.describe(looper.error))) }
            }
        }
        failureObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification,
                                                                 object: nil, queue: nil) { [weak self] note in
            guard let self, let item = note.object as? AVPlayerItem, item === self.player.currentItem else { return }
            self.setHealth(.failed(Self.describe(item.error)))
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
        statusObservation?.invalidate()
        looperObservation?.invalidate()
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        player.pause()
        looper?.disableLooping()
    }

    private static func makeOutput() -> AVPlayerItemVideoOutput {
        let attributes: [String: any Sendable] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
        ]
        let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        out.suppressesPlayerRendering = true
        return out
    }

    private func attachOutput(to item: AVPlayerItem?) {
        // Build the new output and swap it in under the lock; talk to AVFoundation only after letting go (R18).
        let fresh = item == nil ? nil : Self.makeOutput()
        lock.lock()
        let oldOutput = output, oldItem = outputItem
        output = fresh
        outputItem = item
        lock.unlock()
        if let oldOutput, let oldItem { avf(); oldItem.remove(oldOutput) }
        if let item, let fresh { avf(); item.add(fresh) }

        // Watch the item itself: a file that opens but cannot be decoded fails here, long after `init` returned.
        let observation = item?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            if item.status == .failed { self?.setHealth(.failed(Self.describe(item.error))) }
        }
        lock.lock()
        let replaced = statusObservation
        statusObservation = observation
        lock.unlock()
        replaced?.invalidate()
    }

    private func playerReachedEnd() {
        lock.lock()
        playerEnded = true
        let handler = endedHandler
        lock.unlock()
        handler?()
    }

    // MARK: Health (R9)

    /// The watchdog re-seeks a stalled player this many times in a row, without the time moving, before it reports
    /// the source as `.stalled`.
    static let maxStallRecoveries = 3
    static func isUnrecoverable(consecutiveRecoveries: Int) -> Bool { consecutiveRecoveries >= maxStallRecoveries }

    /// `.failed` when the item or player failed (broken, truncated or unsupported file, unreachable volume),
    /// `.stalled` when it was told to play and the watchdog could not get it moving, otherwise `.healthy`. A failure is
    /// permanent for this source; a stall clears itself if the clip starts moving again.
    public var playbackHealth: PlaybackHealth { lock.lock(); defer { lock.unlock() }; return health }

    /// Called each time `playbackHealth` changes. May run on any thread.
    public func setOnHealthChange(_ handler: (@Sendable (PlaybackHealth) -> Void)?) {
        lock.lock(); healthHandler = handler; lock.unlock()
    }

    private func setHealth(_ new: PlaybackHealth) {
        lock.lock()
        var changed = false
        if case .failed = health {} else if health != new { health = new; changed = true }   // a failure is final
        let handler = healthHandler
        lock.unlock()
        if changed { handler?(new) }
    }

    private static func describe(_ error: Error?) -> String {
        error.map { $0.localizedDescription } ?? "the player reported a failure"
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

    /// 0...1.
    public var volume: Float {
        get { player.volume }
        set { player.volume = min(1, max(0, newValue)) }
    }

    /// MEDIA-006: the Core Audio device UID this player's sound goes to. Nil (or empty) is the system default. Set it
    /// before the clip plays; AVPlayer applies it to its audio renderer.
    public var audioOutputDeviceUniqueID: String? {
        get { player.audioOutputDeviceUniqueID }
        set { player.audioOutputDeviceUniqueID = newValue }
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
        epoch += 1
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
        lock.lock()
        let play = wantsPlaying
        stallLastTime = -1
        stallSince = CACurrentMediaTime()
        lock.unlock()
        if play { player.play() } else { player.pause() }
    }

    // MARK: Frames

    /// Number of distinct frames delivered so far (diagnostics).
    public var deliveredFrameCount: Int { lock.lock(); defer { lock.unlock() }; return delivered }

    /// The newest decoded frame, or the previous one if nothing new has arrived. Never blocks on decoding.
    public func latestPixelBuffer() -> CVPixelBuffer? {
        watchForStall()
        lock.lock()
        let out = output
        let startedIn = epoch
        lock.unlock()
        var fresh: CVPixelBuffer?
        if let out {                                  // AVFoundation is asked with the lock released (R18)
            avf()
            let t = out.itemTime(forHostTime: CACurrentMediaTime())
            if t.isValid, out.hasNewPixelBuffer(forItemTime: t) {
                avf()
                fresh = out.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil)
            }
        }
        lock.lock()
        defer { lock.unlock() }
        if let fresh, epoch == startedIn {            // a stop() meanwhile discards the frame
            latest = fresh
            delivered += 1
        }
        return latest
    }

    /// Times the watchdog had to re-seek a player that was told to play but whose time stood still (diagnostics, tests).
    public var stallRecoveries: Int { lock.lock(); defer { lock.unlock() }; return stallRecoveryCount }

    /// AVPlayer sometimes ends up with rate 1 and a ready item whose time never advances (seen after seeking to a
    /// non-key frame while the machine is busy: the clip froze at the seek target and never reported its end). Outputs
    /// call `latestPixelBuffer()` continuously, so this is checked there, at most four times a second. If the player has
    /// been told to play, is ready, and its time has not moved for a second, seek it to where it stands; the rate is
    /// re-applied when that seek finishes. If that happens `maxStallRecoveries` times in a row without the time moving,
    /// the source reports `.stalled` (R9) and goes on trying.
    private func watchForStall() {
        let host = CACurrentMediaTime()
        lock.lock()
        guard wantsPlaying, pendingSeeks == 0, !playerEnded, host - stallCheckedAt >= 0.25 else { lock.unlock(); return }
        stallCheckedAt = host
        lock.unlock()

        avf()
        guard player.currentItem?.status == .readyToPlay else { return }
        avf()
        let time = player.currentTime().seconds

        lock.lock()
        guard wantsPlaying, pendingSeeks == 0, !playerEnded else { lock.unlock(); return }   // changed while we looked
        if !time.isFinite || abs(time - stallLastTime) > 0.001 {
            stallLastTime = time
            stallSince = host
            var recovered = false
            if let target = lastRecoveryTarget, time.isFinite, abs(time - target) > 0.05 {
                lastRecoveryTarget = nil           // moving again, past where the last kick put it
                consecutiveStallRecoveries = 0
                recovered = true
            }
            let wasStalled = health == .stalled
            lock.unlock()
            if recovered && wasStalled { setHealth(.healthy) }
            return
        }
        guard host - stallSince >= 1.0 else { lock.unlock(); return }
        stallSince = host
        // Kick it where it stands. (The transport's own clock may already say the clip is over: the player is the one
        // that is behind, and it still has to play out the rest and report its end.)
        let target = time
        if transport.duration > 0, !loops, target >= transport.duration - 0.1 { lock.unlock(); return }
        if let last = lastRecoveryTarget, abs(last - target) <= 0.05 { consecutiveStallRecoveries += 1 } else { consecutiveStallRecoveries = 1 }
        lastRecoveryTarget = target
        let giveUp = Self.isUnrecoverable(consecutiveRecoveries: consecutiveStallRecoveries)
        pendingSeeks += 1
        stallRecoveryCount += 1
        lock.unlock()
        if giveUp { setHealth(.stalled) }
        avf()
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero,
                    toleranceAfter: .zero) { [weak self] _ in self?.seekFinished() }
    }

    /// Player state for diagnostics.
    public var diagnostics: String {
        let item = player.currentItem
        let err: Error? = item?.error ?? player.error ?? looper?.error
        let status = item.map { String($0.status.rawValue) } ?? "no item"
        let time = String(format: "%.2f", player.currentTime().seconds)
        lock.lock(); let extra = "pendingSeeks \(pendingSeeks), wantsPlaying \(wantsPlaying), recoveries \(stallRecoveryCount), ended \(playerEnded)"; lock.unlock()
        return "\(extra), rate \(player.rate), control \(player.timeControlStatus.rawValue), item status \(status), time \(time), error \(err.map { "\($0)" } ?? "none")"
    }
}

