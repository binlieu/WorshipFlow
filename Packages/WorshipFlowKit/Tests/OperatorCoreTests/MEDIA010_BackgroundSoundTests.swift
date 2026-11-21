// MEDIA-010 item 3: "the audio cannot unmute while the video is background". A background video starts muted, which
// stays, but the operator can unmute it, the state shown is the state heard, Next keeps it, Blackout silences it and
// restores the chosen state afterwards.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct MEDIA010_BackgroundSoundTests {
    private func rig() async throws -> (MediaRig, MediaAsset, [(Float, Bool)]) {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.showStateChanged(isLive: true)
        return (rig, loop, [])
    }

    final class Heard { var calls: [(Float, Bool)] = []; var last: (Float, Bool)? { calls.last } }

    private func listen(_ rig: MediaRig) -> Heard {
        let heard = Heard()
        rig.model.onBackgroundAudioChange = { v, m in heard.calls.append((v, m)) }
        return heard
    }

    @Test func aBackgroundVideoIsMutedByDefaultAndThatIsWhatIsShown() async throws {
        let (rig, loop, _) = try await rig()
        rig.model.setBackground(loop.id)
        #expect(rig.model.isBackgroundMuted)
        #expect(rig.model.backgroundHeardMuted)
    }

    @Test func theOperatorCanUnmuteItAndThePlayerIsToldSoTheStateShownIsTheStateHeard() async throws {
        let (rig, loop, _) = try await rig()
        let heard = listen(rig)
        rig.model.setBackground(loop.id)
        rig.model.setBackgroundMuted(false)
        #expect(!rig.model.isBackgroundMuted && !rig.model.backgroundHeardMuted)
        let last = try #require(heard.last)
        #expect(last.1 == false, "the player was told to unmute")
        rig.model.setBackgroundMuted(true)
        #expect(heard.last?.1 == true && rig.model.backgroundHeardMuted)
    }

    @Test func theUnmuteSurvivesNextAndANewBackgroundChoice() async throws {
        let (rig, loop, _) = try await rig()
        let other = await rig.add("other.mov")
        let heard = listen(rig)
        rig.model.setBackground(loop.id)
        rig.model.setBackgroundMuted(false)
        rig.model.showStateChanged(isLive: true)       // Next within the show: the app passes the state on again
        #expect(!rig.model.isBackgroundMuted)
        rig.model.setBackground(other.id)
        #expect(!rig.model.isBackgroundMuted, "a new choice keeps the operator's sound choice")
        #expect(heard.last?.1 == false)
    }

    @Test func blackoutSilencesItAndLiftingRestoresTheChosenState() async throws {
        let (rig, loop, _) = try await rig()
        let heard = listen(rig)
        rig.model.setBackground(loop.id)
        rig.model.setBackgroundMuted(false)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        #expect(heard.last?.1 == true && rig.model.backgroundHeardMuted)
        #expect(!rig.model.isBackgroundMuted, "the operator's own choice is not changed")
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(heard.last?.1 == false && !rig.model.backgroundHeardMuted)
    }

    @Test func aMuteChosenDuringBlackoutStaysSilentWhenItLifts() async throws {
        let (rig, loop, _) = try await rig()
        let heard = listen(rig)
        rig.model.setBackground(loop.id)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        rig.model.setBackgroundMuted(false)
        #expect(heard.calls.allSatisfy { $0.1 }, "still silent while Blackout is on")
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(heard.last?.1 == false)
    }

    @Test func theForegroundClipsMuteIsASeparateChoice() async throws {
        let (rig, loop, _) = try await rig()
        rig.model.setBackground(loop.id)
        rig.model.setBackgroundMuted(false)
        #expect(!rig.model.isMuted == true, "the clip over the words was not muted by that")
        rig.model.setMuted(true)
        #expect(!rig.model.isBackgroundMuted)
    }
}
