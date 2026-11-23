// FIX-X item 1 (SLIDE, MEDIA; REVIEW-5 L3): Blackout keeps the video objects' players (they go on playing, silenced), so lifting it shows each clip
// where it would have been instead of reopening it from its first frame. Real AVFoundation players on a tiny movie; no wall-clock assertions: what is
// checked is whether the same player is still there, not where it is.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct FIXX_ObjectVideoBlackoutTests {
    private func request(_ url: URL, muted: Bool = true) -> ObjectVideoRequest {
        ObjectVideoRequest(assetID: UUID(), url: url, loops: true, muted: muted, duration: 2)
    }

    @Test func blackoutKeepsTheSamePlayerAndLiftingItDoesNotReopenTheClip() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = request(url)
        players.apply([r])
        let before = try #require(players.sourceIdentity(for: r.assetID))
        players.apply([], blackedOut: true)                                 // the composed scene has no objects under Blackout
        #expect(players.openAssetIDs == [r.assetID])
        #expect(players.sourceIdentity(for: r.assetID) == before)
        players.apply([r], blackedOut: false)                               // lifted: the scene names the clip again
        #expect(players.sourceIdentity(for: r.assetID) == before)           // not reopened, so not restarted
        players.closeAll()
    }

    @Test func aClipThatHasSoundIsSilencedUnderBlackoutAndHeardAgainWhenItLifts() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = request(url, muted: false)
        players.apply([r])
        #expect(players.isMuted(r.assetID) == false)
        players.apply([], blackedOut: true)
        #expect(players.isMuted(r.assetID) == true)
        players.apply([r], blackedOut: false)
        #expect(players.isMuted(r.assetID) == false)
        players.closeAll()
    }

    @Test func aClipThatWasMutedStaysMutedAfterBlackoutLifts() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = request(url, muted: true)
        players.apply([r])
        players.apply([], blackedOut: true)
        players.apply([r], blackedOut: false)
        #expect(players.isMuted(r.assetID) == true)
        players.closeAll()
    }

    @Test func blackoutOpensNothingNew() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let a = request(url), b = request(url)
        players.apply([a])
        players.apply([a, b], blackedOut: true)                             // a publish under Blackout never opens a clip
        #expect(players.openAssetIDs == [a.assetID])
        players.closeAll()
    }

    @Test func withoutBlackoutAnEmptySceneStillClosesEveryPlayer() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let r = request(url)
        players.apply([r])
        players.apply([], blackedOut: false)                                // Stop, Clear, or the slide left Live
        #expect(players.openAssetIDs.isEmpty)
    }

    @Test func theLimitOfFourIsUnchangedAfterBlackoutLifts() async throws {
        let url = try await redThenBlue(in: try TestMedia.tempDirectory())
        let players = ObjectVideoPlayers()
        let all = (0..<6).map { _ in request(url) }
        players.apply(Array(all.prefix(2)))
        players.apply([], blackedOut: true)
        players.apply(all, blackedOut: false)
        #expect(players.openAssetIDs.count == ObjectVideoPlayers.limit)
        #expect(players.skippedAssetIDs.count == 2)
        players.closeAll()
    }
}
