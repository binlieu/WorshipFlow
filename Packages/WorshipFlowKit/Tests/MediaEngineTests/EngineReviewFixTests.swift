// FIX-A (review findings R9 reporting, R18): one failing test per defect, written before the fix.
import Testing
import Foundation
import CoreVideo
import Domain
@testable import MediaEngine

/// Counts calls from any thread.
private final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var total = 0, held = 0
    func note(lockHeld: Bool) { lock.lock(); total += 1; if lockHeld { held += 1 }; lock.unlock() }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return total }
    var callsUnderLock: Int { lock.lock(); defer { lock.unlock() }; return held }
}

private final class Events<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

/// A file that is readable but is not a movie.
private func brokenMovie(in dir: URL, name: String = "broken") throws -> URL {
    let url = dir.appendingPathComponent("\(name)-\(UUID().uuidString).mov")
    try Data("this is not a movie, only bytes".utf8).write(to: url)
    return url
}

// MARK: R18

@Suite(.serialized) struct NoAVFoundationCallUnderTheLockTests {
    @Test func playerCallsAreMadeOutsideTheSourcesLock() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let log = CallLog()
        AVFoundationCallProbe.set { log.note(lockHeld: $0) }
        defer { AVFoundationCallProbe.set(nil) }

        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        source.play()
        // Poll like a render thread for long enough that the stall watchdog's checks (four a second) run too.
        let end = Date().addingTimeInterval(1.8)
        while Date() < end {
            _ = source.latestPixelBuffer()
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        source.pause()
        source.seek(to: 0.5)
        _ = source.latestPixelBuffer()
        source.stop()

        #expect(log.calls > 0)                       // the seam is wired
        #expect(log.callsUnderLock == 0)
    }

    @Test func loopingSourceSwapsItsOutputWithoutTheLockToo() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let log = CallLog()
        AVFoundationCallProbe.set { log.note(lockHeld: $0) }
        defer { AVFoundationCallProbe.set(nil) }
        let source = try VideoPlayerSource(url: url, loops: true, duration: 2)
        source.play()
        let end = Date().addingTimeInterval(2.6)     // past a loop boundary, where the looper replaces the current item
        while Date() < end {
            _ = source.latestPixelBuffer()
            try await Task.sleep(nanoseconds: 16_000_000)
        }
        source.stop()
        #expect(log.calls > 0)
        #expect(log.callsUnderLock == 0)
    }
}

// MARK: R9

@Suite(.serialized) struct PlaybackHealthTests {
    @Test func aBrokenFileIsReportedAsFailedAfterOpening() async throws {
        let url = try brokenMovie(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false)      // readable, so opening does not throw
        source.play()
        let failed = await TestMedia.wait {
            if case .failed = source.playbackHealth { return true }
            return false
        }
        #expect(failed)
        #expect(source.latestPixelBuffer() == nil)
    }

    @Test func aBrokenLoopingFileIsReportedToo() async throws {
        let url = try brokenMovie(in: TestMedia.tempDirectory(), name: "brokenloop")
        let source = try VideoPlayerSource(url: url, loops: true)
        source.play()
        let failed = await TestMedia.wait {
            if case .failed = source.playbackHealth { return true }
            return false
        }
        #expect(failed)
    }

    @Test func theHealthCallbackFiresOnce() async throws {
        let url = try brokenMovie(in: TestMedia.tempDirectory())
        let events = Events<PlaybackHealth>()
        let source = try VideoPlayerSource(url: url, loops: false)
        source.setOnHealthChange { events.add($0) }
        source.play()
        #expect(await TestMedia.wait { !events.all.isEmpty })
        try await Task.sleep(nanoseconds: 300_000_000)
        let seen = events.all
        #expect(seen.count == 1)
        if case .failed(let why)? = seen.first { #expect(!why.isEmpty) } else { Issue.record("expected .failed, got \(seen)") }
    }

    @Test func aHealthyClipStaysHealthy() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let source = try VideoPlayerSource(url: url, loops: false, duration: 2)
        source.play()
        #expect(await TestMedia.wait { isRed(source.latestPixelBuffer()) })
        #expect(source.playbackHealth == .healthy)
        source.stop()
    }

