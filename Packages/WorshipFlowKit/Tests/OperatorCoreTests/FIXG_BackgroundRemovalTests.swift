// FIX-G item 2 (MEDIA-010): removing a bin item that slides use as their own background. The operator is told which slides are
// affected before the removal; the slides keep their choice and show the missing-media state (they never lose it silently).
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXG_BackgroundRemovalTests {
    private func rig() async throws -> (MediaRig, LibraryStore, MediaAsset, MediaAsset, [UUID]) {
        let rig = try MediaRig()
        let store = rig.store
        let used = await rig.add("loop.mov")
        let other = await rig.add("other.mov")
        let library = try await store.createLibrary(name: "Songs")
        var ids: [UUID] = []
        for (title, count) in [("Amazing Grace", 3), ("Sermon", 2)] {
            let p = try await store.createPresentation(in: library.id, title: title, kind: .song)
            ids.append(p.id)
            for i in 0..<count {
                let background: MediaSelection? = (title == "Amazing Grace" && i != 1) || (title == "Sermon" && i == 1) ? MediaSelection(asset: used)
                    : (i == 1 ? MediaSelection(asset: other) : nil)
                _ = try await store.appendSlide(to: p.id, content: SlideContent(primary: "\(title) line \(i + 1)", background: background))
            }
        }
        return (rig, store, used, other, ids)
    }

    @Test func theOperatorIsToldWhichSlidesUseTheItemBeforeItIsRemoved() async throws {
        let (rig, _, used, other, _) = try await rig()
        let impact = await rig.model.removalImpact(used.id)
        #expect(impact.uses.map(\.presentationTitle) == ["Amazing Grace", "Amazing Grace", "Sermon"])
        #expect(impact.uses.map(\.slideNumber) == [1, 3, 2])
        #expect(impact.uses.first?.words == "Amazing Grace line 1")
        let message = try #require(impact.message)
        #expect(message.contains("loop") && message.contains("Amazing Grace") && message.contains("slide 3") && message.contains("Sermon"))
        #expect(message.contains("own background"))
        #expect(await rig.model.removalImpact(other.id).uses.count == 1)
    }

    @Test func anItemNoSlideUsesNeedsNoWarning() async throws {
        let rig = try MediaRig()
        let loose = await rig.add("loose.mov")
        let impact = await rig.model.removalImpact(loose.id)
        #expect(impact.uses.isEmpty && impact.message == nil)
    }

    @Test func aLongListIsShortenedWithACount() async throws {
        let rig = try MediaRig()
        let used = await rig.add("loop.mov")
        let library = try await rig.store.createLibrary(name: "Songs")
        let p = try await rig.store.createPresentation(in: library.id, title: "Long", kind: .song)
        for i in 0..<15 { _ = try await rig.store.appendSlide(to: p.id, content: SlideContent(primary: "line \(i)", background: MediaSelection(asset: used))) }
        let message = try #require(await rig.model.removalImpact(used.id).message)
        #expect(message.contains("15 slides") && message.contains("and 7 more"))
    }

    @Test func afterTheRemovalTheSlidesKeepTheirChoiceAndShowTheMissingState() async throws {
        let (rig, store, used, other, ids) = try await rig()
        await rig.model.remove(used.id)
        #expect(rig.model.assets.map(\.id) == [other.id])
        let slides = try await store.slides(of: ids[0])
        #expect(slides.map(\.content.background?.assetID) == [used.id, other.id, used.id], "the choice is kept, not silently cleared")
        #expect(slides.map { SlideBackgroundDrop.isMissing($0.content, available: Set(rig.model.assets.map(\.id))) } == [true, false, true])
        // The slide without a background of its own is not "missing" anything.
        #expect(!SlideBackgroundDrop.isMissing(SlideContent(primary: "x"), available: []))
    }
}
