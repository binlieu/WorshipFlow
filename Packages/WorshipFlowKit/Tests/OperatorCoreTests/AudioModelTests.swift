// MEDIA-005 / MEDIA-006: the audio list, the cues and the programme audio device. No real engine and no real device:
// a fake engine per cue, a fake device list and a clock the test moves by hand. (`FakeClock` and `FakeFiles` come
// from MediaModelTests.swift.)
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

/// A device list the test edits. Thread-safe because the real one is called from a Core Audio queue.
final class FakeDeviceList: AudioDeviceListing, @unchecked Sendable {
    private let lock = NSLock()
    private var list: [AudioOutputDevice]
    private var handlers: [Int: @Sendable () -> Void] = [:]
    private var next = 0

    init(_ list: [AudioOutputDevice] = FakeDeviceList.standard) { self.list = list }

    static let builtIn = AudioOutputDevice(uid: "BuiltIn", name: "MacBook Speakers", channelCount: 2, isDefault: true)
    static let desk = AudioOutputDevice(uid: "Desk", name: "Desk Interface", channelCount: 4, isDefault: false)
    static let standard = [builtIn, desk]

    func outputDevices() -> [AudioOutputDevice] { lock.lock(); defer { lock.unlock() }; return list }

    func observeChanges(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        lock.lock(); let key = next; next += 1; handlers[key] = handler; lock.unlock()
        return { [weak self] in self?.lock.lock(); self?.handlers[key] = nil; self?.lock.unlock() }
    }

    var observerCount: Int { lock.lock(); defer { lock.unlock() }; return handlers.count }

    /// Replaces the list and tells every observer, as Core Audio does.
    func set(_ devices: [AudioOutputDevice]) {
        lock.lock(); list = devices; let all = Array(handlers.values); lock.unlock()
        all.forEach { $0() }
    }
}

/// Records what the model asks of one cue's engine.
@MainActor
final class FakeCueEngine: AudioCueEngine {
    var onFinished: (@MainActor () -> Void)?
    var onLevels: (@MainActor (AudioLevels) -> Void)?
    var onDeviceLost: (@MainActor (String) -> Void)?
    var onFailure: (@MainActor (String) -> Void)?
    var calls: [String] = []
    var playedURL: URL?
    var loops = false
    var volume: Float = -1
    var muted: Bool? = nil
    var deviceUID: String?? = .none          // .none: never told; .some(nil): told "default"
    var failWith: Error?
    var stopped = false

    func play(url: URL, from seconds: Double, loops: Bool) throws {
        if let failWith { throw failWith }
        calls.append("play"); playedURL = url; self.loops = loops
    }
    func pause() { calls.append("pause") }
    func resume() { calls.append("resume") }
    func seek(to seconds: Double) { calls.append("seek \(seconds)") }
    func stop() { calls.append("stop"); stopped = true }
    func setLoops(_ loops: Bool) { self.loops = loops; calls.append("loops \(loops)") }
    func setLevel(volume: Float, muted: Bool) { self.volume = volume; self.muted = muted }
    func setOutputDevice(uid: String?) { deviceUID = .some(uid) }
}

struct PlayFailure: LocalizedError { var errorDescription: String? { "The file is damaged." } }

/// Hands out one fake engine per cue and remembers them.
@MainActor
final class EngineBin {
    var engines: [FakeCueEngine] = []
    var failure: Error?
    func make() -> FakeCueEngine {
        let engine = FakeCueEngine()
        engine.failWith = failure
        engines.append(engine)
        return engine
    }
}

@MainActor
final class AudioRig {
    let store: LibraryStore
    let clock = FakeClock()
    let files = FakeFiles()
    let devices: FakeDeviceList
    let model: AudioModel
    private let bin = EngineBin()
    var engines: [FakeCueEngine] { bin.engines }
    var engineFailure: Error? { get { bin.failure } set { bin.failure = newValue } }
    var programmeChanges: [String?] = []

