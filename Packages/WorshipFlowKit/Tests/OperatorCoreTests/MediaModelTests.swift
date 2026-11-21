// MEDIA-001: the media bin and the media layers. No real media files and no players: a fake prober, a fake clock and an
// in-memory library.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// A clock the test moves by hand. Seconds, monotonic.
final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double = 1000
    func now() -> Double { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ seconds: Double) { lock.lock(); t += seconds; lock.unlock() }
}

/// Answers by file name: "bad.*" fails, "song.mp3" is audio, "*.png" an image, anything else a 10 s video.
struct FakeProber: MediaProber {
    struct Failure: LocalizedError { var errorDescription: String? { "The file could not be opened." } }
    func probe(url: URL) async throws -> MediaProbeResult {
        let name = url.lastPathComponent
        if name.hasPrefix("bad") { throw Failure() }
        if name.hasSuffix(".png") { return MediaProbeResult(kind: .image, pixelWidth: 800, pixelHeight: 600) }
        if name.hasSuffix(".mp3") { return MediaProbeResult(kind: .audio, duration: 30) }
        return MediaProbeResult(kind: .video, duration: 10, pixelWidth: 1920, pixelHeight: 1080)
    }
}

/// Which paths count as readable. Everything does until a test removes one.
final class FakeFiles: @unchecked Sendable {
    private let lock = NSLock()
    private var missing: Set<String> = []
    func lose(_ path: String) { lock.lock(); missing.insert(path); lock.unlock() }
    func restore(_ path: String) { lock.lock(); missing.remove(path); lock.unlock() }
    func isAvailable(_ asset: MediaAsset) -> Bool { lock.lock(); defer { lock.unlock() }; return !missing.contains(asset.path) }
}

@MainActor
final class MediaRig {
    let store: LibraryStore
    let clock = FakeClock()
    let files = FakeFiles()
    let model: MediaModel
    var layerChanges: [MediaLayers] = []
    var audioChanges: [(Float, Bool)] = []
    var assetChanges = 0

    init(store: LibraryStore? = nil) throws {
        self.store = try store ?? LibraryStore.inMemory()
        let clock = self.clock, files = self.files
        model = MediaModel(store: self.store, prober: FakeProber(), now: { clock.now() }, isAvailable: { files.isAvailable($0) })
        model.onLayersChange = { [unowned self] in layerChanges.append($0) }
        model.onAudioChange = { [unowned self] v, m in audioChanges.append((v, m)) }
        model.onAssetsChange = { [unowned self] _ in assetChanges += 1 }
    }

    /// A second model on the same library, as after a relaunch.
    func relaunched() -> MediaRig? { try? MediaRig(store: store) }

    @discardableResult
    func add(_ name: String) async -> MediaAsset {
        let asset = await model.add(url: URL(fileURLWithPath: "/media/\(name)"))
        return asset!
    }
}

@MainActor
@Suite struct MediaBinTests {
    @Test func addingStoresWhatTheProberFound() async throws {
        let rig = try MediaRig()
        let video = await rig.add("loop.mov")
        #expect(video.kind == .video && video.duration == 10 && video.pixelWidth == 1920 && video.pixelHeight == 1080)
        #expect(video.name == "loop" && video.path == "/media/loop.mov")
        let image = await rig.add("cross.png")
        #expect(image.kind == .image && image.duration == nil && image.pixelWidth == 800)
        #expect(rig.model.assets.map(\.name) == ["loop", "cross"])
        // What is on screen is what the library holds.
        #expect(try await rig.store.mediaAssets(kind: nil).map(\.id) == rig.model.assets.map(\.id))
        #expect(rig.model.lastError == nil)
    }

    @Test func theBookmarkIsStoredWithTheAsset() async throws {
        let rig = try MediaRig()
        let added = await rig.model.add(url: URL(fileURLWithPath: "/media/loop.mov"), bookmark: Data([9, 8, 7]))
        #expect(added?.bookmark == Data([9, 8, 7]))
        #expect(rig.model.assets.first?.bookmark == Data([9, 8, 7]))
    }

