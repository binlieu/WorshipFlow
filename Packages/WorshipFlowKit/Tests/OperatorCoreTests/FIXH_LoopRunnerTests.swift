// FIX-H item 1 (UI-005b): the announcements loop must never replace a clip the operator played, and it ends (and says so) when the
// foreground is no longer the loop's. Item 6 (UI-005b): the player says whether a file started. The runner under test is the
// loop's decision logic, now in OperatorCore behind the foreground and audio ports, driven here by a fake clock and fake players.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
final class FIXHForeground: ForegroundPort {
    var names: [UUID: String] = [:]
    var unreadable: Set<UUID> = []
    var refusal: String?
    var current: UUID?
    var starts = 0
    var loops = false
    var played: [UUID] = []
    var stopCount = 0

    func add(_ id: UUID, _ name: String) { names[id] = name }
    func name(of assetID: UUID) -> String? { names[assetID] }
    func isReadable(_ assetID: UUID) -> Bool { names[assetID] != nil && !unreadable.contains(assetID) }
    var foregroundAssetID: UUID? { current }
    var foregroundStarts: Int { starts }
    func startForeground(_ assetID: UUID) -> String? {
        if let refusal { return refusal }
        guard isReadable(assetID) else { return "not readable" }
        current = assetID; starts += 1; loops = false; played.append(assetID)
        return nil
    }
    func setForegroundLoops(_ on: Bool) { loops = on }
    func stopForeground() { current = nil; stopCount += 1; loops = false }

    /// The operator plays something from the bin, the dock or a cue.
    func operatorPlays(_ id: UUID) { current = id; starts += 1; loops = false }
    func operatorClears() { current = nil }
}

@MainActor
final class FIXHAudio: AudioPlayerPort {
    var names: [UUID: String] = [:]
    var unreadable: Set<UUID> = []
    var refusal: String?
    var playing: [UUID] = []
    var stopped: [UUID] = []
    func name(of assetID: UUID) -> String? { names[assetID] }
    func isReadable(_ assetID: UUID) -> Bool { names[assetID] != nil && !unreadable.contains(assetID) }
    func startSound(_ assetID: UUID) -> String? {
        if let refusal { return refusal }
        playing.append(assetID); return nil
    }
    func stop(_ assetID: UUID) { stopped.append(assetID) }
}

final class FIXHClock: @unchecked Sendable {
    var seconds: Double = 1000
}

@MainActor
@Suite struct FIXH_LoopRunnerTests {
    let one = MediaItemSpec(assetID: UUID(), name: "Welcome.png", kind: .image)
    let two = MediaItemSpec(assetID: UUID(), name: "Picnic.png", kind: .image)
    let other = MediaItemSpec(assetID: UUID(), name: "Testimony.mov", kind: .video)

    struct Rig {
        var fg: FIXHForeground
        var audio: FIXHAudio
        var clock: FIXHClock
        var runner: MediaItemRunner
        var ended: Counter
        var previews: [UUID?] = []
    }
    @MainActor final class Counter { var count = 0 }

    func rig() -> Rig {
        let fg = FIXHForeground()
        for s in [one, two, other] { fg.add(s.assetID, s.name) }
        let audio = FIXHAudio()
        let clock = FIXHClock()
        let runner = MediaItemRunner(foreground: fg, audio: audio, preview: { _ in }, now: { clock.seconds })
        let ended = Counter()
        runner.onLoopEnded = { ended.count += 1 }
        return Rig(fg: fg, audio: audio, clock: clock, runner: runner, ended: ended)
    }

    var loop: AnnouncementsSpec { AnnouncementsSpec(label: "Announcements loop", items: [one, two], secondsPerPicture: 10) }

    @Test func theLoopMovesThroughItsPicturesOnTheClock() {
        let r = rig()
        #expect(r.runner.handle(.startLoop(loop)) == .ok)
        #expect(r.fg.played == [one.assetID])
        r.clock.seconds += 9; r.runner.tick()
        #expect(r.fg.played == [one.assetID])
        r.clock.seconds += 1; r.runner.tick()
        #expect(r.fg.played == [one.assetID, two.assetID])
        r.clock.seconds += 10; r.runner.tick()
        #expect(r.fg.played == [one.assetID, two.assetID, one.assetID])
        #expect(r.ended.count == 0)
    }

    @Test func aClipTheOperatorPlaysIsNeverReplacedByTheLoop() {
        let r = rig()
        _ = r.runner.handle(.startLoop(loop))
        r.fg.operatorPlays(other.assetID)                    // from the bin, the dock or a cue
        r.clock.seconds += 10; r.runner.tick()
        #expect(r.fg.played == [one.assetID])                 // the loop put nothing up after the operator's clip
        #expect(r.fg.current == other.assetID && r.fg.stopCount == 0)
        #expect(r.ended.count == 1)                            // and the model is told the loop is over
        r.clock.seconds += 50; r.runner.tick()
        #expect(r.ended.count == 1 && r.fg.current == other.assetID)
    }

