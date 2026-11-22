// FIX-K item 3 (SLIDE): the lyric boxes (first and second language) of the Edit canvas can be selected, dragged, resized, typed into the
// inspector's Position fields and nudged. Doing so gives THAT slide its own text frame, stored with the slide; other slides and Live are untouched.
// Reset returns to the theme's place; "Apply to all slides in this song" is a separate action. Objects (text, shape, image) keep one write and one
// undo step for a drag, a resize and a nudge.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXK_LyricBoxTests {
    static let themePrimary = NormalizedRect(x: 0.05, y: 0.05, width: 0.5, height: 0.3)
    static let themeSecondary = NormalizedRect(x: 0.05, y: 0.57, width: 0.9, height: 0.38)

    struct Rig {
        let model: WorkspaceModel
        let editor: SlideEditorModel
        let store: LibraryStore
        let clock: ManualSaveClock
        let writes: Counter
        let showChanges: Counter
    }
    @MainActor final class Counter { var n = 0 }

    func ready(secondary: Bool = true) async throws -> Rig {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: secondary ? "mot\n\nhai\n\nba" : nil, maxLines: 1))
        await model.openPresentation(p.id)
        let writes = Counter(), changes = Counter()
        model.draftWriter = { [store] slide in writes.n += 1; try await store.updateSlide(slide) }
        model.onShowChange = { _ in changes.n += 1 }
        let editor = SlideEditorModel(workspace: model)
        editor.lyricThemeFrames = { content in
            var frames: [LyricBox: NormalizedRect] = [:]
            if !content.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.primary] = Self.themePrimary }
            if !(content.secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { frames[.secondary] = Self.themeSecondary }
            return frames
        }
        return Rig(model: model, editor: editor, store: store, clock: clock, writes: writes, showChanges: changes)
    }

    func stored(_ r: Rig, _ index: Int) -> SlideTextFrames? { r.model.slides[index].content.textFrames }

    // MARK: What there is to select

    @Test func theBoxesAreTheThemesFramesUntilTheSlideHasItsOwn() async throws {
        let r = try await ready()
        #expect(r.editor.lyricBoxes == [.primary: Self.themePrimary, .secondary: Self.themeSecondary])
        #expect(r.editor.lyricFrame(.primary) == Self.themePrimary && !r.editor.hasOwnFrame(.primary))
        r.editor.selectLyric(.primary)
        #expect(r.editor.selectedLyricBox == .primary && r.editor.selectedObjectID == nil)
    }

    @Test func aLanguageWithNoWordsHasNoBox() async throws {
        let r = try await ready(secondary: false)
        #expect(r.editor.lyricBoxes.keys.sorted { $0.rawValue < $1.rawValue } == [.primary])
        r.editor.selectLyric(.secondary)
        #expect(r.editor.selectedLyricBox == nil)
    }

    @Test func selectingAnObjectOrNothingOrAnotherSlideLeavesNoLyricSelected() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        let id = try #require(r.editor.add(.rectangle))                 // adding selects the new object
        #expect(r.editor.selectedLyricBox == nil && r.editor.selectedObjectID == id)
        r.editor.selectLyric(.secondary)
        #expect(r.editor.selectedObjectID == nil && r.editor.selectedLyricBox == .secondary)
        r.model.selectSlide(2)
        #expect(r.editor.selectedLyricBox == nil)
        r.model.selectSlide(0)
        #expect(r.editor.selectedLyricBox == .secondary)                // remembered with its slide, as an object's selection is
        r.editor.selectLyric(.primary); r.editor.select(nil)
        #expect(r.editor.selectedLyricBox == nil)
    }

    // MARK: Drag and resize

    @Test func draggingALyricBoxWritesNothingUntilReleaseThenOnceAndOneUndoStep() async throws {
        let r = try await ready()
        r.model.selectSlide(1)
        r.editor.selectLyric(.primary)
        await r.clock.advance(by: 6)
        let written = r.writes.n, changes = r.showChanges.n
        let start = try #require(r.editor.lyricFrame(.primary))
        r.editor.beginInteraction()
        for i in 1...60 { r.editor.moveLyric(.primary, from: start, dx: Double(i) * 0.002, dy: Double(i) * 0.001) }
        // Shown where the pointer is, not stored.
        #expect(abs((r.editor.lyricFrame(.primary)?.x ?? 0) - (start.x + 0.12)) < 1e-9)
        #expect(stored(r, 1) == nil && r.showChanges.n == changes)
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written)
        r.editor.endInteraction()
        let end = try #require(stored(r, 1)?.primary)
        #expect(abs(end.x - (start.x + 0.12)) < 1e-9 && abs(end.y - (start.y + 0.06)) < 1e-9 && end.width == start.width)
        #expect(stored(r, 1)?.secondary == nil)
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1)
        // One undo step puts the slide back on the theme's frame.
        r.editor.undo()
        #expect(stored(r, 1) == nil && r.editor.lyricFrame(.primary) == Self.themePrimary && !r.editor.canUndo)
        r.editor.redo()
        #expect(stored(r, 1)?.primary == end)
    }

    @Test func resizingALyricBoxFollowsTheSameRules() async throws {
        let r = try await ready()
        r.editor.selectLyric(.secondary)
        let start = try #require(r.editor.lyricFrame(.secondary))
        r.editor.beginInteraction()
        for i in 1...20 { r.editor.resizeLyric(.secondary, from: start, dWidth: -Double(i) * 0.01, dHeight: -Double(i) * 0.005) }
        #expect(stored(r, 0) == nil)
        r.editor.endInteraction()
        let end = try #require(stored(r, 0)?.secondary)
        #expect(abs(end.width - (start.width - 0.2)) < 1e-9 && abs(end.height - (start.height - 0.1)) < 1e-9 && end.x == start.x && end.y == start.y)
        #expect(stored(r, 0)?.primary == nil)
        r.editor.undo()
        #expect(stored(r, 0) == nil)
    }

    @Test func aLyricFrameIsKeptOnTheSlideAndAtLeastTheMinimumSize() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        r.editor.setLyricFrame(.primary, x: 0.9, y: 0.95, width: 0.5, height: 0.5)
        let f = try #require(stored(r, 0)?.primary)
        #expect(f.x >= 0 && f.y >= 0 && f.x + f.width <= 1 + 1e-9 && f.y + f.height <= 1 + 1e-9)
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0, height: 0)
        let tiny = try #require(stored(r, 0)?.primary)
        #expect(tiny.width >= SlideObject.minimumSize && tiny.height >= SlideObject.minimumSize)
    }

    @Test func typedPositionFieldsAreOneUndoStepPerRun() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        for x in [0.11, 0.12, 0.13] { r.editor.setLyricFrame(.primary, x: x, y: 0.1, width: 0.5, height: 0.3) }
        #expect(stored(r, 0)?.primary?.x == 0.13)
        r.editor.undo()
        #expect(stored(r, 0) == nil)
    }

    // MARK: Only that slide, and never Live

    @Test func otherSlidesAreUntouchedAndEditingNeverChangesLive() async throws {
        let r = try await ready()
        await r.model.goLive(at: 1)
        let live = r.model.show.liveSlide
        r.model.selectSlide(1)                                           // editing the live slide itself
        r.editor.selectLyric(.primary)
        let start = try #require(r.editor.lyricFrame(.primary))
        r.editor.beginInteraction()
        r.editor.moveLyric(.primary, from: start, dx: 0.1, dy: 0.1)
        r.editor.endInteraction()
        #expect(stored(r, 1)?.primary != nil)
        #expect(stored(r, 0) == nil && stored(r, 2) == nil)
        #expect(r.model.show.liveSlide == live && r.model.show.liveSlide?.textFrames == nil)    // only a new trigger shows the new place
    }

    // MARK: Reset and apply to all

    @Test func resetReturnsOneLanguageToTheThemeAndLeavesTheOtherOwn() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.editor.setLyricFrame(.secondary, x: 0.2, y: 0.5, width: 0.5, height: 0.3)
        r.editor.resetLyricFrame(.primary)
        #expect(stored(r, 0)?.primary == nil && stored(r, 0)?.secondary != nil && !r.editor.hasOwnFrame(.primary) && r.editor.hasOwnFrame(.secondary))
        r.editor.resetLyricFrame(.secondary)
        #expect(stored(r, 0) == nil)                                     // both gone: no frames at all
        r.editor.undo()
        #expect(stored(r, 0)?.secondary != nil)
    }

    @Test func applyToAllSlidesGivesEverySlideThatFrameAndKeepsTheirOtherLanguage() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.secondary, x: 0.3, y: 0.7, width: 0.4, height: 0.2)      // slide 1 has its own second-language frame already
        r.model.selectSlide(1)
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        let mine = try #require(stored(r, 1)?.primary)
        r.editor.applyLyricFrameToAllSlides(.primary)
        #expect(r.model.slides.map { $0.content.textFrames?.primary } == [mine, mine, mine])
        #expect(stored(r, 0)?.secondary?.x == 0.3)                        // untouched language kept
        // Undo works on the selected slide and takes only that slide's share back (slide 3 had no frame of its own).
        r.model.selectSlide(2)
        r.editor.undo()
        #expect(stored(r, 2)?.primary == nil)
        #expect(stored(r, 0)?.primary == mine && stored(r, 1)?.primary == mine)
    }

    @Test func applyToAllWithNoOwnFrameResetsEverySlideToTheTheme() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        r.model.selectSlide(2)
        r.editor.applyLyricFrameToAllSlides(.primary)                      // slide 3 has the theme's frame: that is what all get
        #expect(r.model.slides.allSatisfy { $0.content.textFrames == nil })
    }

    // MARK: The keyboard

    @Test func nudgingALyricBoxMovesItOnePointOrTenWithShiftAndIsOneStepPerRun() async throws {
        let r = try await ready()
        r.editor.selectLyric(.primary)
        let start = try #require(r.editor.lyricFrame(.primary))
        #expect(r.editor.nudgeSelection(columns: 1, rows: 0, big: false))
        let one = try #require(stored(r, 0)?.primary)
        #expect(abs(one.x - (start.x + 1.0 / 1920)) < 1e-12 && one.y == start.y)
        #expect(r.editor.nudgeSelection(columns: 0, rows: -1, big: true))
        let two = try #require(stored(r, 0)?.primary)
        #expect(abs(two.y - (start.y - 10.0 / 1080)) < 1e-12 && two.x == one.x)
        r.editor.undo()
        #expect(stored(r, 0) == nil)                                        // the run of nudges was one step
    }

    @Test func nudgingDoesNothingAndSaysSoWithNothingSelected() async throws {
        let r = try await ready()
        #expect(r.editor.nudgeSelection(columns: 1, rows: 0, big: false) == false)
        #expect(stored(r, 0) == nil && !r.editor.canUndo)
    }

    @Test func aNudgeAgainstTheEdgeStaysOnTheSlide() async throws {
        let r = try await ready()
        r.editor.setLyricFrame(.primary, x: 0, y: 0, width: 0.5, height: 0.5)
        r.editor.selectLyric(.primary)
        _ = r.editor.nudgeSelection(columns: -1, rows: -1, big: true)
        #expect(stored(r, 0)?.primary?.x == 0 && stored(r, 0)?.primary?.y == 0)
    }

    // MARK: Objects: one model write and one undo step for a drag, a resize and a nudge, whatever the kind

    nonisolated static let kinds: [(String, NewSlideObject)] = [("text box", .textBox), ("rectangle", .rectangle), ("ellipse", .ellipse),
                                                    ("rounded rectangle", .roundedRectangle), ("image", .image(path: "/nowhere/picture.png"))]

    @Test(arguments: ["text box", "rectangle", "ellipse", "rounded rectangle", "image"]) func eachObjectKindDragsResizesAndNudgesWithOneWriteAndOneUndoStep(kind: String) async throws {
        let template = try #require(Self.kinds.first { $0.0 == kind }?.1)
        let r = try await ready()
        let id = try #require(r.editor.add(template))
        await r.clock.advance(by: 6)
        let start = try #require(r.editor.selectedObject).frame

        // Drag.
        var written = r.writes.n
        r.editor.beginInteraction()
        for i in 1...30 { r.editor.move(id, from: start, dx: Double(i) * 0.002, dy: Double(i) * 0.001) }
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1, "\(kind) drag")
        let dragged = try #require(r.editor.selectedObject).frame
        #expect(dragged != start)
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start, "\(kind) drag undo")

        // Resize.
        written = r.writes.n
        r.editor.beginInteraction()
        for i in 1...30 { r.editor.resize(id, from: start, dWidth: Double(i) * 0.001, dHeight: Double(i) * 0.001) }
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1, "\(kind) resize")
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start, "\(kind) resize undo")

        // Nudge: one write and one undo step.
        written = r.writes.n
        #expect(r.editor.nudgeSelection(columns: 1, rows: 1, big: false))
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1, "\(kind) nudge")
        let nudged = try #require(r.editor.selectedObject).frame
        #expect(abs(nudged.x - (start.x + 1.0 / 1920)) < 1e-12 && abs(nudged.y - (start.y + 1.0 / 1080)) < 1e-12)
        #expect(r.editor.nudgeSelection(columns: 1, rows: 0, big: true))
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start, "\(kind) nudge undo (a run is one step)")
    }

    // MARK: The eight handles

    @Test func eachOfTheEightHandlesMovesItsOwnEdgesAndKeepsTheOppositeOnesStill() {
        let f = NormalizedRect(x: 0.3, y: 0.3, width: 0.4, height: 0.3)
        let handles: [(Double, Double)] = [(0, 0), (0.5, 0), (1, 0), (0, 0.5), (1, 0.5), (0, 1), (0.5, 1), (1, 1)]
        for (px, py) in handles {
            let r = SlideEditing.resizedFrame(from: f, handleX: px, handleY: py, dx: 0.05, dy: 0.04)
            let leftMoves = px == 0, rightMoves = px == 1, topMoves = py == 0, bottomMoves = py == 1
            #expect(abs(r.x - (leftMoves ? f.x + 0.05 : f.x)) < 1e-12, "handle \(px),\(py) left")
            #expect(abs((r.x + r.width) - (rightMoves ? f.x + f.width + 0.05 : f.x + f.width)) < 1e-12, "handle \(px),\(py) right")
            #expect(abs(r.y - (topMoves ? f.y + 0.04 : f.y)) < 1e-12, "handle \(px),\(py) top")
            #expect(abs((r.y + r.height) - (bottomMoves ? f.y + f.height + 0.04 : f.y + f.height)) < 1e-12, "handle \(px),\(py) bottom")
        }
        // Dragged past the opposite edge it stops at the minimum size, with that edge still.
        let past = SlideEditing.resizedFrame(from: f, handleX: 0, handleY: 0, dx: 5, dy: 5)
        #expect(abs(past.width - SlideObject.minimumSize) < 1e-12 && abs(past.height - SlideObject.minimumSize) < 1e-12)
        #expect(abs((past.x + past.width) - (f.x + f.width)) < 1e-12 && abs((past.y + past.height) - (f.y + f.height)) < 1e-12)
    }

    @Test func aHandleDragOfAnObjectOrALyricBoxIsOneWriteAndOneUndoStep() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.textBox))
        await r.clock.advance(by: 6)
        let start = try #require(r.editor.selectedObject).frame
        var written = r.writes.n
        r.editor.beginInteraction()
        for i in 1...20 { r.editor.dragFrame(id, to: SlideEditing.resizedFrame(from: start, handleX: 0, handleY: 0, dx: Double(i) * 0.002, dy: Double(i) * 0.002)) }
        #expect(r.model.slides[0].content.objects.first?.frame == start)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1)
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start)

        r.editor.selectLyric(.secondary)
        let lyric = try #require(r.editor.lyricFrame(.secondary))
        written = r.writes.n
        r.editor.beginInteraction()
        for i in 1...20 { r.editor.dragLyricFrame(.secondary, to: SlideEditing.resizedFrame(from: lyric, handleX: 1, handleY: 1, dx: -Double(i) * 0.002, dy: -Double(i) * 0.002)) }
        #expect(stored(r, 0) == nil)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1)
        #expect(abs((stored(r, 0)?.secondary?.width ?? 0) - (lyric.width - 0.04)) < 1e-9)
        r.editor.undo()
        #expect(stored(r, 0) == nil)
    }
}