    @Test func addingTheSameFileTwiceKeepsOneEntry() async throws {
        let rig = try MediaRig()
        let first = await rig.add("loop.mov")
        let second = await rig.add("loop.mov")
        #expect(first.id == second.id && rig.model.assets.count == 1)
    }

    @Test func aFileThatCannotBeProbedIsReportedAndNotAdded() async throws {
        let rig = try MediaRig()
        let result = await rig.model.add(url: URL(fileURLWithPath: "/media/bad.mov"))
        #expect(result == nil && rig.model.assets.isEmpty)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("bad.mov") && message.contains("not added") && message.contains("could not be opened"))
        #expect(try await rig.store.mediaAssets(kind: nil).isEmpty)
    }

    @Test func addingSeveralKeepsTheGoodOnesAndReportsTheBadOnes() async throws {
        let rig = try MediaRig()
        let urls = ["a.mov", "bad1.mov", "b.png", "bad2.png"].map { URL(fileURLWithPath: "/media/\($0)") }
        let added = await rig.model.add(urls: urls)
        #expect(added.map(\.name) == ["a", "b"])
        let message = try #require(rig.model.lastError)
        #expect(message.contains("bad1.mov") && message.contains("bad2.png"))
        // A fully successful batch clears an old message.
        _ = await rig.model.add(urls: [URL(fileURLWithPath: "/media/c.mov")])
        #expect(rig.model.lastError == nil)
    }

    @Test func renameChangesTheNameOnly() async throws {
        let rig = try MediaRig()
        let a = await rig.add("loop.mov")
        await rig.model.rename(a.id, to: "  Welcome loop ")
        #expect(rig.model.asset(a.id)?.name == "Welcome loop" && rig.model.asset(a.id)?.path == a.path)
        await rig.model.rename(a.id, to: "   ")
        #expect(rig.model.asset(a.id)?.name == "Welcome loop")
        #expect(try #require(rig.model.lastError).contains("name is needed"))
        await rig.model.rename(UUID(), to: "Nobody")        // unknown id: nothing happens, nothing crashes
    }

    @Test func removeDropsTheReferenceAndNeverTheFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("wf-media-keep-\(UUID().uuidString).mov")
        try Data([1, 2, 3]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let rig = try MediaRig()
        let asset = try #require(await rig.model.add(url: file))
        await rig.model.remove(asset.id)
        #expect(rig.model.assets.isEmpty)
        #expect(try await rig.store.mediaAssets(kind: nil).isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func removingTheBackgroundOrTheClipTakesItOutOfTheLayers() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.setBackground(loop.id)
        rig.model.playForeground(clip.id)
        await rig.model.remove(loop.id)
        #expect(rig.model.layers.background == nil && rig.model.layers.foreground != nil)
        await rig.model.remove(clip.id)
        #expect(rig.model.layers.foreground == nil)
        await rig.model.flush()
        // The stored background choice went with the asset: a relaunch has none.
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.layers.background == nil)
    }

    @Test func theKindFilterShowsOneKindOrAll() async throws {
        let rig = try MediaRig()
        await rig.add("a.mov"); await rig.add("b.png"); await rig.add("c.mov"); await rig.add("song.mp3")
        #expect(rig.model.visibleAssets.count == 4)
        rig.model.kindFilter = .video
        #expect(rig.model.visibleAssets.map(\.name) == ["a", "c"])
        rig.model.kindFilter = .image
        #expect(rig.model.visibleAssets.map(\.name) == ["b"])
        rig.model.kindFilter = .audio
        #expect(rig.model.visibleAssets.map(\.name) == ["song"])
        rig.model.kindFilter = nil
        #expect(rig.model.visibleAssets.count == 4)
    }

    @Test func theBinSurvivesARelaunch() async throws {
        let rig = try MediaRig()
        await rig.add("a.mov"); await rig.add("b.png")
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.assets.map(\.name) == ["a", "b"])
        #expect(again.assetChanges == 1)
    }
}