    init(store: LibraryStore? = nil, devices: FakeDeviceList = FakeDeviceList()) throws {
        self.store = try store ?? LibraryStore.inMemory()
        self.devices = devices
        let clock = self.clock, files = self.files, bin = self.bin
        model = AudioModel(store: self.store, devices: devices, makeEngine: { bin.make() }, now: { clock.now() },
                           isAvailable: { files.isAvailable($0) })
        model.onProgrammeDeviceChange = { [unowned self] in programmeChanges.append($0) }
    }

    static func sound(_ name: String, duration: Double? = 30) -> MediaAsset {
        MediaAsset(name: name, kind: .audio, path: "/audio/\(name).mp3", duration: duration)
    }

    /// Puts three sounds and a video in the bin, loads the model.
    func loaded(_ assets: [MediaAsset]? = nil) async -> [MediaAsset] {
        let all = assets ?? [Self.sound("hymn"), Self.sound("bed"), Self.sound("chime", duration: 5),
                             MediaAsset(name: "loop", kind: .video, path: "/media/loop.mov", duration: 10)]
        await model.load()
        model.setAssets(all)
        return all
    }

    /// A second model on the same library, as after a relaunch.
    func relaunched(devices: FakeDeviceList? = nil) throws -> AudioRig { try AudioRig(store: store, devices: devices ?? self.devices) }

    var active: [FakeCueEngine] { engines.filter { !$0.stopped } }
}

@MainActor
@Suite struct AudioListAndPlayTests {
    @Test func theListHoldsOnlyTheSoundFilesOfTheBin() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        #expect(rig.model.assets.map(\.name) == ["hymn", "bed", "chime"])
        #expect(rig.model.assets.allSatisfy { $0.kind == .audio })
        #expect(all.count == 4)
    }

    @Test func playOpensTheFileOnItsOwnEngineWithTheCurrentLevelAndDevice() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setVolume(0.3)
        rig.model.play(all[0].id)
        let engine = try #require(rig.engines.first)
        #expect(engine.playedURL == URL(fileURLWithPath: "/audio/hymn.mp3") && engine.loops == false)
        #expect(abs(engine.volume - 0.3) < 0.0001 && engine.muted == false)
        #expect(engine.deviceUID == .some(nil))                     // system default until the operator chooses
        #expect(rig.model.activeCues.map(\.assetID) == [all[0].id])
        #expect(rig.model.lastError == nil)
    }

    @Test func aVideoOrAnUnknownIdIsNotPlayedAsASound() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[3].id)
        rig.model.play(UUID())
        #expect(rig.engines.isEmpty && rig.model.activeCues.isEmpty)
    }

    @Test func aFileThatCannotBeReadIsReportedAndNothingStarts() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.files.lose(all[0].path)
        rig.model.play(all[0].id)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("hymn") && message.contains("missing or cannot be read") && message.contains("/audio/hymn.mp3"))
        #expect(rig.engines.isEmpty && rig.model.activeCues.isEmpty)
    }

    @Test func aFileTheEngineCannotOpenIsReportedAndTheCueThatWasPlayingKeepsPlaying() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.engineFailure = PlayFailure()
        rig.model.play(all[1].id)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("bed") && message.contains("The file is damaged."))
        #expect(rig.model.activeCues.map(\.assetID) == [all[0].id])
        #expect(rig.engines[0].stopped == false)
        #expect(rig.engines[1].stopped)                              // the engine that failed to open is released
    }

    @Test func pressingPlayOnAPlayingCueDoesNotRestartIt() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.clock.advance(3)
        rig.model.play(all[0].id)
        #expect(rig.engines.count == 1)
        #expect(rig.model.readout(for: all[0].id)?.position == 3)
    }

    @Test func removingTheFileFromTheBinStopsItsCue() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.model.setAssets(Array(all.dropFirst()))
        #expect(rig.model.activeCues.isEmpty && rig.engines[0].stopped)
    }
}

