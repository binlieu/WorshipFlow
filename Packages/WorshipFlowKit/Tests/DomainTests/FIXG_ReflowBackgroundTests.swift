// FIX-G item 2 (MEDIA-010): a re-flow carries a slide's own background over by the same match as notes and objects, and the
// loss list names a background that nothing takes.
import Testing
import Foundation
@testable import Domain

@Suite struct FIXG_ReflowBackgroundTests {
    let video = MediaSelection(assetID: UUID(), kind: .video, duration: 8)
    let picture = MediaSelection(assetID: UUID(), kind: .image, duration: nil)

    func old(_ section: String?, _ words: String, background: MediaSelection? = nil) -> ExistingSlide {
        ExistingSlide(sectionName: section, content: SlideContent(primary: words, background: background), notes: "")
    }
    func new(_ section: String?, _ words: String) -> ReflowResult {
        ReflowResult(sectionName: section, content: SlideContent(primary: words))
    }

    @Test func aMatchedSlideTakesItsBackgroundAlong() {
        let carry = Reflow.carryOver(from: [old("Verse 1", "a", background: video), old("Chorus", "c", background: picture)],
                                     to: [new("Verse 1", "A!"), new("Chorus", "c"), new("Chorus", "new")])
        #expect(carry.backgrounds == [video, picture, nil])
        #expect(carry.losses.isEmpty)
    }

    @Test func aSlideWhoseWordsVanishedIsListedAsALossForItsBackgroundAlone() {
        let carry = Reflow.carryOver(from: [old("Verse 1", "gone", background: video), old("Verse 1", "plain")], to: [new("Verse 1", "other")])
        #expect(carry.backgrounds == [nil])
        #expect(carry.losses.count == 1)
        #expect(carry.losses.first?.hasBackground == true && carry.losses.first?.primary == "gone")
        #expect(carry.losses.first?.objectCount == 0 && carry.losses.first?.notes == "")
    }

    @Test func aLossWithoutABackgroundSaysSo() {
        let carry = Reflow.carryOver(from: [old(nil, "gone")], to: [])
        #expect(carry.losses.isEmpty)
    }
}
