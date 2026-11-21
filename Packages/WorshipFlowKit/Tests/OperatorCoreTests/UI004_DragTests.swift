// UI-004: dragging in the slide editor. While the pointer is down the object follows it in the editor only: the presentation, the
// preview, the live output and the save queue are not touched. When the pointer is released the model is written once, as one
// undo step.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI004_DragTests {
    struct Rig {
        let model: WorkspaceModel
        let editor: SlideEditorModel
        let store: LibraryStore
        let clock: ManualSaveClock
        let writes: Counter
        let showChanges: Counter
    }

    @MainActor final class Counter { var n = 0 }

    func ready() async throws -> Rig {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        let writes = Counter(), changes = Counter()
        model.draftWriter = { [store] slide in writes.n += 1; try await store.updateSlide(slide) }
        model.onShowChange = { _ in changes.n += 1 }
        return Rig(model: model, editor: SlideEditorModel(workspace: model), store: store, clock: clock, writes: writes, showChanges: changes)
    }

    @Test func nothingIsWrittenWhileThePointerIsDown() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        await r.clock.advance(by: 6)                       // the add is saved
        let written = r.writes.n
        let storedFrame = try #require(r.model.slides[r.model.show.selectedIndex].content.objects.first).frame
        let changes = r.showChanges.n

        r.editor.beginInteraction()
        for i in 1...60 { r.editor.move(id, from: storedFrame, dx: Double(i) * 0.005, dy: Double(i) * 0.002) }
        // The editor shows the object where the pointer is ...
        let shown = try #require(r.editor.selectedObject).frame
        #expect(abs(shown.x - (storedFrame.x + 0.3)) < 1e-9)
        // ... but the presentation, the preview and the save queue have not been touched.
        #expect(r.model.slides[r.model.show.selectedIndex].content.objects.first?.frame == storedFrame)
        #expect(r.showChanges.n == changes)
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written)
        #expect(try await r.store.slides(of: r.model.openPresentationID!)[0].content.objects.first?.frame == storedFrame)
        r.editor.endInteraction()
    }

    @Test func releasingWritesOnceAndIsOneUndoStep() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        await r.clock.advance(by: 6)
        let written = r.writes.n
        let start = try #require(r.editor.selectedObject).frame

        r.editor.beginInteraction()
        for i in 1...60 { r.editor.move(id, from: start, dx: Double(i) * 0.005, dy: 0) }
        r.editor.endInteraction()
        // One change of the stored slide, saved once.
        let end = try #require(r.model.slides[r.model.show.selectedIndex].content.objects.first).frame
        #expect(abs(end.x - (start.x + 0.3)) < 1e-9)
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1)
        // One undo step: it puts the object back, and the next one takes the add back.
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start)
        r.editor.undo()
        #expect(r.editor.objects.isEmpty)
    }

    @Test func resizingFollowsTheSameRules() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        await r.clock.advance(by: 6)
        let written = r.writes.n
        let start = try #require(r.editor.selectedObject).frame
        r.editor.beginInteraction()
        for i in 1...30 { r.editor.resize(id, from: start, dWidth: Double(i) * 0.002, dHeight: Double(i) * 0.002) }
        #expect(r.model.slides[r.model.show.selectedIndex].content.objects.first?.frame == start)
        #expect(abs((r.editor.selectedObject?.frame.width ?? 0) - (start.width + 0.06)) < 1e-9)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written + 1)
        r.editor.undo()
        #expect(r.editor.selectedObject?.frame == start)
    }

    @Test func aDragOnAnInactiveSlideLeavesLiveUnchanged() async throws {
        let r = try await ready()
        await r.model.goLive(at: 0)                         // slide 1 is live
        let liveBefore = r.model.show.liveDeck
        let liveIndex = r.model.show.liveIndex
        r.model.selectSlide(1)                              // the editor works on slide 2
        let id = try #require(r.editor.add(.rectangle))
        let start = try #require(r.editor.selectedObject).frame
        let liveWithObject = r.model.show.liveDeck
        #expect(liveWithObject == liveBefore)
        let changes = r.showChanges.n
        r.editor.beginInteraction()
        for i in 1...40 { r.editor.move(id, from: start, dx: Double(i) * 0.005, dy: 0.1) }
        #expect(r.model.show.liveDeck == liveBefore && r.model.show.liveIndex == liveIndex)
        #expect(r.showChanges.n == changes)
        r.editor.endInteraction()
        #expect(r.model.show.liveDeck == liveBefore && r.model.show.liveIndex == liveIndex)
    }

    @Test func aMoveWithNoOpenInteractionStillWritesAtOnce() async throws {
        // The inspector's own fields and the keyboard are not drags: they keep writing as they did.
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        let start = try #require(r.editor.selectedObject).frame
        r.editor.move(id, from: start, dx: 0.1, dy: 0)
        #expect(abs((r.model.slides[r.model.show.selectedIndex].content.objects.first?.frame.x ?? 0) - (start.x + 0.1)) < 1e-9)
    }

    @Test func aDragThatEndsWhereItBeganWritesNothing() async throws {
        let r = try await ready()
        let id = try #require(r.editor.add(.rectangle))
        await r.clock.advance(by: 6)
        let written = r.writes.n
        let start = try #require(r.editor.selectedObject).frame
        r.editor.beginInteraction()
        r.editor.move(id, from: start, dx: 0.2, dy: 0.2)
        r.editor.move(id, from: start, dx: 0, dy: 0)
        r.editor.endInteraction()
        await r.clock.advance(by: 6)
        #expect(r.writes.n == written)
    }

    @Test func theDragStartsOnTheFirstMovementPastASmallThreshold() {
        #expect(SlideEditing.dragHasStarted(dx: 0, dy: 0) == false)
        #expect(SlideEditing.dragHasStarted(dx: 1.5, dy: 1.5) == false)
        #expect(SlideEditing.dragHasStarted(dx: 3, dy: 0))
        #expect(SlideEditing.dragHasStarted(dx: 0, dy: -4))
        #expect(SlideEditing.dragThreshold <= 4)
        #expect(SlideEditing.handleHitSize >= 24)
    }
}