@MainActor
@Suite struct AudioOneAtATimeTests {
    @Test func startingACueStopsTheOneThatWasPlaying() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.model.play(all[1].id)
        #expect(rig.model.activeCues.map(\.assetID) == [all[1].id])
        #expect(rig.engines[0].stopped && !rig.engines[1].stopped)
        #expect(rig.model.currentID == all[1].id)
    }

    @Test func anOverlapCueStartsWithoutStoppingAnything() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[1].id)
        rig.model.play(all[0].id)
        rig.model.play(all[1].id)
        #expect(Set(rig.model.activeCues.map(\.assetID)) == [all[0].id, all[1].id])
        #expect(rig.active.count == 2)
    }

    @Test func aNormalCueStopsTheOtherNormalCuesButNotAnOverlapBed() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[1].id)                  // the bed
        rig.model.play(all[1].id)
        rig.model.play(all[0].id)
        rig.model.play(all[2].id)                                   // replaces the hymn, the bed plays on
        #expect(Set(rig.model.activeCues.map(\.assetID)) == [all[1].id, all[2].id])
        #expect(rig.engines[0].stopped == false && rig.engines[1].stopped)      // engine 0 is the bed, 1 the hymn
    }

    @Test func theOverlapMarkSurvivesARelaunch() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[1].id)
        await rig.model.flush()
        let again = try rig.relaunched()
        _ = await again.loaded(all)
        #expect(again.model.overlapIDs == [all[1].id])
        rig.model.setOverlap(false, for: all[1].id)
        await rig.model.flush()
        let third = try rig.relaunched()
        _ = await third.loaded(all)
        #expect(third.model.overlapIDs.isEmpty)
    }
}

@MainActor
@Suite struct AudioTransportTests {
    @Test func pauseResumeAndSeekFollowTheTransportClock() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        let id = all[0].id
        rig.model.play(id)
        rig.clock.advance(4)
        #expect(rig.model.readout(for: id)?.position == 4 && rig.model.readout(for: id)?.status == .playing)
        rig.model.pause(id)
        rig.clock.advance(10)
        #expect(rig.model.readout(for: id)?.position == 4 && rig.model.readout(for: id)?.status == .paused)
        rig.model.resume(id)
        rig.clock.advance(1)
        #expect(rig.model.readout(for: id)?.position == 5)
        rig.model.seek(id, to: 20)
        #expect(rig.model.readout(for: id)?.position == 20 && rig.model.readout(for: id)?.duration == 30)
        #expect(rig.engines[0].calls == ["play", "pause", "resume", "seek 20.0"])
    }

    @Test func seekingPastTheEndIsClampedAndAnUnknownCueIsIgnored() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.model.seek(all[0].id, to: 9999)
        #expect(rig.model.readout(for: all[0].id)?.position == 30)
        rig.model.pause(UUID()); rig.model.resume(UUID()); rig.model.seek(UUID(), to: 3); rig.model.stop(UUID())
        #expect(rig.model.activeCues.count == 1)
    }

    @Test func stopTakesTheCueAwayAndSilencesTheMeter() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.engines[0].onLevels?(AudioLevels(peak: [0.5, 0.5], rms: [0.3, 0.3]))
        #expect(rig.model.levels.peak == [0.5, 0.5])
        rig.model.stop(all[0].id)
        #expect(rig.model.activeCues.isEmpty && rig.engines[0].stopped)
        #expect(rig.model.levels == .silent())
        #expect(rig.model.readout(for: all[0].id) == nil)
    }

    @Test func theClockEndsACueThatDoesNotLoopAndTheEngineReportEndsOneWithoutADuration() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded([AudioRig.sound("chime", duration: 5), AudioRig.sound("unknown", duration: nil)])
        rig.model.play(all[0].id)
        rig.clock.advance(4)
        #expect(rig.model.tick() == false && rig.model.activeCues.count == 1)
        rig.clock.advance(2)
        #expect(rig.model.tick() == true && rig.model.activeCues.isEmpty)
        #expect(rig.engines[0].stopped)

        rig.model.play(all[1].id)
        rig.clock.advance(100)
        #expect(rig.model.tick() == false)                            // no duration: the clock never ends it
        rig.engines[1].onFinished?()
        #expect(rig.model.activeCues.isEmpty)
    }

    @Test func aFinishReportFromAnEngineThatWasAlreadyStoppedChangesNothing() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        let old = rig.engines[0]
        rig.model.play(all[1].id)                                     // stops the first
        old.onFinished?()                                             // a late report from it
        #expect(rig.model.activeCues.map(\.assetID) == [all[1].id])
    }

    @Test func aLoopingCueNeverEndsAndTheSwitchWorksWhilePlaying() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        let id = all[2].id                                            // 5 s
        rig.model.setLoops(true, for: id)
        rig.model.play(id)
        #expect(rig.engines[0].loops)
        rig.clock.advance(12)
        #expect(rig.model.tick() == false && rig.model.readout(for: id)?.position == 2)
        rig.model.setLoops(false, for: id)                            // position is kept, the engine is told
        #expect(rig.engines[0].loops == false && rig.model.readout(for: id)?.position == 2)
        rig.clock.advance(4)
        #expect(rig.model.tick() == true && rig.model.activeCues.isEmpty)
    }
}

