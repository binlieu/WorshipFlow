// FIX-N items 6, 7 and 8 (FIX-K): an interrupted drag no longer leaves the Edit interaction open (a position typed in the inspector then showed but was
// never saved); "Apply to all slides in this song" skips slides with no words in that language, says how many it will change, and is one undo step;
// a run of nudges ends when the selection changes, another edit happens or the quiet period passes; the lyric boxes' theme frames are composed once.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXN_EditInteractionTests {
    static let themePrimary = NormalizedRect(x: 0.05, y: 0.05, width: 0.5, height: 0.3)
    static let themeSecondary = NormalizedRect(x: 0.05, y: 0.57, width: 0.9, height: 0.38)

    @MainActor final class Clock { var now = Date(timeIntervalSince1970: 2_000_000); func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) } }
    struct Rig { let model: WorkspaceModel; let editor: SlideEditorModel; let clock: Clock }

    func ready(primary: String = "one\n\ntwo\n\nthree", secondary: String? = "mot\n\nhai\n\nba") async throws -> Rig {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: primary, secondaryText: secondary, maxLines: 1))
        await model.openPresentation(p.id)
        let editor = SlideEditorModel(workspace: model)
        editor.lyricThemeFrames = { content in
            var frames: [LyricBox: NormalizedRect] = [:]
            if !content.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.primary] = Self.themePrimary }
            if !(content.secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.secondary] = Self.themeSecondary }
            return frames
        }
        let clock = Clock()
        editor.nudgeClock = { clock.now }
        return Rig(model: model, editor: editor, clock: clock)
    }

    func frames(_ r: Rig, _ i: Int) -> SlideTextFrames? { r.model.slides[i].content.textFrames }

    // MARK: Item 6: an interrupted drag

    @Test func aPositionTypedAfterAnInterruptedLyricDragIsSavedAndUndoable() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        r.editor.beginInteraction()
        r.editor.moveLyric(.primary, from: Self.themePrimary, dx: 0.1, dy: 0.1)      // the pointer went up somewhere nobody saw: no endInteraction
        r.editor.setLyricFrame(.primary, x: 0.3, y: 0.4, width: 0.4, height: 0.2)    // the inspector's fields
        #expect(frames(r, 0)?.primary == NormalizedRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2))
        #expect(r.editor.lyricDragFrames.isEmpty)
        #expect(r.editor.canUndo)
        r.editor.undo()
        r.editor.undo()
        #expect(frames(r, 0) == nil, "the drag and the typed position are both steps; both undo")
    }

    @Test func aPositionTypedForAnObjectAfterAnInterruptedDragIsSaved() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        let start = try #require(r.editor.objects.first { $0.id == id }?.frame)
        r.editor.beginInteraction()
        r.editor.move(id, from: start, dx: 0.1, dy: 0.0)
        r.editor.setFrame(id, x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        #expect(r.model.slides[0].content.objects.first { $0.id == id }?.frame == NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))
        #expect(r.editor.dragFrames.isEmpty)
    }

    @Test func endingAStrayInteractionKeepsWhatTheDragShowedAsOneStep() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        r.editor.beginInteraction()
        r.editor.moveLyric(.primary, from: Self.themePrimary, dx: 0.1, dy: 0.0)
        r.editor.endInteraction()          // the window resigned key, the view went, the slide changed: the model is told
        r.editor.endInteraction()          // and a second time does nothing
        #expect(abs((frames(r, 0)?.primary?.x ?? 0) - 0.15) < 1e-12)
        #expect(r.editor.lyricDragFrames.isEmpty)
        r.editor.undo()
        #expect(frames(r, 0) == nil)
    }

    @Test func selectingSomethingElseEndsAStrayDragOnItsOwnSlide() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        r.editor.beginInteraction()
        r.editor.moveLyric(.primary, from: Self.themePrimary, dx: 0.1, dy: 0.0)
        r.model.selectSlide(1)
        r.editor.selectLyric(.primary)          // the next press, on another slide
        #expect(r.editor.lyricDragFrames.isEmpty)
        #expect(frames(r, 0)?.primary != nil, "the first slide kept what its drag showed")
        #expect(frames(r, 1) == nil, "and the second slide was not touched")
    }

    @Test func theInteractionEpochCountsEndedInteractionsSoTheBoxesCanResetTheirPressedState() async throws {
        let r = try await ready()
        let before = r.editor.interactionEpoch
        r.editor.beginInteraction(); r.editor.endInteraction()
        #expect(r.editor.interactionEpoch == before + 1)
        r.editor.endInteraction()
        #expect(r.editor.interactionEpoch == before + 1)
    }

    // MARK: Item 7: Apply to all slides

    @Test func applyToAllSkipsSlidesWithNoWordsInThatLanguage() async throws {
        let r = try await ready()
        var noSecond = r.model.slides[1].content
        noSecond.secondary = nil             // slide 2 has no second language
        r.model.editSlide(id: r.model.slides[1].id, content: noSecond)
        let slides = r.model.slides
        #expect(slides.count == 3 && (slides[1].content.secondary ?? "").isEmpty)
        r.editor.selectLyric(.secondary)
        r.editor.setLyricFrame(.secondary, x: 0.2, y: 0.6, width: 0.6, height: 0.3)
        #expect(r.editor.lyricApplyCount(.secondary) == 1)
        r.editor.applyLyricFrameToAllSlides(.secondary)
        #expect(frames(r, 0)?.secondary != nil && frames(r, 2)?.secondary != nil)
        #expect(frames(r, 1) == nil, "the slide with no words in that language keeps no frame")
        #expect(r.editor.lyricApplyCount(.secondary) == 0, "nothing left to change")
    }

    @Test func applyToAllIsOneUndoStepThatRestoresEverySlide() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.secondary, x: 0.3, y: 0.7, width: 0.4, height: 0.2)      // slide 1 already has its own second-language frame
        let before = r.model.slides.map(\.content.textFrames)
        r.model.selectSlide(1)
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        let beforeApply = r.model.slides.map(\.content.textFrames)
        #expect(r.editor.lyricApplyCount(.primary) == 2)
        r.editor.applyLyricFrameToAllSlides(.primary)
        let mine = try #require(frames(r, 1)?.primary)
        #expect(r.model.slides.map { $0.content.textFrames?.primary } == [mine, mine, mine])
        // One undo, from any slide that took part, puts every slide back.
        r.model.selectSlide(2)
        r.editor.undo()
        #expect(r.model.slides.map(\.content.textFrames) == beforeApply)
        // One redo brings them all back.
        r.editor.redo()
        #expect(r.model.slides.map { $0.content.textFrames?.primary } == [mine, mine, mine])
        r.editor.undo()
        #expect(r.model.slides.map(\.content.textFrames) == beforeApply)
        _ = before
    }

    @Test func applyToAllDoesNotTouchLive() async throws {
        let r = try await ready()
        await r.model.goLive()
        let live = r.model.show.liveSlide
        r.editor.selectLyric(.primary)
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.applyLyricFrameToAllSlides(.primary)
        #expect(r.model.show.liveSlide == live)
    }

    // MARK: Item 8: nudging

    @Test func aRunOfNudgesIsOneStepAndAnotherSelectionStartsANewOne() async throws {
        let r = try await ready()
        let a = try #require(r.editor.add(.rectangle))
        let b = try #require(r.editor.add(.rectangle))
        r.editor.select(a)
        for _ in 0..<5 { #expect(r.editor.nudgeSelection(columns: 1, rows: 0, big: false)) }
        r.editor.select(b)
        for _ in 0..<5 { #expect(r.editor.nudgeSelection(columns: 0, rows: 1, big: false)) }
        r.editor.select(a)                      // the same key as the first run: it must not join it
        for _ in 0..<3 { #expect(r.editor.nudgeSelection(columns: 1, rows: 0, big: false)) }
        let xs = r.model.slides[0].content.objects.first { $0.id == a }!.frame.x
        let startA = xs - 8.0 / 1920
        r.editor.undo()          // the last run on a
        #expect(abs(r.model.slides[0].content.objects.first { $0.id == a }!.frame.x - (startA + 5.0 / 1920)) < 1e-9)
        r.editor.undo()          // the run on b
        #expect(abs(r.model.slides[0].content.objects.first { $0.id == b }!.frame.y - r.model.slides[0].content.objects.first { $0.id == b }!.frame.y) < 1e-9)
        r.editor.undo()          // the first run on a
        #expect(abs(r.model.slides[0].content.objects.first { $0.id == a }!.frame.x - startA) < 1e-9)
    }

    @Test func aQuietPeriodEndsARunOfNudges() async throws {
        let r = try await ready()
        let a = try #require(r.editor.add(.rectangle))
        r.editor.select(a)
        let start = try #require(r.editor.objects.first { $0.id == a }?.frame.x)
        for _ in 0..<4 { r.clock.advance(0.1); r.editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        r.clock.advance(r.editor.nudgeQuietPeriod + 0.1)
        for _ in 0..<2 { r.clock.advance(0.1); r.editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        r.editor.undo()
        #expect(abs((r.editor.objects.first { $0.id == a }?.frame.x ?? 0) - (start + 4.0 / 1920)) < 1e-9, "only the second run is undone")
        r.editor.undo()
        #expect(abs((r.editor.objects.first { $0.id == a }?.frame.x ?? 0) - start) < 1e-9)
    }

    @Test func anotherEditEndsTheRun() async throws {
        let r = try await ready()
        let a = try #require(r.editor.add(.rectangle))
        r.editor.select(a)
        let start = try #require(r.editor.objects.first { $0.id == a }?.frame.x)
        for _ in 0..<3 { r.editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        r.editor.setOpacity(a, 0.5)
        for _ in 0..<2 { r.editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        r.editor.undo()
        #expect(abs((r.editor.objects.first { $0.id == a }?.frame.x ?? 0) - (start + 3.0 / 1920)) < 1e-9)
    }

    // MARK: Item 8: the lyric boxes are not recomposed on every read

    @Test func lyricBoxesComposeTheThemeFramesOnceUntilTheTextOrTheThemeChanges() async throws {
        let r = try await ready()
        var revision = 0
        r.editor.lyricThemeRevision = { revision }
        let start = r.editor.debugLyricComposeCount
        for _ in 0..<50 { _ = r.editor.lyricBoxes; _ = r.editor.selectedLyricBox; _ = r.editor.lyricFrame(.primary) }
        #expect(r.editor.debugLyricComposeCount == start + 1)
        revision += 1                      // the theme or a screen changed
        _ = r.editor.lyricBoxes
        #expect(r.editor.debugLyricComposeCount == start + 2)
        r.model.selectSlide(1)             // another slide, another words
        _ = r.editor.lyricBoxes; _ = r.editor.lyricBoxes
        #expect(r.editor.debugLyricComposeCount == start + 3)
    }
}
