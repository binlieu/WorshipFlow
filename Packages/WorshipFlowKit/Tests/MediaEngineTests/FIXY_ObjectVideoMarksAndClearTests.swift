// FIX-Y items 1 and 2 (SLIDE, MEDIA; REVIEW-5 L2, KI-280): a video object plays between the in and out marks of its bin clip, as the same clip does as
// a background or foreground layer; and Clear keeps the players of the objects (silenced) exactly where the slide's own background keeps playing.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct FIXY_ObjectVideoMarksAndClearTests {
    @Test func aVideoObjectLoopsInsideTheMarksOfItsClip() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())          // red for the first second, blue for the second
        let players = ObjectVideoPlayers()
        let r = ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: true, duration: 2, markIn: 1)
        players.apply([r])
        #expect(await TestMedia.wait { isBlue(players.pixelBuffer(for: r.assetID)) })
        var sawRed = false
        for _ in 0..<60 { if isRed(players.pixelBuffer(for: r.assetID)) { sawRed = true }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(!sawRed)                                                            // the red first second, before the in mark, is never shown
        players.closeAll()
    }

    @Test func aChangeOfMarksReopensTheClipAndEqualRequestsDoNot() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let id = UUID()
        let plain = ObjectVideoRequest(assetID: id, url: url, loops: true, muted: true, duration: 2)
        let marked = ObjectVideoRequest(assetID: id, url: url, loops: true, muted: true, duration: 2, markIn: 1, markOut: 2)
        players.apply([plain])
        let first = try #require(players.sourceIdentity(for: id))
        players.apply([plain])
        #expect(players.sourceIdentity(for: id) == first)
        players.apply([marked])
        #expect(players.sourceIdentity(for: id) != first)
        #expect(players.markRange(for: id)?.markIn == 1)
        players.closeAll()
    }

    // MARK: Clear

    private func state(after commands: [ShowCommand]) -> ShowState {
        var s = ShowState()
        let slide = SlideContent(primary: "One")
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [slide, SlideContent(primary: "Two")])))
        s.apply(.trigger(index: 0))
        for c in commands { s.apply(c) }
        return s
    }

    @Test func theHoldRuleMatchesWhereTheSlidesOwnBackgroundKeepsPlaying() {
        #expect(!ObjectVideoPlayers.holds(state(after: [])))                        // on air: normal
        #expect(ObjectVideoPlayers.holds(state(after: [.blackout])))                // Blackout: background kept
        #expect(ObjectVideoPlayers.holds(state(after: [.clear])))                   // Clear words: background kept
        #expect(ObjectVideoPlayers.holds(state(after: [.clearAll])))                // Clear all: the same state
        #expect(!ObjectVideoPlayers.holds(state(after: [.clearBackground])))        // Clear background: the objects are still drawn; they are not held
        #expect(!ObjectVideoPlayers.holds(state(after: [.stop])))                   // Stop closes everything
        #expect(!ObjectVideoPlayers.holds(ShowState()))                             // nothing live
    }

    @Test func clearKeepsThePlayersSilencedAndUnClearingDoesNotReopenThem() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: false, duration: 2)
        players.apply([r], hidden: false)
        let before = try #require(players.sourceIdentity(for: r.assetID))
        players.apply([], hidden: true)                                             // Clear: the composed scene has no objects
        #expect(players.sourceIdentity(for: r.assetID) == before)
        #expect(players.isMuted(r.assetID) == true)
        players.apply([r], hidden: false)
        #expect(players.sourceIdentity(for: r.assetID) == before)
        #expect(players.isMuted(r.assetID) == false)
        players.apply([], hidden: false)                                            // Stop (or the slide left Live): everything closes
        #expect(players.openAssetIDs.isEmpty)
        players.closeAll()
    }
}
