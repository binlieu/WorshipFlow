// FIX-N items 6, 7, 8: the same behaviour as FIXN_EditInteractionTests, written only against API that existed before the fix, so the same file runs
// (and fails) against the tree as it was, and passes after.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXN_EditInteractionRuntimeTests {
    static let themePrimary = NormalizedRect(x: 0.05, y: 0.05, width: 0.5, height: 0.3)
    static let themeSecondary = NormalizedRect(x: 0.05, y: 0.57, width: 0.9, height: 0.38)

    func ready() async throws -> (WorkspaceModel, SlideEditorModel) {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: "mot\n\nhai\n\nba", maxLines: 1))
        await model.openPresentation(p.id)
        let editor = SlideEditorModel(workspace: model)
        editor.lyricThemeFrames = { content in
            var frames: [LyricBox: NormalizedRect] = [:]
            if !content.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.primary] = Self.themePrimary }
            if !(content.secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.secondary] = Self.themeSecondary }
            return frames
        }
        return (model, editor)
    }

    @Test func aPositionTypedAfterAnInterruptedLyricDragIsSaved() async throws {
        let (model, editor) = try await ready()
        editor.selectLyric(.primary)
        editor.beginInteraction()
        editor.moveLyric(.primary, from: Self.themePrimary, dx: 0.1, dy: 0.1)      // no endInteraction: the pointer went up where nobody saw
        editor.setLyricFrame(.primary, x: 0.3, y: 0.4, width: 0.4, height: 0.2)
        #expect(model.slides[0].content.textFrames?.primary == NormalizedRect(x: 0.3, y: 0.4, width: 0.4, height: 0.2))
    }

    @Test func aPositionTypedForAnObjectAfterAnInterruptedDragIsSaved() async throws {
        let (model, editor) = try await ready()
        let id = try #require(editor.add(.rectangle))
        let start = try #require(editor.objects.first { $0.id == id }?.frame)
        editor.beginInteraction()
        editor.move(id, from: start, dx: 0.1, dy: 0.0)
        editor.setFrame(id, x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        #expect(model.slides[0].content.objects.first { $0.id == id }?.frame == NormalizedRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2))
    }

    @Test func applyToAllSkipsSlidesWithNoWordsInThatLanguage() async throws {
        let (model, editor) = try await ready()
        var noSecond = model.slides[1].content
        noSecond.secondary = nil
        model.editSlide(id: model.slides[1].id, content: noSecond)
        editor.selectLyric(.secondary)
        editor.setLyricFrame(.secondary, x: 0.2, y: 0.6, width: 0.6, height: 0.3)
        editor.applyLyricFrameToAllSlides(.secondary)
        #expect(model.slides[0].content.textFrames?.secondary != nil && model.slides[2].content.textFrames?.secondary != nil)
        #expect(model.slides[1].content.textFrames == nil)
    }

    @Test func applyToAllIsOneUndoStepThatRestoresEverySlide() async throws {
        let (model, editor) = try await ready()
        model.selectSlide(1)
        editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        let beforeApply = model.slides.map(\.content.textFrames)
        editor.applyLyricFrameToAllSlides(.primary)
        model.selectSlide(2)
        editor.undo()
        #expect(model.slides.map(\.content.textFrames) == beforeApply)
    }

    @Test func aRunOfNudgesEndsWhenAnotherObjectIsSelectedEvenBackOnTheFirst() async throws {
        let (model, editor) = try await ready()
        let a = try #require(editor.add(.rectangle))
        let b = try #require(editor.add(.rectangle))
        editor.select(a)
        for _ in 0..<5 { editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        editor.select(b)
        for _ in 0..<5 { editor.nudgeSelection(columns: 0, rows: 1, big: false) }
        editor.select(a)
        for _ in 0..<3 { editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        let x = model.slides[0].content.objects.first { $0.id == a }!.frame.x
        editor.undo()
        #expect(abs(model.slides[0].content.objects.first { $0.id == a }!.frame.x - (x - 3.0 / 1920)) < 1e-9, "the last run on a is its own step")
    }

    @Test func reselectingTheSameObjectAfterAnotherSelectionStartsANewRunOfNudges() async throws {
        let (model, editor) = try await ready()
        let a = try #require(editor.add(.rectangle))
        let b = try #require(editor.add(.rectangle))
        editor.select(a)
        for _ in 0..<2 { editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        editor.select(b)                       // nothing nudged on b
        editor.select(a)
        for _ in 0..<2 { editor.nudgeSelection(columns: 1, rows: 0, big: false) }
        let x = model.slides[0].content.objects.first { $0.id == a }!.frame.x
        editor.undo()
        #expect(abs(model.slides[0].content.objects.first { $0.id == a }!.frame.x - (x - 2.0 / 1920)) < 1e-9, "only the second run is undone")
    }
}
