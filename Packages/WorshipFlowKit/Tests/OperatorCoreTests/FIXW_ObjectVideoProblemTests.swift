// FIX-W item 4 (SLIDE, MEDIA; REVIEW-5 M4): a video object that cannot be opened, or is past the player limit, is reported where the operator
// already reads media problems (`MediaModel.lastError`), naming the clip and the reason, and the message goes when the problem does.
import Testing
import Foundation
import Domain
@testable import OperatorCore

@MainActor
@Suite struct FIXW_ObjectVideoProblemTests {
    @Test func aClipThatCannotBeOpenedIsNamedWithTheReason() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("Testimony.mov")
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)
        let text = try #require(rig.model.lastError)
        #expect(text.contains("Testimony") && text.contains("could not be opened"))
    }

    @Test func aClipBeyondThePlayerLimitIsNamedWithTheLimit() async throws {
        let rig = try MediaRig()
        let fifth = await rig.add("Fifth.mov")
        rig.model.reportObjectVideos(unavailable: [], skipped: [fifth.id], limit: 4)
        let text = try #require(rig.model.lastError)
        #expect(text.contains("Fifth") && text.contains("4") && text.contains("at once"))
    }

    @Test func theMessageIsClearedWhenTheClipOpensAgainButAnotherMessageIsNotTouched() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("Testimony.mov")
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)
        rig.model.reportObjectVideos(unavailable: [], skipped: [], limit: 4)
        #expect(rig.model.lastError == nil)
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)
        rig.model.report("Something else went wrong.")
        rig.model.reportObjectVideos(unavailable: [], skipped: [], limit: 4)
        #expect(rig.model.lastError == "Something else went wrong.")
    }

    @Test func aDismissedMessageIsNotRaisedAgainByTheSameProblemOnTheNextPublish() async throws {
        let rig = try MediaRig()
        let clip = await rig.add("Testimony.mov")
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)
        rig.model.dismissError()
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)
        #expect(rig.model.lastError == nil)
        rig.model.reportObjectVideos(unavailable: [], skipped: [], limit: 4)
        rig.model.reportObjectVideos(unavailable: [clip.id], skipped: [], limit: 4)      // it failed again later: told again
        #expect(rig.model.lastError != nil)
    }

    @Test func nothingIsSaidWhenNothingIsWrong() async throws {
        let rig = try MediaRig()
        rig.model.reportObjectVideos(unavailable: [], skipped: [], limit: 4)
        #expect(rig.model.lastError == nil)
    }
}
