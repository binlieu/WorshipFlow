// FIX-W item 4 (REVIEW-5 L1): a clip that failed to open and opens on a later apply is no longer reported unavailable.
import Testing
import Foundation
import Domain
@testable import MediaEngine

@Suite(.serialized) struct FIXW_ObjectVideoRecoveryTests {
    @Test func aClipThatFailedAndLaterOpensIsNoLongerReportedUnavailable() async throws {
        let dir = try TestMedia.tempDirectory()
        let real = try await redThenBlue(in: dir)
        let later = dir.appendingPathComponent("later.mov")                  // not there yet: the disk is unplugged
        let players = ObjectVideoPlayers()
        let r = ObjectVideoRequest(assetID: UUID(), url: later, loops: true, muted: true, duration: 2)
        players.apply([r])
        #expect(players.unavailableAssetIDs == [r.assetID])
        try FileManager.default.copyItem(at: real, to: later)                // plugged back in
        players.apply([r])
        #expect(players.openAssetIDs == [r.assetID])
        #expect(players.unavailableAssetIDs.isEmpty)
        players.closeAll()
    }
}
