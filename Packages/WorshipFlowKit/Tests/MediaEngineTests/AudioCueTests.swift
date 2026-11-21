// MEDIA-005 / MEDIA-006: the audio cue player on a real AVAudioEngine rendered offline (no device, no sound), the
// level meter's arithmetic, the device catalog and the video players' output device.
import Testing
import Foundation
import AVFoundation
import Domain
@testable import MediaEngine

/// A device catalog the test edits.
final class FakeCatalog: AudioDeviceCatalog, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [AudioOutputDevice]
    private var handlers: [Int: @Sendable () -> Void] = [:]
    private var next = 0
    init(_ list: [AudioOutputDevice]) { self.list = list }

    func outputDevices() -> [AudioOutputDevice] { lock.lock(); defer { lock.unlock() }; return list }
    func deviceID(forUID uid: String) -> UInt32? {
        lock.lock(); defer { lock.unlock() }
        return list.first { $0.uid == uid } == nil ? nil : 77
    }
    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        lock.lock(); let key = next; next += 1; handlers[key] = handler; lock.unlock()
        return { [weak self] in self?.lock.lock(); self?.handlers[key] = nil; self?.lock.unlock() }
    }
    var observerCount: Int { lock.lock(); defer { lock.unlock() }; return handlers.count }
    func set(_ devices: [AudioOutputDevice]) {
        lock.lock(); list = devices; let all = Array(handlers.values); lock.unlock()
        all.forEach { $0() }
    }
}

enum Tone {
    /// A 440 Hz sine at `amplitude`, written as 16-bit PCM in a CAF-free WAV so any reader opens it.
    static func write(to url: URL, seconds: Double, amplitude: Float = 0.5, channels: AVAudioChannelCount = 2) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: channels, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: Int(channels),
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(44100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<Int(channels) {
            let p = buffer.floatChannelData![c]
            for i in 0..<Int(frames) { p[i] = amplitude * Float(sin(2 * Double.pi * 440 * Double(i) / 44100)) }
        }
        try file.write(from: buffer)
    }

    static func make(seconds: Double, amplitude: Float = 0.5, channels: AVAudioChannelCount = 2) throws -> URL {
        let url = try TestMedia.tempDirectory().appendingPathComponent("tone.wav")
        try write(to: url, seconds: seconds, amplitude: amplitude, channels: channels)
        return url
    }
}