@MainActor
@Suite struct MediaBackgroundTests {
    @Test func settingTheBackgroundStartsALoopingLayerAndTellsTheApp() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        let layer = try #require(rig.model.layers.background)
        #expect(layer.selection == MediaSelection(asset: loop) && layer.transport.loops)
        #expect(layer.transport.status(at: rig.clock.now()) == .playing)
        #expect(rig.layerChanges.count == 1 && rig.layerChanges[0].background == layer)
        // Choosing the one that is already the background changes nothing and publishes nothing.
        rig.model.setBackground(loop.id)
        #expect(rig.layerChanges.count == 1)
        rig.model.clearBackground()
        #expect(rig.model.layers.background == nil && rig.layerChanges.count == 2)
        rig.model.clearBackground()
        #expect(rig.layerChanges.count == 2)
    }

    @Test func aStillImageCanBeTheBackground() async throws {
        let rig = try MediaRig()
        let image = await rig.add("cross.png")
        rig.model.setBackground(image.id)
        #expect(rig.model.layers.background?.selection.kind == .image)
    }

    @Test func theBackgroundComesBackAfterARelaunchButTheForegroundDoesNot() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        let clip = await rig.add("clip.mov")
        rig.model.showStateChanged(isLive: true)
        rig.model.setBackground(loop.id)
        rig.model.playForeground(clip.id)
        await rig.model.flush()

        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.layers.background?.selection.assetID == loop.id)
        #expect(again.model.layers.background?.transport.status(at: again.clock.now()) == .playing)
        #expect(again.model.layers.foreground == nil)
        #expect(again.layerChanges.count == 1)
    }

    @Test func clearingTheBackgroundIsRememberedToo() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        rig.model.clearBackground()
        await rig.model.flush()
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.layers.background == nil)
    }

    @Test func aBackgroundWhoseFileIsGoneAtLaunchIsReportedAndComesBackWithTheFile() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        await rig.model.flush()

        let again = try #require(rig.relaunched())
        again.files.lose(loop.path)
        await again.model.load()
        #expect(again.model.layers.background == nil && again.layerChanges.isEmpty)
        let message = try #require(again.model.lastError)
        #expect(message.contains("loop") && message.contains("/media/loop.mov") && message.contains("missing"))

        // The choice was kept: with the drive back, the next launch restores it.
        let third = try #require(rig.relaunched())
        await third.model.load()
        #expect(third.model.layers.background?.selection.assetID == loop.id)
    }

    @Test func aMissingFileIsRefusedWithAMessageAndChangesNothing() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        let other = await rig.add("other.mov")
        rig.model.setBackground(other.id)
        rig.files.lose(loop.path)
        rig.model.setBackground(loop.id)
        #expect(rig.model.layers.background?.selection.assetID == other.id)
        #expect(try #require(rig.model.lastError).contains("missing"))
        #expect(rig.layerChanges.count == 1)
    }

    @Test func aSoundFileIsKeptInTheBinButNeverBecomesALayer() async throws {
        let rig = try MediaRig()
        let song = await rig.add("song.mp3")
        rig.model.showStateChanged(isLive: true)
        rig.model.setBackground(song.id)
        rig.model.playForeground(song.id)
        #expect(rig.model.layers.background == nil && rig.model.layers.foreground == nil)
        #expect(try #require(rig.model.lastError).contains("sound file"))
        #expect(rig.layerChanges.isEmpty)
    }

    @Test func aBackgroundTheEngineCouldNotOpenIsTakenOutButStaysChosen() async throws {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        rig.model.reportUnavailable([loop.id])
        #expect(rig.model.layers.background == nil)
        #expect(try #require(rig.model.lastError).contains("could not be opened"))
        await rig.model.flush()
        let again = try #require(rig.relaunched())
        await again.model.load()
        #expect(again.model.layers.background?.selection.assetID == loop.id)
    }
}