    @Test func theSamePictureStartedAgainByTheOperatorIsStillTheOperators() {
        let r = rig()
        _ = r.runner.handle(.startLoop(loop))
        r.fg.operatorPlays(one.assetID)                      // the loop's own picture, but started by someone else
        r.clock.seconds += 10; r.runner.tick()
        #expect(r.fg.played == [one.assetID] && r.ended.count == 1 && r.fg.stopCount == 0)
    }

    @Test func clearingTheForegroundEndsTheLoopAndTellsTheModel() {
        let r = rig()
        _ = r.runner.handle(.startLoop(loop))
        r.fg.operatorClears()
        r.runner.tick()
        #expect(r.ended.count == 1 && r.fg.played == [one.assetID])
        r.clock.seconds += 30; r.runner.tick()
        #expect(r.fg.played == [one.assetID] && r.ended.count == 1)
    }

    @Test func stoppingTheLoopStopsOnlyItsOwnPicture() {
        let r = rig()
        _ = r.runner.handle(.startLoop(loop))
        _ = r.runner.handle(.stopLoop(loop))
        #expect(r.fg.current == nil && r.fg.stopCount == 1 && r.ended.count == 0)      // asked to stop by the model: nothing to report back
        let again = rig()
        _ = again.runner.handle(.startLoop(loop))
        again.fg.operatorPlays(other.assetID)
        _ = again.runner.handle(.stopLoop(loop))
        #expect(again.fg.current == other.assetID && again.fg.stopCount == 0)       // the operator's clip stays
    }

    @Test func aVideoLoopRepeatsAndAlsoEndsWhenTheOperatorPlaysSomethingElse() {
        let r = rig()
        let video = AnnouncementsSpec(label: "Video loop", items: [other])
        #expect(r.runner.handle(.startLoop(video)) == .ok)
        #expect(r.fg.loops)
        r.fg.operatorPlays(one.assetID)
        r.runner.tick()
        #expect(r.ended.count == 1 && r.fg.current == one.assetID)
    }

    @Test func aLoopWhosePicturesAreAllMissingOrUnreadableDoesNotStartAndNamesTheLoop() {
        let r = rig()
        r.fg.unreadable = [one.assetID, two.assetID]
        let outcome = r.runner.handle(.startLoop(loop))
        guard case .failed(let text) = outcome else { Issue.record("expected a failure, got \(outcome)"); return }
        #expect(text.contains("Announcements loop"))
        #expect(r.fg.played.isEmpty && r.fg.current == nil)
    }

    @Test func aMissingFileIsReportedByNameAndNothingStarts() {
        let r = rig()
        let ghost = MediaItemSpec(assetID: UUID(), name: "Gone.mov", kind: .video)
        let outcome = r.runner.handle(.play(ghost))
        guard case .failed(let text) = outcome else { Issue.record("expected a failure, got \(outcome)"); return }
        #expect(text.contains("Gone.mov") && r.fg.played.isEmpty)
    }

    @Test func aFileThatIsListedButNotReadableFailsToo() {
        let r = rig()
        r.fg.unreadable = [other.assetID]
        let outcome = r.runner.handle(.play(other))
        guard case .failed(let text) = outcome else { Issue.record("expected a failure, got \(outcome)"); return }
        #expect(text.contains("Testimony.mov") && r.fg.played.isEmpty)
    }

    @Test func aPlayerThatRefusesIsReportedWithItsOwnReason() {
        let r = rig()
        r.fg.refusal = "Take a slide live first."
        #expect(r.runner.handle(.play(other)) == .failed("Take a slide live first."))
    }

    @Test func aSoundWithNoAudioPlayerSaysSo() {
        let fg = FIXHForeground()
        let runner = MediaItemRunner(foreground: fg, audio: nil, preview: { _ in }, now: { 0 })
        let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in.m4a", kind: .audio)
        guard case .failed(let text) = runner.handle(.play(sound)) else { Issue.record("expected a failure"); return }
        #expect(text.contains("Walk-in.m4a") && text.localizedCaseInsensitiveContains("sound"))
    }

    @Test func aSoundIsPlayedAndStoppedThroughTheAudioPort() {
        let r = rig()
        let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in.m4a", kind: .audio)
        r.audio.names[sound.assetID] = sound.name
        #expect(r.runner.handle(.play(sound)) == .ok)
        #expect(r.audio.playing == [sound.assetID])
        _ = r.runner.handle(.stop(sound))
        #expect(r.audio.stopped == [sound.assetID])
        r.audio.refusal = "The file is missing."
        #expect(r.runner.handle(.play(sound)) == .failed("The file is missing."))
    }

    @Test func aSoundThatIsListedButNotReadableFailsBeforeAnythingChanges() {
        let r = rig()
        let sound = MediaItemSpec(assetID: UUID(), name: "Walk-in.m4a", kind: .audio)
        r.audio.names[sound.assetID] = sound.name
        r.audio.unreadable = [sound.assetID]
        guard let problem = r.runner.preflight(.media(sound)) else { Issue.record("expected a problem"); return }
        #expect(problem.contains("Walk-in.m4a"))
        r.audio.unreadable = []
        #expect(r.runner.preflight(.media(sound)) == nil)
    }
}
