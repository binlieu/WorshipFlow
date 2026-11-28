// FIX-AB item 5 and 6 (MEDIA-010): a video clicked in the media bin is heard whatever its role; a slide's own background stays muted until the
// operator unmutes it. The values are what the registry is told (`onBackgroundAudioChange`), not time.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXAB_BinSoundTests {
    final class Heard { var calls: [(Float, Bool)] = []; var last: (Float, Bool)? { calls.last } }

    private func listen(_ rig: MediaRig) -> Heard {
        let heard = Heard()
        rig.model.onBackgroundAudioChange = { v, m in heard.calls.append((v, m)) }
        return heard
    }

    private func rigWithLoop() async throws -> (MediaRig, MediaAsset) {
        let rig = try MediaRig()
        let loop = await rig.add("loop.mov")
        rig.model.showStateChanged(isLive: true)
        return (rig, loop)
    }

    @Test func aVideoClickedInTheBinAsBackgroundIsHeard() async throws {
        let (rig, loop) = try await rigWithLoop()
        let heard = listen(rig)
        rig.model.setBackgroundFromBin(loop.id)
        #expect(rig.model.hasLiveBackgroundOverride)
        #expect(!rig.model.isBackgroundMuted && !rig.model.backgroundHeardMuted)
        #expect(heard.last?.1 == false, "the player was told to be heard")
    }

    @Test func aSlidesOwnBackgroundStaysMutedWhenItsSlideGoesLive() async throws {
        let (rig, loop) = try await rigWithLoop()
        let heard = listen(rig)
        var deck = ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "one")])
        deck.slides[0].background = MediaSelection(asset: loop)
        var show = ShowState()
        show.apply(.load(deck)); show.apply(.trigger(index: 0))
        #expect(LiveMedia.playing(override: rig.model.layers, state: show, at: 1000).background != nil, "the slide's loop is on")
        #expect(rig.model.backgroundHeardMuted, "and still silent")
        #expect(heard.calls.allSatisfy { $0.1 }, "nothing told the player to be heard")
    }

    @Test func aBinChoiceThatEndsLeavesTheNextSlideBackgroundSilentAgain() async throws {
        let (rig, loop) = try await rigWithLoop()
        rig.model.setBackgroundFromBin(loop.id)
        rig.model.dropBackgroundOverride()
        #expect(rig.model.backgroundHeardMuted, "the slide's own loop must not start making sound because the bin choice went")
    }

    @Test func blackoutStillSilencesABinBackgroundAndLiftingBringsItBack() async throws {
        let (rig, loop) = try await rigWithLoop()
        let heard = listen(rig)
        rig.model.setBackgroundFromBin(loop.id)
        rig.model.showStateChanged(isLive: true, isBlackedOut: true)
        #expect(heard.last?.1 == true && rig.model.backgroundHeardMuted)
        rig.model.showStateChanged(isLive: true, isBlackedOut: false)
        #expect(heard.last?.1 == false && !rig.model.backgroundHeardMuted)
    }

    @Test func theOperatorCanStillMuteABinBackgroundAndTheNextBinClickIsHeardAgain() async throws {
        let (rig, loop) = try await rigWithLoop()
        let other = await rig.add("other.mov")
        let heard = listen(rig)
        rig.model.setBackgroundFromBin(loop.id)
        rig.model.setBackgroundMuted(true)
        #expect(rig.model.isBackgroundMuted && heard.last?.1 == true)
        rig.model.setBackgroundFromBin(other.id)
        #expect(!rig.model.isBackgroundMuted && heard.last?.1 == false, "a click in the bin is heard")
    }

    @Test func anUnmuteByTheOperatorSurvivesTheBinChoiceEnding() async throws {
        let (rig, loop) = try await rigWithLoop()
        rig.model.setBackgroundFromBin(loop.id)
        rig.model.setBackgroundMuted(true)
        rig.model.setBackgroundMuted(false)         // the operator's own choice from now on
        rig.model.dropBackgroundOverride()
        #expect(!rig.model.isBackgroundMuted, "the operator's choice is kept, as MEDIA-010 says")
    }

    @Test func aPictureClickedInTheBinDoesNotUnmuteTheBackgroundSound() async throws {
        let rig = try MediaRig()
        let picture = await rig.add("still.png")
        rig.model.showStateChanged(isLive: true)
        rig.model.setBackgroundFromBin(picture.id)
        #expect(rig.model.isBackgroundMuted, "nothing to hear: a slide's loop that follows stays silent")
    }

    @Test func theBinsOldPathStaysMutedForCuesAndFolders() async throws {
        let (rig, loop) = try await rigWithLoop()
        rig.model.setBackground(loop.id)         // a cue's Set background: MEDIA-010's rule is untouched
        #expect(rig.model.backgroundHeardMuted)
    }
}
