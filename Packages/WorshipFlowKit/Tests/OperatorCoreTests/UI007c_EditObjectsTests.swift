// UI-007c (SLIDE): the Layers list, lock and hide, text Fit and Background fill, and the video object in the slide editor. Each edit is one undo
// step and is kept; a locked object refuses every way of moving, resizing, nudging, aligning or deleting it and says why.
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct UI007c_EditObjectsTests {
    private func ready() async throws -> (model: WorkspaceModel, editor: SlideEditorModel, store: LibraryStore, clock: ManualSaveClock, id: UUID) {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return (model, SlideEditorModel(workspace: model), store, clock, p.id)
    }

    private func object(_ editor: SlideEditorModel, _ id: UUID) -> SlideObject { editor.objects.first { $0.id == id }! }

    // MARK: Layers list

    @Test func theListIsTopFirstSoTheLastObjectIsTheFirstRow() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle)), b = try #require(s.editor.add(.textBox)), c = try #require(s.editor.add(.ellipse))
        let rows = s.editor.layerRows()
        #expect(rows.compactMap(\.objectID) == [c, b, a])
        #expect(rows.map(\.kind) == [.shape, .text, .shape])
        #expect(rows[0].canMoveUp == false && rows[0].canMoveDown && rows[2].canMoveUp && rows[2].canMoveDown == false)
        #expect(rows.first { $0.objectID == c }?.isSelected == true)
    }

    @Test func theSlidesOwnWordsAreRowsAboveEveryObjectThatSelectTheirBox() async throws {
        let s = try await ready()
        s.editor.lyricThemeFrames = { _ in [.primary: NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2), .secondary: NormalizedRect(x: 0.1, y: 0.7, width: 0.8, height: 0.2)] }
        let a = try #require(s.editor.add(.rectangle))
        let rows = s.editor.layerRows()
        #expect(rows.map(\.kind) == [.words, .words, .shape])
        #expect(rows[0].lyricBox == .secondary && rows[1].lyricBox == .primary && rows[2].objectID == a)
        #expect(rows[0].objectID == nil && rows[0].canMoveUp == false && rows[0].canMoveDown == false)
        s.editor.selectLyric(.primary)
        #expect(s.editor.layerRows().map(\.isSelected) == [false, true, false])
    }

    @Test func aRowShowsTheOperatorsNameElseWhatTheObjectIs() async throws {
        let s = try await ready()
        let t = try #require(s.editor.add(.textBox))
        #expect(s.editor.layerRows()[0].title == "Text: Text" && s.editor.layerRows()[0].customName == nil)
        s.editor.setName(t, "  Verse title  ")
        #expect(s.editor.layerRows()[0].title == "Verse title" && s.editor.layerRows()[0].customName == "Verse title")
        s.editor.setName(t, "   ")                                       // blank gives the object its own title back
        #expect(s.editor.layerRows()[0].customName == nil)
        let img = try #require(s.editor.addImage(path: "/pictures/logo.png"))
        #expect(s.editor.layerRows()[0].title == "Image: logo.png" && img != t)
        let clip = UUID()
        let v = try #require(s.editor.addVideo(mediaID: clip))
        #expect(s.editor.layerRows(mediaTitle: { $0 == clip ? "Waves.mov" : nil })[0].title == "Video: Waves.mov")
        #expect(s.editor.layerRows()[0].title == "Video" && s.editor.layerRows()[0].objectID == v)
    }

    @Test func aNameIsOneUndoStepAndIsKept() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setName(id, "Frame")
        await s.clock.advance(by: 2.1)
        #expect(try await s.store.slides(of: s.id)[0].content.objects.first?.name == "Frame")
        s.editor.undo()
        #expect(object(s.editor, id).name == nil)
        s.editor.redo()
        #expect(object(s.editor, id).name == "Frame")
    }

    @Test func hidingKeepsTheObjectAndItsRowAndIsOneUndoStep() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setHidden(id, true)
        #expect(s.editor.objects.count == 1 && object(s.editor, id).isHidden)
        #expect(s.editor.layerRows()[0].isHidden)
        #expect(s.editor.selectedObjectID == id)                       // still selectable, so it can be shown again
        await s.clock.advance(by: 2.1)
        #expect(try await s.store.slides(of: s.id)[0].content.objects.first?.isHidden == true)
        s.editor.undo()
        #expect(!object(s.editor, id).isHidden)
    }

    @Test func movingALayerChangesTheStackOneStepAtATimeAndStopsAtTheEnds() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle)), b = try #require(s.editor.add(.ellipse)), c = try #require(s.editor.add(.roundedRectangle))
        s.editor.moveLayer(a, up: true)
        #expect(s.editor.objects.map(\.id) == [b, a, c])
        s.editor.moveLayer(a, up: true)
        s.editor.moveLayer(a, up: true)                                 // already at the front
        #expect(s.editor.objects.map(\.id) == [b, c, a])
        s.editor.moveLayer(a, up: false)
        #expect(s.editor.objects.map(\.id) == [b, a, c])
        s.editor.undo()
        #expect(s.editor.objects.map(\.id) == [b, c, a])
    }

    // MARK: Lock

    private func lockedBox(_ s: (model: WorkspaceModel, editor: SlideEditorModel, store: LibraryStore, clock: ManualSaveClock, id: UUID)) throws -> (UUID, NormalizedRect) {
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setFrame(id, x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        s.editor.setLocked(id, true)
        return (id, object(s.editor, id).frame)
    }

    @Test func aLockedObjectCannotBeMovedResizedOrNudgedAndSaysWhy() async throws {
        let s = try await ready()
        let (id, frame) = try lockedBox(s)
        s.editor.dismissMessage()
        s.editor.move(id, from: frame, dx: 0.1, dy: 0.1)
        #expect(object(s.editor, id).frame == frame)
        #expect(s.editor.lastMessage?.contains("locked") == true)
        s.editor.dismissMessage()
        s.editor.resize(id, from: frame, dWidth: 0.1, dHeight: 0.1)
        #expect(object(s.editor, id).frame == frame && s.editor.lastMessage != nil)
        s.editor.dismissMessage()
        s.editor.dragFrame(id, to: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(object(s.editor, id).frame == frame && s.editor.dragFrames.isEmpty && s.editor.lastMessage != nil)
        s.editor.dismissMessage()
        s.editor.setFrame(id, x: 0.6, y: 0.6, width: 0.1, height: 0.1)           // typed in the inspector too
        #expect(object(s.editor, id).frame == frame && s.editor.lastMessage != nil)
        s.editor.dismissMessage()
        #expect(s.editor.nudgeSelection(columns: 1, rows: 0, big: true))        // the key is taken (the slide selection does not move)
        #expect(object(s.editor, id).frame == frame && s.editor.lastMessage != nil)
        s.editor.dismissMessage()
        #expect(!s.editor.alignSelected(.center))
        #expect(object(s.editor, id).frame == frame && s.editor.lastMessage != nil)
    }

    @Test func aLockedObjectCannotBeDeletedByAnyPath() async throws {
        let s = try await ready()
        let (id, _) = try lockedBox(s)
        s.editor.dismissMessage()
        s.editor.delete(id)
        #expect(s.editor.objects.count == 1 && s.editor.lastMessage?.contains("locked") == true)
        s.editor.dismissMessage()
        #expect(s.editor.deleteSelected())                                       // the key is taken (it must not fall through), nothing is deleted
        #expect(s.editor.objects.count == 1 && s.editor.lastMessage != nil)
    }

    @Test func aDragThatBeginsOnALockedObjectWritesNothingAndRecordsNoStep() async throws {
        let s = try await ready()
        let (id, frame) = try lockedBox(s)
        s.editor.undo(); s.editor.redo()                                          // settle the history
        let before = s.editor.canUndo
        s.editor.beginInteraction()
        s.editor.move(id, from: frame, dx: 0.2, dy: 0.2)
        s.editor.endInteraction()
        #expect(object(s.editor, id).frame == frame && s.editor.canUndo == before)
    }

    @Test func unlockingGivesBackEveryMoveAndLockingIsOneUndoStep() async throws {
        let s = try await ready()
        let (id, frame) = try lockedBox(s)
        s.editor.setLocked(id, false)
        s.editor.move(id, from: frame, dx: 0.1, dy: 0.0)
        #expect(object(s.editor, id).frame.x > frame.x)
        s.editor.undo()                                                           // the move
        s.editor.undo()                                                           // the unlock
        #expect(object(s.editor, id).isLocked)
        s.editor.redo()
        #expect(!object(s.editor, id).isLocked)
    }

    @Test func otherEditsOfALockedObjectStillWorkAndALockedObjectCanBeReordered() async throws {
        let s = try await ready()
        let (id, _) = try lockedBox(s)
        let other = try #require(s.editor.add(.ellipse))
        s.editor.setOpacity(id, 0.5)
        s.editor.setHidden(id, true)
        s.editor.moveLayer(id, up: true)
        #expect(object(s.editor, id).opacity == 0.5 && object(s.editor, id).isHidden && s.editor.objects.map(\.id) == [other, id])
        #expect(s.editor.duplicate(id) != nil)                                    // a copy is allowed: nothing is moved or lost
    }

    @Test func lockAndHideAreIndependentAndLockedStaysSelectable() async throws {
        let s = try await ready()
        let (id, _) = try lockedBox(s)
        s.editor.select(nil)
        s.editor.select(id)
        #expect(s.editor.selectedObjectID == id)
        #expect(s.editor.layerRows()[0].isLocked && !s.editor.layerRows()[0].isHidden)
    }

    // MARK: Text Fit and Background fill

    @Test func fitAndFillAreEditsOfATextBoxKeptWithTheSlideAndOneUndoEach() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.textBox))
        s.editor.setFit(id, .shrinkToFit)
        s.editor.setBackgroundFill(id, ColorRGBA(red: 0, green: 0, blue: 0, alpha: 0.5))
        await s.clock.advance(by: 2.1)
        guard case .text(let stored) = try await s.store.slides(of: s.id)[0].content.objects[0].content else { Issue.record("not text"); return }
        #expect(stored.fit == .shrinkToFit && stored.backgroundFill?.alpha == 0.5)
        s.editor.undo()
        guard case .text(let a) = object(s.editor, id).content else { return }
        #expect(a.fit == .shrinkToFit && a.backgroundFill == nil)
        s.editor.undo()
        guard case .text(let b) = object(s.editor, id).content else { return }
        #expect(b.fit == .none)
    }

    @Test func aRunOfColourChoicesForTheFillIsOneUndoStep() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.textBox))
        s.editor.setBackgroundFill(id, .white)
        s.editor.setBackgroundFill(id, .black)
        s.editor.setBackgroundFill(id, ColorRGBA(red: 0.2, green: 0.4, blue: 0.6))
        s.editor.undo()
        guard case .text(let t) = object(s.editor, id).content else { return }
        #expect(t.backgroundFill == nil)
    }

    @Test func fitAndFillDoNothingToAShape() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        let before = object(s.editor, id)
        s.editor.setFit(id, .shrinkToFit)
        s.editor.setBackgroundFill(id, .white)
        #expect(object(s.editor, id) == before)
    }

    // MARK: Video object

    @Test func aVideoObjectIsPlacedLoopedAndMutedInFreeSpaceSelectedAndOneUndoStep() async throws {
        let s = try await ready()
        let clip = UUID()
        let id = try #require(s.editor.addVideo(mediaID: clip))
        let o = object(s.editor, id)
        #expect(o.content == .video(VideoObject(mediaID: clip, loops: true, muted: true)))
        #expect(s.editor.selectedObjectID == id)
        #expect(abs(o.frame.width * 1920 / (o.frame.height * 1080) - 16.0 / 9.0) < 0.01, "a 16:9 clip is placed at its own shape")
        await s.clock.advance(by: 2.1)
        #expect(try await s.store.slides(of: s.id)[0].content.objects.first?.content == .video(VideoObject(mediaID: clip)))
        s.editor.undo()
        #expect(s.editor.objects.isEmpty)
    }

    @Test func loopAndSoundAreEditsOfTheVideoObject() async throws {
        let s = try await ready()
        let id = try #require(s.editor.addVideo(mediaID: UUID()))
        s.editor.setVideoLoops(id, false)
        s.editor.setVideoMuted(id, false)
        guard case .video(let v) = object(s.editor, id).content else { Issue.record("not video"); return }
        #expect(!v.loops && !v.muted)
        s.editor.undo()
        guard case .video(let w) = object(s.editor, id).content else { return }
        #expect(!w.loops && w.muted)
        let text = try #require(s.editor.add(.textBox))
        let before = object(s.editor, text)
        s.editor.setVideoLoops(text, false)                                       // not a video: nothing changes
        #expect(object(s.editor, text) == before)
    }

    @Test func aTwoVideosSlideKeepsBothClips() async throws {
        let s = try await ready()
        let a = UUID(), b = UUID()
        _ = s.editor.addVideo(mediaID: a)
        _ = s.editor.addVideo(mediaID: b)
        let clips = s.editor.objects.compactMap { o -> UUID? in if case .video(let v) = o.content { v.mediaID } else { nil } }
        #expect(clips == [a, b])
    }

    // MARK: Editing never changes what is live

    @Test func hidingOrLockingOrAddingAVideoLeavesTheLiveSlideAsItWas() async throws {
        let s = try await ready()
        s.model.selectSlide(0)
        s.model.goLive(at: 0)
        let liveBefore = s.model.show.liveSlide
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setHidden(id, true)
        s.editor.setLocked(id, true)
        _ = s.editor.addVideo(mediaID: UUID())
        #expect(s.model.show.liveSlide == liveBefore)
    }
}