@MainActor
@Suite struct AudioLevelTests {
    @Test func volumeIsClampedAppliedToEveryCueAndKeptAcrossARelaunch() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[0].id); rig.model.setOverlap(true, for: all[1].id)
        rig.model.play(all[0].id); rig.model.play(all[1].id)
        rig.model.setVolume(0.2)
        #expect(rig.engines.allSatisfy { abs($0.volume - 0.2) < 0.0001 })
        rig.model.setVolume(7)
        #expect(rig.model.volume == 1)
        rig.model.setVolume(.nan)
        #expect(rig.model.volume == 0)
        rig.model.setVolume(0.25); rig.model.setMuted(true)
        #expect(rig.engines.allSatisfy { $0.muted == true })
        await rig.model.flush()
        let again = try rig.relaunched()
        _ = await again.loaded(all)
        #expect(again.model.volume == 0.25 && again.model.isMuted)
        again.model.play(all[0].id)
        #expect(again.engines.first?.muted == true && abs((again.engines.first?.volume ?? 0) - 0.25) < 0.0001)
    }

    @Test func theMeterShowsTheLoudestOfTheCuesAndGoesQuietWhenTheLastStops() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[0].id); rig.model.setOverlap(true, for: all[1].id)
        rig.model.play(all[0].id); rig.model.play(all[1].id)
        rig.engines[0].onLevels?(AudioLevels(peak: [0.2, 0.6], rms: [0.1, 0.3]))
        rig.engines[1].onLevels?(AudioLevels(peak: [0.5, 0.1], rms: [0.2, 0.05]))
        #expect(rig.model.levels == AudioLevels(peak: [0.5, 0.6], rms: [0.2, 0.3]))
        rig.model.stop(all[0].id)
        #expect(rig.model.levels == AudioLevels(peak: [0.5, 0.1], rms: [0.2, 0.05]))
        rig.model.stop(all[1].id)
        #expect(rig.model.levels == .silent())
    }

    @Test func aMuteOrLevelChangeIsReportedToTheApp() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        var seen: [(Float, Bool)] = []
        rig.model.onLevelChange = { seen.append(($0, $1)) }
        rig.model.setVolume(0.5); rig.model.setVolume(0.5); rig.model.setMuted(true); rig.model.setMuted(true)
        #expect(seen.count == 2 && seen[0] == (0.5, false) && seen[1] == (0.5, true))
    }
}

@MainActor
@Suite struct AudioDeviceTests {
    private let desk = FakeDeviceList.desk
    private let builtIn = FakeDeviceList.builtIn