/// Polls on the main actor until `condition` holds or `seconds` pass.
@MainActor func waitMain(upTo seconds: Double = 8, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// Renders offline, then gives the engine's tap queue a moment: tap buffers reach the meter asynchronously.
@MainActor func render(_ player: AudioCuePlayer, _ seconds: Double) async throws {
    try player.renderOffline(seconds: seconds)
    try await Task.sleep(nanoseconds: 300_000_000)
}

@Suite struct LevelAccumulatorTests {
    @Test func peakAndRMSOfKnownSamples() {
        var acc = LevelAccumulator(channels: 2)
        acc.add([0, 0.5, -1, 0.5], channel: 0)
        acc.add([0.25, -0.25, 0.25, -0.25], channel: 1)
        let l = acc.takeLevels()
        #expect(l.peak == [1, 0.25])
        #expect(abs(l.rms[0] - Float((0 + 0.25 + 1 + 0.25) / 4).squareRoot()) < 1e-6)
        #expect(abs(l.rms[1] - 0.25) < 1e-6)
    }

    @Test func takingResetsAndSeveralBuffersCombine() {
        var acc = LevelAccumulator(channels: 1)
        acc.add([0.2, 0.2], channel: 0)
        acc.add([-0.6, 0.0], channel: 0)
        let l = acc.takeLevels()
        #expect(l.peak == [0.6])
        #expect(abs(l.rms[0] - Float((0.04 + 0.04 + 0.36 + 0) / 4).squareRoot()) < 1e-6)
        #expect(acc.takeLevels() == .silent(channels: 1))        // nothing since the last take
    }

    @Test func silenceNonFiniteSamplesAndStrayChannelsAreSafe() {
        var acc = LevelAccumulator(channels: 2)
        acc.add([Float.nan, .infinity, 0.5], channel: 0)
        acc.add([0.1], channel: 5)                                // a channel the meter does not have: ignored
        acc.add([], channel: 1)
        let l = acc.takeLevels()
        #expect(l.peak[0] == 0.5 && l.peak[1] == 0 && l.rms[1] == 0)
        #expect(l.peak.allSatisfy(\.isFinite) && l.rms.allSatisfy(\.isFinite))
    }

    @Test func aMeterWithNoChannelsStillReturnsSomething() {
        var acc = LevelAccumulator(channels: 0)
        #expect(acc.takeLevels().peak.count == 2)                 // two-channel meter is the floor the interface draws
    }
}

@MainActor
@Suite(.serialized) struct AudioCuePlayerTests {
    private let builtIn = AudioOutputDevice(uid: "BuiltIn", name: "Speakers", channelCount: 2, isDefault: true)
    private let desk = AudioOutputDevice(uid: "Desk", name: "Desk", channelCount: 4, isDefault: false)

    private func offline(_ catalog: FakeCatalog? = nil) -> AudioCuePlayer {
        AudioCuePlayer(catalog: catalog ?? FakeCatalog([builtIn, desk]), output: .offline(sampleRate: 44100))
    }

    @Test func theMeterReadsTheLevelOfWhatIsPlaying() async throws {
        let url = try Tone.make(seconds: 2)
        let player = offline()
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.5)
        let l = player.takeMeter()
        #expect(l.peak.count == 2)
        #expect(l.peak.allSatisfy { $0 > 0.45 && $0 <= 0.52 }, "peak \(l.peak)")
        #expect(l.rms.allSatisfy { $0 > 0.3 && $0 < 0.4 }, "rms \(l.rms)")          // 0.5 / sqrt 2 = 0.354
        player.stop()
    }

    @Test func aMonoFileFillsBothMeterChannels() async throws {
        let url = try Tone.make(seconds: 1, channels: 1)
        let player = offline()
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        let l = player.takeMeter()
        #expect(l.peak.count == 2 && l.peak[0] > 0.3 && abs(l.peak[0] - l.peak[1]) < 0.01, "peak \(l.peak)")
        player.stop()
    }

    @Test func volumeScalesTheSignalAndMuteSilencesIt() async throws {
        let url = try Tone.make(seconds: 3)
        let player = offline()
        player.setLevel(volume: 0.5, muted: false)
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        let half = player.takeMeter()
        #expect(half.peak.allSatisfy { $0 > 0.2 && $0 < 0.27 }, "peak \(half.peak)")
        player.setLevel(volume: 0.5, muted: true)
        try await render(player, 0.3)
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 < 0.001 })
        player.setLevel(volume: 0.5, muted: false)
        try await render(player, 0.3)
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 > 0.2 })
        player.stop()
    }

    @Test func aLevelOutsideZeroToOneIsClamped() async throws {
        let url = try Tone.make(seconds: 2)
        let player = offline()
        player.setLevel(volume: 9, muted: false)
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 <= 0.52 })
        player.setLevel(volume: .nan, muted: false)
        try await render(player, 0.3)
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 < 0.001 })
        player.stop()
    }

    @Test func positionAdvancesWithWhatIsRenderedAndPauseHoldsIt() async throws {
        let url = try Tone.make(seconds: 4)
        let player = offline()
        try player.play(url: url, from: 0, loops: false)
        #expect(abs(player.duration - 4) < 0.01 && player.isPlaying)
        try await render(player, 1)
        #expect(abs(player.position - 1) < 0.1, "position \(player.position)")
        player.pause()
        let held = player.position
        try await render(player, 1)
        #expect(player.isPlaying == false && abs(player.position - held) < 0.01)
        player.resume()
        try await render(player, 1)
        #expect(player.isPlaying && abs(player.position - (held + 1)) < 0.15, "position \(player.position)")
        player.stop()
    }

    @Test func pausedAudioIsSilentAndResumeBringsItBack() async throws {
        let url = try Tone.make(seconds: 4)
        let player = offline()
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        player.pause()
        _ = player.takeMeter()
        try await render(player, 0.5)
        #expect(player.takeMeter().peak.allSatisfy { $0 < 0.001 })
        player.resume()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 > 0.4 })
        player.stop()
    }

    @Test func seekJumpsAndKeepsPlayingOrStaysPaused() async throws {
        let url = try Tone.make(seconds: 6)
        let player = offline()
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        player.seek(to: 4)
        #expect(abs(player.position - 4) < 0.05 && player.isPlaying)
        try await render(player, 0.5)
        #expect(abs(player.position - 4.5) < 0.15, "position \(player.position)")
        player.pause()
        player.seek(to: 1)
        #expect(abs(player.position - 1) < 0.05 && player.isPlaying == false)
        player.seek(to: 100)                                       // past the end: clamped
        #expect(player.position <= player.duration + 0.001)
        player.seek(to: -3)
        #expect(player.position == 0)
        player.stop()
    }

    @Test func startingPartWayInBeginsThere() async throws {
        let url = try Tone.make(seconds: 6)
        let player = offline()
        try player.play(url: url, from: 3, loops: false)
        #expect(abs(player.position - 3) < 0.05)
        player.stop()
    }

    @Test func aClipThatDoesNotLoopReportsItsEndOnceAndStops() async throws {
        let url = try Tone.make(seconds: 0.5)
        let player = offline()
        var finished = 0
        player.onFinished = { finished += 1 }
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 1)
        #expect(await waitMain { finished > 0 })
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(finished == 1 && player.isPlaying == false)
    }

    @Test func aLoopingClipKeepsPlayingPastItsEnd() async throws {
        let url = try Tone.make(seconds: 0.5)
        let player = offline()
        var finished = 0
        player.onFinished = { finished += 1 }
        try player.play(url: url, from: 0, loops: true)
        for _ in 0..<6 {                                             // 3 s of a 0.5 s file, letting the loop re-schedule
            try await render(player, 0.5)
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(finished == 0 && player.isPlaying)
        #expect(player.takeMeter().peak.allSatisfy { $0 > 0.4 })     // still sounding
        #expect(player.position >= 0 && player.position < 0.5 + 0.01)
        // Switching the loop off lets it run to the end.
        player.setLoops(false)
        try await render(player, 1.5)
        #expect(await waitMain { finished == 1 })
        player.stop()
    }

    @Test func stopSilencesResetsAndStaysQuiet() async throws {
        let url = try Tone.make(seconds: 2)
        let player = offline()
        var finished = 0
        player.onFinished = { finished += 1 }
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        player.stop()
        #expect(player.isPlaying == false && player.position == 0)
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 < 0.001 })
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(finished == 0)                                        // a stop is not an ending
        player.stop()                                                 // twice is harmless
    }

    @Test func aFileThatIsNotAudioThrowsAndLeavesThePlayerIdle() async throws {
        let dir = try TestMedia.tempDirectory()
        let bad = dir.appendingPathComponent("bad.mp3")
        try Data("this is not audio".utf8).write(to: bad)
        let missing = dir.appendingPathComponent("nothing.wav")
        let player = offline()
        #expect(throws: (any Error).self) { try player.play(url: bad, from: 0, loops: false) }
        #expect(throws: (any Error).self) { try player.play(url: missing, from: 0, loops: false) }
        #expect(player.isPlaying == false && player.duration == 0)
    }

    @Test func startingAnotherFileReplacesTheFirst() async throws {
        let a = try Tone.make(seconds: 2, amplitude: 0.5)
        let b = try Tone.make(seconds: 3, amplitude: 0.2)
        let player = offline()
        var finished = 0
        player.onFinished = { finished += 1 }
        try player.play(url: a, from: 0, loops: false)
        try await render(player, 0.2)
        try player.play(url: b, from: 0, loops: false)
        #expect(abs(player.duration - 3) < 0.01)
        _ = player.takeMeter()
        try await render(player, 0.3)
        let l = player.takeMeter()
        #expect(l.peak.allSatisfy { $0 > 0.15 && $0 < 0.25 }, "peak \(l.peak)")
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(finished == 0)
        player.stop()
    }

    // MARK: Devices

    @Test func aDeviceThatExistsIsUsedAndOneThatDoesNotFallsBackAndIsReported() async throws {
        let catalog = FakeCatalog([builtIn, desk])
        let player = offline(catalog)
        var lost: [String] = []
        player.onDeviceLost = { lost.append($0) }
        #expect(player.outputDeviceUID == nil)
        player.setOutputDevice(uid: "Desk")
        #expect(player.outputDeviceUID == "Desk" && lost.isEmpty)
        player.setOutputDevice(uid: "Ghost")
        #expect(player.outputDeviceUID == nil && lost == ["Ghost"])
        player.setOutputDevice(uid: nil)
        #expect(player.outputDeviceUID == nil && lost == ["Ghost"])
    }

    @Test func aDeviceThatDisappearsMidPlayFallsBackKeepsPlayingAndComesBack() async throws {
        let catalog = FakeCatalog([builtIn, desk])
        let url = try Tone.make(seconds: 4)
        let player = offline(catalog)
        var lost: [String] = []
        player.onDeviceLost = { lost.append($0) }
        player.setOutputDevice(uid: "Desk")
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        catalog.set([builtIn])
        #expect(await waitMain { lost == ["Desk"] })
        #expect(player.outputDeviceUID == nil && player.isPlaying)
        _ = player.takeMeter()
        try await render(player, 0.3)
        #expect(player.takeMeter().peak.allSatisfy { $0 > 0.4 })     // still sounding on the default
        catalog.set([builtIn, desk])
        #expect(await waitMain { player.outputDeviceUID == "Desk" })
        #expect(lost == ["Desk"])                                     // coming back is not a loss
        player.stop()
    }

    @Test func thePlayerReleasesItsCatalogListenerWhenItGoesAway() async throws {
        let catalog = FakeCatalog([builtIn])
        var player: AudioCuePlayer? = offline(catalog)
        #expect(catalog.observerCount == 1)
        player?.shutdown()
        player = nil
        #expect(catalog.observerCount == 0)
    }

    @Test func eachPollDeliversTheMeterToTheMainActorHandler() async throws {
        let url = try Tone.make(seconds: 2)
        let player = offline()
        var seen: [AudioLevels] = []
        player.onLevels = { seen.append($0) }
        try player.play(url: url, from: 0, loops: false)
        try await render(player, 0.3)
        player.pollMeter()
        #expect(seen.count == 1 && seen[0].peak.allSatisfy { $0 > 0.4 })
        player.stop()
        #expect(seen.last == .silent())                               // stopping resets the meter shown to the operator
    }
}