@MainActor
@Suite struct MediaForegroundTests {
    func liveRig() async throws -> (MediaRig, MediaAsset, MediaAsset) {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")      // 10 s
        let image = await rig.add("cross.png")
        rig.model.showStateChanged(isLive: true)
        return (rig, clip, image)
    }

    @Test func playStartsAClipOnceFromTheStart() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        let layer = try #require(rig.model.layers.foreground)
        #expect(!layer.transport.loops && layer.transport.status(at: rig.clock.now()) == .playing)
        let readout = try #require(rig.model.foregroundReadout())
        #expect(readout.name == "clip" && readout.position == 0 && readout.duration == 10 && readout.remaining == 10)
        #expect(readout.isPlaying && readout.canSeek)
        #expect(rig.layerChanges.count == 1)
    }

    @Test func positionAndRemainingFollowTheClock() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.clock.advance(3.5)
        let readout = try #require(rig.model.foregroundReadout())
        #expect(abs(readout.position - 3.5) < 1e-9 && abs(readout.remaining - 6.5) < 1e-9)
    }

    @Test func pauseHoldsTheClipAndResumeContinuesIt() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.clock.advance(2)
        rig.model.pause()
        rig.clock.advance(5)
        var readout = try #require(rig.model.foregroundReadout())
        #expect(readout.status == .paused && abs(readout.position - 2) < 1e-9)
        rig.model.resume()
        rig.clock.advance(1)
        readout = try #require(rig.model.foregroundReadout())
        #expect(readout.isPlaying && abs(readout.position - 3) < 1e-9)
    }

    @Test func seekMovesThePositionAndKeepsPausedPaused() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.model.pause()
        rig.model.seek(to: 7)
        var readout = try #require(rig.model.foregroundReadout())
        #expect(readout.status == .paused && readout.position == 7)
        rig.model.seek(to: 99)                          // beyond the end clamps
        readout = try #require(rig.model.foregroundReadout())
        #expect(readout.position == 10)
        rig.model.seek(to: -4)
        #expect(rig.model.foregroundReadout()?.position == 0)
    }

    @Test func tickEndsAFinishedClipAndReportsTheChange() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.clock.advance(9.9)
        #expect(!rig.model.tick(now: rig.clock.now()))
        #expect(rig.model.layers.foreground != nil && rig.layerChanges.count == 1)
        rig.clock.advance(0.2)
        #expect(rig.model.tick(now: rig.clock.now()))
        #expect(rig.model.layers.foreground == nil && rig.layerChanges.count == 2)
        #expect(rig.layerChanges.last?.foreground == nil)
        // Nothing left to end: a second tick reports no change.
        #expect(!rig.model.tick(now: rig.clock.now() + 100))
        #expect(rig.layerChanges.count == 2)
    }

    @Test func aPausedClipNeverEndsByTheClock() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.model.pause()
        rig.clock.advance(1000)
        #expect(!rig.model.tick())
        #expect(rig.model.layers.foreground != nil)
    }

    @Test func aStillImageStaysUntilStopped() async throws {
        let (rig, _, image) = try await liveRig()
        rig.model.playForeground(image.id)
        rig.clock.advance(3600)
        #expect(!rig.model.tick())
        #expect(rig.model.foregroundReadout()?.canSeek == false)
        rig.model.stopForeground()
        #expect(rig.model.layers.foreground == nil)
    }

    @Test func stopRemovesTheClipAndDoesNothingWithoutOne() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.stopForeground()
        #expect(rig.layerChanges.isEmpty)
        rig.model.playForeground(clip.id)
        rig.model.stopForeground()
        #expect(rig.model.layers.foreground == nil && rig.model.foregroundReadout() == nil && rig.layerChanges.count == 2)
        rig.model.pause(); rig.model.resume(); rig.model.seek(to: 3)    // no clip: harmless
        #expect(rig.layerChanges.count == 2)
    }

    @Test func playingAgainReplacesTheClipFromTheStart() async throws {
        let (rig, clip, image) = try await liveRig()
        rig.model.playForeground(clip.id)
        rig.clock.advance(4)
        rig.model.playForeground(image.id)
        #expect(rig.model.layers.foreground?.selection.assetID == image.id)
        rig.model.playForeground(clip.id)
        #expect(rig.model.foregroundReadout()?.position == 0)
    }

    @Test func aClipIsRefusedWhileTheScreensAreStopped() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("clip.mov")
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground == nil && rig.layerChanges.isEmpty)
        #expect(try #require(rig.model.lastError).contains("Take a slide live first"))
    }

    @Test func stoppingTheShowStopsTheClipButKeepsTheBackground() async throws {
        let (rig, clip, _) = try await liveRig()
        let loop = await rig.add("loop.mov")
        rig.model.setBackground(loop.id)
        rig.model.playForeground(clip.id)
        rig.model.showStateChanged(isLive: false)
        #expect(rig.model.layers.foreground == nil && rig.model.layers.background != nil)
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground == nil)
    }

    @Test func aClipWhoseFileIsMissingIsRefusedAndOneThatFailsLaterIsRemoved() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.files.lose(clip.path)
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground == nil)
        #expect(try #require(rig.model.lastError).contains("missing"))
        rig.files.restore(clip.path)
        rig.model.dismissError()
        rig.model.playForeground(clip.id)
        #expect(rig.model.layers.foreground != nil)
        rig.model.reportUnavailable([clip.id])
        #expect(rig.model.layers.foreground == nil)
        #expect(try #require(rig.model.lastError).contains("could not be opened"))
        rig.model.reportUnavailable([clip.id])          // already gone: nothing more
        #expect(rig.layerChanges.count == 2)
    }

    @Test func theClipEndsWhenThePlayerSaysSoNearItsEnd() async throws {
        let (rig, clip, _) = try await liveRig()
        rig.model.playForeground(clip.id)
        // A late report from an earlier clip, while this one has just started, is ignored.
        #expect(!rig.model.playerReportedEnd())
        rig.clock.advance(9.5)
        #expect(rig.model.playerReportedEnd())
        #expect(rig.model.layers.foreground == nil)
        #expect(!rig.model.playerReportedEnd())
    }

    @Test func aClipWithoutAStoredLengthEndsOnThePlayersReport() async throws {
        let rig = try MediaRig()
        let unknown = try await rig.store.addMediaAsset(name: "stream", kind: .video, path: "/media/stream.mov", bookmark: nil,
                                                        duration: nil, pixelWidth: nil, pixelHeight: nil)
        await rig.model.load()
        rig.model.showStateChanged(isLive: true)
        rig.model.playForeground(unknown.id)
        rig.clock.advance(500)
        #expect(!rig.model.tick())                      // the clock cannot know
        #expect(rig.model.foregroundReadout()?.canSeek == false)
        #expect(rig.model.playerReportedEnd())
        #expect(rig.model.layers.foreground == nil)
    }

    @Test func volumeAndMuteAreClampedAndReported() async throws {
        let rig = try MediaRig()
        #expect(rig.model.volume == 0.5 && !rig.model.isMuted)
        rig.model.setVolume(0.2)
        rig.model.setVolume(0.2)                         // unchanged: no second call
        rig.model.setVolume(3)
        rig.model.setVolume(-1)
        rig.model.setVolume(.nan)
        rig.model.setMuted(true)
        rig.model.setMuted(true)
        #expect(rig.audioChanges.map(\.0) == [0.2, 1, 0, 0])
        #expect(rig.audioChanges.map(\.1) == [false, false, false, true])
        #expect(rig.model.volume == 0 && rig.model.isMuted)
    }
}