    @Test func nothingChosenMeansTheSystemDefault() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        #expect(rig.model.programmeDeviceUID == nil && rig.model.effectiveDeviceUID == nil)
        #expect(rig.model.devices.map(\.uid) == ["BuiltIn", "Desk"])
        #expect(rig.model.deviceNotice == nil && rig.model.lastError == nil)
    }

    @Test func choosingADeviceSendsEveryPlayingCueThereAndTellsTheApp() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.programmeChanges.removeAll()
        rig.model.chooseDevice("Desk")
        #expect(rig.model.programmeDeviceUID == "Desk" && rig.model.effectiveDeviceUID == "Desk")
        #expect(rig.engines[0].deviceUID == .some("Desk"))
        #expect(rig.programmeChanges == ["Desk"])
        rig.model.play(all[1].id)                                     // a later cue goes to the same place
        #expect(rig.engines[1].deviceUID == .some("Desk"))
        rig.model.chooseDevice(nil)
        #expect(rig.engines[1].deviceUID == .some(nil) && rig.programmeChanges == ["Desk", nil])
    }

    @Test func choosingTheSameDeviceAgainDoesNotTellTheAppAgain() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        rig.model.chooseDevice("Desk")
        rig.programmeChanges.removeAll()
        rig.model.chooseDevice("Desk")
        #expect(rig.programmeChanges.isEmpty)
    }

    @Test func choosingADeviceThatIsNotThereFallsBackToTheDefaultAndSaysSo() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.play(all[0].id)
        rig.model.chooseDevice("Ghost")
        #expect(rig.model.programmeDeviceUID == nil && rig.model.effectiveDeviceUID == nil)
        #expect(rig.engines[0].deviceUID == .some(nil))
        let message = try #require(rig.model.lastError)
        #expect(message.contains("Ghost") && message.contains("not connected") && message.contains("system default"))
        await rig.model.flush()
        let again = try rig.relaunched()
        _ = await again.loaded()
        #expect(again.model.programmeDeviceUID == nil)
    }

    @Test func theChosenDeviceSurvivesARelaunch() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        rig.model.chooseDevice("Desk")
        await rig.model.flush()
        let again = try rig.relaunched()
        _ = await again.loaded()
        #expect(again.model.programmeDeviceUID == "Desk" && again.model.effectiveDeviceUID == "Desk")
        #expect(again.programmeChanges.last == "Desk")
        // Choosing the default again is remembered as well.
        again.model.chooseDevice(nil)
        await again.model.flush()
        let third = try rig.relaunched()
        _ = await third.loaded()
        #expect(third.model.programmeDeviceUID == nil)
    }

    @Test func aStoredDeviceThatIsNotConnectedAtLaunchPlaysOnTheDefaultButIsKeptAndReported() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        rig.model.chooseDevice("Desk")
        await rig.model.flush()
        let again = try rig.relaunched(devices: FakeDeviceList([builtIn]))
        let all = await again.loaded()
        #expect(again.model.programmeDeviceUID == "Desk" && again.model.effectiveDeviceUID == nil)
        let notice = try #require(again.model.deviceNotice)
        #expect(notice.contains("Desk Interface") && notice.contains("system default"))
        #expect(again.model.lastError != nil)
        again.model.play(all[0].id)
        #expect(again.engines[0].deviceUID == .some(nil))
        // The drive comes back: the choice is honoured again without the operator doing anything.
        again.devices.set([builtIn, desk])
        await settle()
        #expect(again.model.effectiveDeviceUID == "Desk" && again.model.deviceNotice == nil)
        #expect(again.engines[0].deviceUID == .some("Desk"))
    }

    @Test func aDeviceThatDisappearsWhilePlayingFallsBackKeepsPlayingAndReports() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.chooseDevice("Desk")
        rig.model.play(all[0].id)
        rig.model.dismissError()
        rig.devices.set([builtIn])
        await settle()
        #expect(rig.model.effectiveDeviceUID == nil && rig.model.programmeDeviceUID == "Desk")
        #expect(rig.engines[0].deviceUID == .some(nil) && rig.engines[0].stopped == false)
        #expect(rig.model.activeCues.count == 1)
        let message = try #require(rig.model.lastError)
        #expect(message.contains("Desk Interface") && message.contains("still playing"))
        #expect(rig.model.deviceNotice != nil)
        #expect(rig.programmeChanges.last == .some(nil))
        // And it comes back.
        rig.devices.set([builtIn, desk])
        await settle()
        #expect(rig.engines[0].deviceUID == .some("Desk") && rig.model.deviceNotice == nil)
    }

    @Test func anEngineThatLosesItsDeviceByItselfIsReportedOnce() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.chooseDevice("Desk")
        rig.model.play(all[0].id)
        rig.model.dismissError()
        rig.engines[0].onDeviceLost?("Desk")
        let first = try #require(rig.model.lastError)
        #expect(first.contains("Desk Interface"))
        rig.model.dismissError()
        rig.engines[0].onDeviceLost?("Desk")                          // the same loss again: not repeated
        #expect(rig.model.lastError == nil)
    }

    @Test func theListChangingWithoutTheChosenDeviceMovingDoesNothingVisible() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        rig.model.chooseDevice("Desk")
        rig.programmeChanges.removeAll()
        rig.devices.set([builtIn, desk, AudioOutputDevice(uid: "USB", name: "USB Headset", channelCount: 2, isDefault: false)])
        await settle()
        #expect(rig.model.devices.count == 3 && rig.programmeChanges.isEmpty && rig.model.lastError == nil)
    }

    @Test func stopObservingReleasesTheDeviceListener() async throws {
        let rig = try AudioRig()
        _ = await rig.loaded()
        #expect(rig.devices.observerCount == 1)
        rig.model.shutdown()
        #expect(rig.devices.observerCount == 0)
    }
}