@Suite struct AudioDeviceCatalogTests {
    @Test func theSystemCatalogListsOutputDevicesWithAtMostOneDefault() {
        let catalog = CoreAudioDeviceCatalog()
        let devices = catalog.outputDevices()
        #expect(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty && $0.channelCount > 0 })
        #expect(devices.filter(\.isDefault).count <= 1)
        #expect(Set(devices.map(\.uid)).count == devices.count)
        for d in devices { #expect(catalog.deviceID(forUID: d.uid) != nil) }
        #expect(catalog.deviceID(forUID: "no-such-device-\(UUID().uuidString)") == nil)
    }

    @Test func listenersCanBeAddedAndRemovedWithoutFiring() {
        let catalog = CoreAudioDeviceCatalog()
        let cancel = catalog.observeChanges { }
        cancel()
        cancel()                                                      // twice is harmless
    }
}

@Suite(.serialized) struct VideoAudioRoutingTests {
    @Test func theChosenDeviceReachesTheForegroundPlayerNowAndLater() async throws {
        let url = try await redThenBlue(in: TestMedia.tempDirectory())
        let asset = MediaAsset(name: "clip", kind: .video, path: url.path, duration: 2)
        let registry = MediaRegistry()
        registry.register(asset)
        registry.setAudioOutputDevice(uid: "Desk")                    // before anything is open
        var layers = MediaLayers()
        layers.startForeground(MediaSelection(asset: asset), at: 0)
        registry.apply(layers, at: 0)
        let source = try #require(registry.videoSource(in: .foreground))
        #expect(source.audioOutputDeviceUniqueID == "Desk")
        registry.setAudioOutputDevice(uid: nil)                       // back to the system default
        #expect(source.audioOutputDeviceUniqueID == nil || source.audioOutputDeviceUniqueID == "")
        registry.setAudioOutputDevice(uid: "Other")
        #expect(source.audioOutputDeviceUniqueID == "Other")
        registry.closeAll()
    }
}
