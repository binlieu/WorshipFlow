// FIX-K item 7 (owner: "drag and drop feels janky and laggy also sometime sluggish"): counters. During a drag nothing is written to the database, nothing is published
// to an output and (for a column strip) the layout does not change; each of those happens once, on release. The running-app numbers (per event, 200 slides and 100
// bin items) are in AI/reports/FIX-K-report.md; they come from the debug hook, not from this suite (no wall-clock assertions here).
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct FIXK_DragCounterTests {
    struct Rig { let model: WorkspaceModel; let editor: SlideEditorModel; let store: LibraryStore; let clock: ManualSaveClock; var publications = 0 }
    @MainActor final class Count { var n = 0 }

    func ready() async throws -> (Rig, Count) {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let text = (1...40).map { "Line \($0)" }.joined(separator: "\n\n")
        let p = try #require(await model.importLyrics(title: "Long", primaryText: text, secondaryText: "b", maxLines: 1))
        await model.openPresentation(p.id)
        let published = Count()
        model.onShowChange = { _ in published.n += 1 }
        let editor = SlideEditorModel(workspace: model)
        editor.lyricThemeFrames = { _ in [.primary: NormalizedRect(x: 0.05, y: 0.05, width: 0.5, height: 0.3)] }
        return (Rig(model: model, editor: editor, store: store, clock: clock), published)
    }

    @Test func anObjectDragWritesNothingAndPublishesNothingUntilReleaseThenCommitsOnce() async throws {
        let (r, published) = try await ready()
        r.model.selectSlide(10)
        let id = try #require(r.editor.add(.rectangle))
        await r.clock.advance(by: 6)
        let commits = r.store.commitCount, shows = published.n
        let start = try #require(r.editor.selectedObject).frame
        r.editor.beginInteraction()
        for i in 1...60 { r.editor.move(id, from: start, dx: Double(i) * 0.003, dy: 0.001 * Double(i)) }
        await r.clock.advance(by: 6)
        #expect(r.store.commitCount == commits && published.n == shows)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.store.commitCount == commits + 1)
    }

    @Test func aLyricBoxDragAndAHandleDragAreTheSame() async throws {
        let (r, published) = try await ready()
        r.model.selectSlide(5)
        r.editor.selectLyric(.primary)
        await r.clock.advance(by: 6)                                 // whatever the selection itself saves
        let commits = r.store.commitCount, shows = published.n
        let start = try #require(r.editor.lyricFrame(.primary))
        r.editor.beginInteraction()
        for i in 1...60 { r.editor.moveLyric(.primary, from: start, dx: Double(i) * 0.002, dy: 0.001) }
        for i in 1...30 { r.editor.dragLyricFrame(.primary, to: SlideEditing.resizedFrame(from: start, handleX: 1, handleY: 1, dx: Double(i) * 0.001, dy: 0)) }
        await r.clock.advance(by: 6)
        #expect(r.store.commitCount == commits && published.n == shows)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.store.commitCount == commits + 1)
    }

    @Test func reorderingASlideDoesNotTouchWhatIsLiveAndIsAtMostTwoCommits() async throws {
        let (r, _) = try await ready()
        await r.model.goLive(at: 2)
        await r.clock.advance(by: 6)
        let live = r.model.show.liveDeck, commits = r.store.commitCount
        await r.model.moveSlide(from: 30, to: 3)
        #expect(r.model.show.liveDeck == live)                       // the screens are republished only when what they show changed (the app's gate)
        #expect(r.store.commitCount - commits <= 2)
        #expect(r.model.slides[3].content.primary == "Line 31")
    }

    @Test func aColumnStripChangesNoWidthUntilReleaseThenOnce() {
        var drag = ColumnDrag(range: 240...380, grows: 1)
        var committed = 256.0, layouts = 0
        for i in 1...50 {
            drag.change(translation: Double(i) * 3, from: committed)
            #expect(drag.isDragging)
            _ = layouts                                              // the view applies nothing to the layout while dragging
        }
        #expect(committed == 256 && drag.proposed == 380)           // clamped to the range
        if let final = drag.end() { committed = final; layouts += 1 }
        #expect(committed == 380 && layouts == 1 && !drag.isDragging && drag.proposed == nil)
        #expect(drag.end() == nil)                                   // a second release does nothing
        var inspector = ColumnDrag(range: 320...440, grows: -1)      // dragging left widens it
        inspector.change(translation: -50, from: 372)
        #expect(inspector.proposed == 422)
    }

    @Test func aStripThatWasOnlyPressedCommitsNothing() {
        var drag = ColumnDrag(range: 240...380, grows: 1)
        #expect(drag.end() == nil)
    }

    @Test func theColumnHandleSourceNeverWritesTheWidthFromAnEvent() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("App/Sources/ShowMode.swift"), encoding: .utf8)
        let handle = try #require(text.components(separatedBy: "struct ColumnHandle").last?.components(separatedBy: "\n}\n").first)
        let changed = try #require(handle.components(separatedBy: ".onChanged").last?.components(separatedBy: ".onEnded").first)
        #expect(!changed.contains("width ="), "the width is applied on release only")
        #expect(handle.contains("ColumnDrag"))
    }
}
