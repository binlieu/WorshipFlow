// FIX-AC item A (MEDIA, KI-286): under Clear words a video object's player keeps playing and is heard, as the slide's own background layer is;
// Clear all and Blackout keep it silenced; Stop closes it; a muted object stays muted; un-clearing never reopens the player.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct FIXAC_ObjectVideoSoundUnderClearTests {
    private func live(after commands: [ShowCommand]) -> ShowState {
        var s = ShowState()
        s.apply(.load(ShowDeck(presentationID: UUID(), slides: [SlideContent(primary: "One"), SlideContent(primary: "Two")])))
        s.apply(.trigger(index: 0))
        for c in commands { s.apply(c) }
        return s
    }

    @Test func theSilenceRuleSparesClearWordsOnly() {
        #expect(!ObjectVideoPlayers.silences(live(after: []), clearedAll: false))                     // on air
        #expect(!ObjectVideoPlayers.silences(live(after: [.clear]), clearedAll: false))              // Clear words: heard
        #expect(ObjectVideoPlayers.silences(live(after: [.clearAll]), clearedAll: true))              // Clear all: silent
        #expect(ObjectVideoPlayers.silences(live(after: [.blackout]), clearedAll: false))             // Blackout: silent
        #expect(ObjectVideoPlayers.silences(live(after: [.clear, .blackout]), clearedAll: false))     // Blackout over Clear words: silent
        #expect(!ObjectVideoPlayers.silences(live(after: [.clearBackground]), clearedAll: false))     // not held at all
        #expect(ObjectVideoPlayers.silences(live(after: [.clear]), clearedAll: true))                 // the flag (Clear all pressed first) keeps it silent
        #expect(!ObjectVideoPlayers.silences(live(after: [.trigger(index: 1)]), clearedAll: true))    // a new slide lifts a stale flag
    }

    @Test func clearWordsKeepsThePlayerAudibleAndClearAllAndBlackoutSilenceIt() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let loud = ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: false, duration: 2)
        let quiet = ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: true, duration: 2)
        players.apply([loud, quiet], hidden: false, silenced: false)
        let loudPlayer = try #require(players.sourceIdentity(for: loud.assetID))
        let quietPlayer = try #require(players.sourceIdentity(for: quiet.assetID))
        #expect(players.isMuted(loud.assetID) == false && players.isMuted(quiet.assetID) == true)

        players.apply([], hidden: true, silenced: false)                      // Clear words
        #expect(players.sourceIdentity(for: loud.assetID) == loudPlayer)
        #expect(players.isMuted(loud.assetID) == false, "heard under Clear words")
        #expect(players.isMuted(quiet.assetID) == true, "a muted object stays muted")

        players.apply([], hidden: true, silenced: true)                       // Clear all (or Blackout)
        #expect(players.isMuted(loud.assetID) == true && players.isMuted(quiet.assetID) == true)
        #expect(players.sourceIdentity(for: loud.assetID) == loudPlayer)

        players.apply([loud, quiet], hidden: false, silenced: false)          // un-clear
        #expect(players.sourceIdentity(for: loud.assetID) == loudPlayer && players.sourceIdentity(for: quiet.assetID) == quietPlayer)
        #expect(players.isMuted(loud.assetID) == false && players.isMuted(quiet.assetID) == true)

        players.apply([], hidden: false, silenced: false)                     // Stop: everything closes
        #expect(players.openAssetIDs.isEmpty)
        players.closeAll()
    }

    @Test func blackoutOverClearWordsSilencesThenLiftingBlackoutHearsItAgainWhileStillCleared() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: false, duration: 2)
        players.apply([r], hidden: false, silenced: false)
        players.apply([], hidden: true, silenced: true)                       // Blackout
        #expect(players.isMuted(r.assetID) == true)
        players.apply([], hidden: true, silenced: false)                      // Blackout lifted, still Clear words
        #expect(players.isMuted(r.assetID) == false)
        players.closeAll()
    }
}