@MainActor
@Suite struct AudioShowControlTests {
    private struct Rig {
        let workspace: WorkspaceModel
        let audio: AudioRig
        let ids: [UUID]
    }

    private func rig() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let workspace = WorkspaceModel(store: store)
        await workspace.load()
        let audio = try AudioRig(store: store)
        let all = await audio.loaded()
        // The same wiring the app makes: the show state reaches the audio, and Clear all does not.
        workspace.onShowChange = { state in audio.model.showStateChanged(isLive: !state.isStopped) }
        let song = try #require(await workspace.importLyrics(title: "Song", primaryText: "one\n\ntwo", secondaryText: nil, maxLines: 2))
        await workspace.openPresentation(song.id)
        await workspace.goLive()
        audio.model.play(all[0].id)
        #expect(audio.model.activeCues.count == 1)
        return Rig(workspace: workspace, audio: audio, ids: all.map(\.id))
    }

    @Test func stopStopsTheCues() async throws {
        let r = try await rig()
        r.workspace.stop()
        #expect(r.audio.model.activeCues.isEmpty && r.audio.engines[0].stopped)
    }

    @Test func clearLeavesTheCuePlaying() async throws {
        let r = try await rig()
        r.workspace.clear()
        #expect(r.workspace.show.isCleared)
        #expect(r.audio.model.activeCues.count == 1 && r.audio.engines[0].stopped == false)
    }

    @Test func clearAllLeavesTheCuePlayingToo() async throws {
        let r = try await rig()
        r.workspace.clearAll()
        #expect(r.workspace.show.isCleared)
        #expect(r.audio.model.activeCues.count == 1 && r.audio.engines[0].stopped == false)
    }

    @Test func aCueStartedWhileTheScreensAreStoppedIsNotStoppedByTheShowStayingStopped() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.showStateChanged(isLive: false)
        rig.model.play(all[0].id)                                     // sound check before the service
        rig.model.showStateChanged(isLive: false)                     // the show state changed, still stopped
        #expect(rig.model.activeCues.count == 1)
        rig.model.showStateChanged(isLive: true)
        rig.model.showStateChanged(isLive: false)                     // now the show really stops
        #expect(rig.model.activeCues.isEmpty)
    }

    @Test func stopAllStopsEveryCueIncludingOverlapOnes() async throws {
        let rig = try AudioRig()
        let all = await rig.loaded()
        rig.model.setOverlap(true, for: all[1].id)
        rig.model.play(all[0].id); rig.model.play(all[1].id)
        rig.model.stopAll()
        #expect(rig.model.activeCues.isEmpty && rig.engines.allSatisfy(\.stopped))
    }
}

/// Lets the main-actor hops the device-list observer makes finish.
@MainActor func settle() async { for _ in 0..<8 { await Task.yield() } }
