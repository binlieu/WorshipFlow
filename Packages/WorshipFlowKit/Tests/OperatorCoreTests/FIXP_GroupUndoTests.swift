// FIX-P items 1 and 2 (review of FIX-N, M1 and M2): "Apply to all slides" is one undo step from every slide that took part, the source included, and
// an undo that cannot restore a slide (it was edited after the apply) restores the others and says so in one plain message.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXP_GroupUndoTests {
    static let themePrimary = NormalizedRect(x: 0.05, y: 0.05, width: 0.5, height: 0.3)
    static let themeSecondary = NormalizedRect(x: 0.05, y: 0.57, width: 0.9, height: 0.38)
    struct Rig { let model: WorkspaceModel; let editor: SlideEditorModel }

    func ready() async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: "mot\n\nhai\n\nba", maxLines: 1))
        await model.openPresentation(p.id)
        let editor = SlideEditorModel(workspace: model)
        editor.lyricThemeFrames = { content in
            var frames: [LyricBox: NormalizedRect] = [:]
            if !content.primary.isEmpty { frames[.primary] = Self.themePrimary }
            if !(content.secondary ?? "").isEmpty { frames[.secondary] = Self.themeSecondary }
            return frames
        }
        return Rig(model: model, editor: editor)
    }
    func primaries(_ r: Rig) -> [NormalizedRect?] { r.model.slides.map { $0.content.textFrames?.primary } }
    func allFrames(_ r: Rig) -> [SlideTextFrames?] { r.model.slides.map(\.content.textFrames) }

    // MARK: M1

    @Test func undoOnTheSlideTheApplyCameFromUndoesTheApplyOnEverySlide() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)      // an earlier step on the source slide itself
        let beforeApply = allFrames(r)
        r.editor.applyLyricFrameToAllSlides(.primary)
        let mine = try #require(primaries(r)[0])
        #expect(primaries(r) == [mine, mine, mine])
        r.editor.undo()                                    // still on the slide the apply came from
        #expect(allFrames(r) == beforeApply, "the first Undo from the source slide puts every slide back")
        r.editor.redo()
        #expect(primaries(r) == [mine, mine, mine], "and the first Redo applies it again")
    }

    @Test func undoFromTheSourceWorksWhenTheSourceHasNoEarlierStep() async throws {
        let r = try await ready()
        // slide 0 has no frame of its own: applying "the theme position" is a no-op for it, but still a step the others share
        r.model.selectSlide(1)
        r.editor.setLyricFrame(.primary, x: 0.2, y: 0.2, width: 0.4, height: 0.2)
        r.model.selectSlide(0)
        r.editor.setLyricFrame(.primary, x: 0.3, y: 0.3, width: 0.4, height: 0.2)
        let beforeApply = allFrames(r)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.editor.undo()
        #expect(allFrames(r) == beforeApply)
        #expect(r.model.slides.count == 3)
    }

    @Test func undoFromATargetStillRestoresTheSourceToo() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        let beforeApply = allFrames(r)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.model.selectSlide(2)
        r.editor.undo()
        #expect(allFrames(r) == beforeApply)
        #expect(r.editor.lastMessage == nil, "nothing was skipped, so nothing is said")
    }

    @Test func anApplyThatChangesNoSlideLeavesNoStepOnTheSource() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        let marker = allFrames(r)
        r.editor.applyLyricFrameToAllSlides(.primary)        // every slide already holds it: nothing changes
        r.editor.undo()                                      // this undoes the FIRST apply, not an empty second one
        #expect(allFrames(r) != marker)
    }

    // MARK: M2

    @Test func aSlideEditedAfterTheApplyIsKeptAndTheUndoSaysSo() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        let beforeApply = allFrames(r)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.model.selectSlide(2)
        r.editor.setLyricFrame(.primary, x: 0.6, y: 0.6, width: 0.3, height: 0.2)      // slide 3 is edited after the apply
        let edited = primaries(r)[2]
        r.model.selectSlide(1)
        r.editor.undo()
        #expect(primaries(r)[2] == edited, "a later edit is never overwritten")
        #expect(allFrames(r)[0] == beforeApply[0] && allFrames(r)[1] == beforeApply[1], "the slides that can go back do")
        #expect(r.editor.lastMessage == "Position restored on 2 of 3 slides; 1 was edited since.")
    }

    @Test func severalSlidesEditedSinceAreCountedInTheSameMessage() async throws {
        let r = try await ready()
        r.editor.applyLyricFrameToAllSlides(.primary)      // nothing differs from the theme: no group at all
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        for i in [1, 2] {
            r.model.selectSlide(i)
            r.editor.setLyricFrame(.primary, x: 0.5 + Double(i) * 0.05, y: 0.5, width: 0.3, height: 0.2)
        }
        r.model.selectSlide(0)
        r.editor.undo()
        #expect(r.editor.lastMessage == "Position restored on 1 of 3 slides; 2 were edited since.")
    }

    @Test func aRedoThatCannotReachASlideSaysSoToo() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.editor.undo()
        r.model.selectSlide(2)
        r.editor.setLyricFrame(.primary, x: 0.6, y: 0.6, width: 0.3, height: 0.2)      // a new edit on slide 3 drops its redo
        let edited = primaries(r)[2]
        r.model.selectSlide(1)
        r.editor.redo()
        #expect(primaries(r)[2] == edited)
        #expect(r.editor.lastMessage == "Position re-applied on 2 of 3 slides; 1 was edited since.")
    }

    @Test func aSlideDeletedSinceIsNotCountedAsSkipped() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        await r.model.deleteSlide(at: 2)
        r.model.selectSlide(1)
        r.editor.undo()
        #expect(r.model.slides.count == 2)
        #expect(r.editor.lastMessage == nil)
    }

    @Test func undoAndRedoNeverTouchLiveEvenWhenPartial() async throws {
        let r = try await ready()
        await r.model.goLive(at: 1)
        let live = r.model.show.liveDeck, index = r.model.show.liveIndex
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.model.selectSlide(2)
        r.editor.setLyricFrame(.primary, x: 0.6, y: 0.6, width: 0.3, height: 0.2)
        r.model.selectSlide(1)
        r.editor.undo(); r.editor.redo()
        #expect(r.model.show.liveDeck == live && r.model.show.liveIndex == index)
    }

    @Test func aCleanUndoOrRedoClearsAnEarlierEditedSinceMessage() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        r.model.selectSlide(2)
        r.editor.setLyricFrame(.primary, x: 0.6, y: 0.6, width: 0.3, height: 0.2)
        r.model.selectSlide(1)
        r.editor.undo()
        #expect(r.editor.lastMessage?.hasPrefix("Position restored on 2 of 3") == true)
        r.editor.redo()                                       // slide 1 and the source go forward again: nothing was skipped this time
        #expect(r.editor.lastMessage == nil, "the old message no longer describes the screen")
    }
}