    @Test func stallRecoveryGivesUpAfterRepeatedFailures() {
        #expect(VideoPlayerSource.isUnrecoverable(consecutiveRecoveries: 0) == false)
        #expect(VideoPlayerSource.isUnrecoverable(consecutiveRecoveries: 2) == false)
        #expect(VideoPlayerSource.isUnrecoverable(consecutiveRecoveries: 3) == true)
        #expect(VideoPlayerSource.isUnrecoverable(consecutiveRecoveries: 10) == true)
    }
}

@Suite(.serialized) struct MediaAvailabilityTests {
    private func foreground(_ id: UUID, kind: MediaKind = .video, duration: Double? = 2) -> MediaLayers {
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(assetID: id, kind: kind, duration: duration), at: 0)
        return layers
    }

    @Test func aBrokenForegroundClipIsReportedPerAssetId() async throws {
        let dir = try TestMedia.tempDirectory()
        let broken = try brokenMovie(in: dir)
        let id = UUID()
        let registry = MediaRegistry()
        let events = Events<String>()
        registry.setOnAvailabilityChange { changed, state in if changed == id { events.add("\(state)") } }
        #expect(registry.availability(of: id) == .notOpen)

        registry.register(id: id, kind: .video, url: broken, duration: 2)
        registry.apply(foreground(id), at: 0)
        let failed = await TestMedia.wait {
            if case .failed = registry.availability(of: id) { return true }
            return false
        }
        #expect(failed)
        #expect(registry.unavailableAssetIDs.contains(id))
        // The state is set before the callback runs, on another thread: wait for the callback, do not race it.
        let told = await TestMedia.wait { events.all.last?.hasPrefix("failed") == true }
        #expect(told)
    }

    @Test func aMissingFileIsReportedAtOnce() {
        let id = UUID()
        let registry = MediaRegistry()
        registry.register(id: id, kind: .video, url: URL(fileURLWithPath: "/nonexistent/clip.mov"), duration: 2)
        registry.apply(foreground(id), at: 0)
        if case .failed = registry.availability(of: id) {} else { Issue.record("expected .failed, got \(registry.availability(of: id))") }
        #expect(registry.unavailableAssetIDs.contains(id))
    }

    @Test func aGoodClipStartsThenDelivers() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let id = UUID()
        let registry = MediaRegistry()
        registry.register(id: id, kind: .video, url: url, duration: 2)
        registry.apply(foreground(id), at: 0)
        #expect(registry.availability(of: id) == .starting)                  // open, no frame pulled yet
        let delivering = await TestMedia.wait {
            _ = registry.currentPixelBuffer(for: .video(id), layer: .foreground)
            return registry.availability(of: id) == .delivering
        }
        #expect(delivering)
        #expect(registry.unavailableAssetIDs.isEmpty)
        registry.closeAll()
        #expect(registry.availability(of: id) == .notOpen)
    }

    @Test func aStillIsDeliveringOnceDecodedAndFailedWhenItCannotBe() async throws {
        let dir = try TestMedia.tempDirectory()
        let png = dir.appendingPathComponent("still.png")
        try TestMedia.writePNG(to: png, width: 8, height: 8, red: 255, green: 0, blue: 0)
        let good = UUID(), bad = UUID()
        let registry = MediaRegistry()
        registry.register(id: good, kind: .image, url: png)
        let garbage = dir.appendingPathComponent("garbage.png")
        try Data("nope".utf8).write(to: garbage)
        registry.register(id: bad, kind: .image, url: garbage)
        registry.apply(foreground(good, kind: .image, duration: nil), at: 0)
        #expect(await TestMedia.wait { registry.availability(of: good) == .delivering })

        registry.apply(foreground(bad, kind: .image, duration: nil), at: 0)
        let failed = await TestMedia.wait {
            if case .failed = registry.availability(of: bad) { return true }
            return false
        }
        #expect(failed)
    }

    @Test func snapshotListsEveryOpenAsset() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let id = UUID()
        let registry = MediaRegistry()
        registry.register(id: id, kind: .video, url: url, duration: 2)
        registry.apply(foreground(id), at: 0)
        #expect(registry.availabilitySnapshot().keys.contains(id))
        registry.closeAll()
    }
}
