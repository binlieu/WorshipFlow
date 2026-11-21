// SLIDE-001b (PRES-01, MEDIA-07): the slide editor model (written by the implementer; no coordinator test defines it).
import Testing
import Foundation
import Domain
import Persistence
@testable import OperatorCore

@MainActor
@Suite struct SlideEditorModelTests {
    struct Setup {
        let model: WorkspaceModel
        let editor: SlideEditorModel
        let store: LibraryStore
        let clock: ManualSaveClock
        let presentationID: UUID
    }

    func ready(chooser: SlideImageChooser? = nil) async throws -> Setup {
        let clock = ManualSaveClock()
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: clock)
        await model.load()
        let p = try #require(await model.importLyrics(title: "Song", primaryText: "one\n\ntwo\n\nthree", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        return Setup(model: model, editor: SlideEditorModel(workspace: model, imageChooser: chooser), store: store, clock: clock,
                     presentationID: p.id)
    }

    func objectCount(_ s: Setup) -> Int { s.model.slides[s.model.show.selectedIndex].content.objects.count }

    // MARK: Adding

    @Test func everyKindCanBeAddedSelectedAndSavedWithinTwoSeconds() async throws {
        let s = try await ready()
        let ids = [s.editor.add(.textBox), s.editor.add(.rectangle), s.editor.add(.ellipse), s.editor.add(.roundedRectangle),
                   s.editor.addImage(path: "/tmp/picture.png")].compactMap { $0 }
        #expect(ids.count == 5 && Set(ids).count == 5)
        #expect(s.editor.objects.map(\.id) == ids)
        #expect(s.editor.selectedObjectID == ids.last)
        let kinds = s.editor.objects.map(\.content)
        guard case .text = kinds[0], case .shape(let rect) = kinds[1], case .shape(let ellipse) = kinds[2],
              case .shape(let rounded) = kinds[3], case .image(let image) = kinds[4] else {
            Issue.record("unexpected kinds \(kinds)"); return
        }
        #expect(rect.shape == .rectangle && ellipse.shape == .ellipse)
        if case .roundedRectangle(let r) = rounded.shape { #expect(r > 0 && r <= 0.5) } else { Issue.record("not rounded") }
        #expect(image.path == "/tmp/picture.png")
        #expect(try await s.store.slides(of: s.presentationID)[0].content.objects.isEmpty)      // not written yet
        await s.clock.advance(by: 2.1)
        #expect(try await s.store.slides(of: s.presentationID)[0].content.objects.map(\.id) == ids)
    }

    @Test func newObjectsDoNotLandOnTopOfEachOther() async throws {
        let s = try await ready()
        for _ in 0..<4 { s.editor.add(.rectangle) }
        let frames = s.editor.objects.map(\.frame)
        for i in frames.indices { for j in frames.indices where i < j { #expect(FreeSpace.overlap(frames[i], frames[j]) == 0, "\(i) \(j)") } }
        s.editor.add(.textBox)
        let text = try #require(s.editor.objects.last).frame
        #expect(frames.allSatisfy { FreeSpace.overlap($0, text) == 0 })
    }

    @Test func theImageChooserSuppliesThePathAndCancelAddsNothing() async throws {
        var answers: [String?] = ["/tmp/a.png", nil]
        let s = try await ready(chooser: { answers.removeFirst() })
        let id = await s.editor.addImage()
        #expect(id != nil && objectCount(s) == 1)
        #expect(await s.editor.addImage() == nil && objectCount(s) == 1)
        let none = try await ready()
        #expect(await none.editor.addImage() == nil && none.editor.lastMessage != nil)
    }

    @Test func nothingIsAddedWithoutAnOpenSlide() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let editor = SlideEditorModel(workspace: model)
        #expect(editor.add(.rectangle) == nil && editor.slide == nil && editor.objects.isEmpty)
        editor.undo(); editor.redo()
        #expect(!editor.deleteSelected() && editor.duplicateSelected() == nil)
    }

    // MARK: Selection

    @Test func selectionBelongsToItsSlide() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        #expect(s.editor.selectedObject?.id == id)
        s.model.selectSlide(1)
        #expect(s.editor.selectedObjectID == nil && s.editor.objects.isEmpty)
        s.model.selectSlide(0)
        #expect(s.editor.selectedObjectID == id)
        s.editor.select(UUID())
        #expect(s.editor.selectedObjectID == nil)
        s.editor.select(id)
        s.editor.select(nil)
        #expect(s.editor.selectedObjectID == nil)
    }

    // MARK: Moving and resizing

    @Test func aDragIsMeasuredFromWhereItStartedAndStaysOnTheSlide() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        let start = try #require(s.editor.selectedObject).frame
        s.editor.beginInteraction()
        s.editor.move(id, from: start, dx: 0.1, dy: 0.05)
        s.editor.move(id, from: start, dx: 0.15, dy: 0.1)
        var now = try #require(s.editor.selectedObject).frame
        #expect(abs(now.x - (start.x + 0.15)) < 1e-9 && abs(now.y - (start.y + 0.1)) < 1e-9)
        #expect(now.width == start.width && now.height == start.height)
        s.editor.move(id, from: start, dx: 9, dy: 9)
        now = try #require(s.editor.selectedObject).frame
        #expect(abs(now.x - (1 - start.width)) < 1e-9 && abs(now.y - (1 - start.height)) < 1e-9)
        s.editor.move(id, from: start, dx: 0, dy: 0)
        #expect(s.editor.selectedObject?.frame == start)
        s.editor.endInteraction()
    }

    @Test func resizingKeepsTheCornerAndTheMinimumSize() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        let start = try #require(s.editor.selectedObject).frame
        s.editor.resize(id, from: start, dWidth: 0.1, dHeight: 0.05)
        var f = try #require(s.editor.selectedObject).frame
        #expect(f.x == start.x && f.y == start.y)
        #expect(abs(f.width - (start.width + 0.1)) < 1e-9 && abs(f.height - (start.height + 0.05)) < 1e-9)
        s.editor.resize(id, from: start, dWidth: -5, dHeight: -5)
        f = try #require(s.editor.selectedObject).frame
        #expect(f.width == SlideObject.minimumSize && f.height == SlideObject.minimumSize)
        s.editor.resize(id, from: start, dWidth: 5, dHeight: 5)
        f = try #require(s.editor.selectedObject).frame
        #expect(f.x + f.width <= 1.0000001 && f.y + f.height <= 1.0000001)
    }

    @Test func typedFramesAreKeptOnTheSlide() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setFrame(id, x: 0.9, y: 0.95, width: 0.4, height: 0.2)
        let f = try #require(s.editor.selectedObject).frame
        #expect(f.width == 0.4 && f.height == 0.2 && abs(f.x - 0.6) < 1e-9 && abs(f.y - 0.8) < 1e-9)
        s.editor.setFrame(id, x: 0.1, y: 0.1, width: 0, height: .nan)
        let tiny = try #require(s.editor.selectedObject).frame
        #expect(tiny.width == SlideObject.minimumSize && tiny.height >= SlideObject.minimumSize)
    }

    // MARK: Text

    @Test func textAndItsStyleCanBeChanged() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.textBox))
        let red = ColorRGBA(red: 1, green: 0, blue: 0)
        s.editor.setText(id, "Hello")
        s.editor.setFontName(id, "Georgia")
        s.editor.setFontSize(id, 120)
        s.editor.setTextColor(id, red)
        s.editor.setOutline(id, width: 4, color: .black)
        s.editor.setShadow(id, TextShadow(offsetX: 3, offsetY: 4, blur: 5))
        s.editor.setAlignment(id, .trailing)
        s.editor.setVerticalAlignment(id, .bottom)
        guard case .text(let t) = try #require(s.editor.selectedObject).content else { Issue.record("not text"); return }
        #expect(t.text == "Hello" && t.style.fontName == "Georgia" && t.style.fontSize == 120 && t.style.color == red)
        #expect(t.style.outlineWidth == 4 && t.style.shadow == TextShadow(offsetX: 3, offsetY: 4, blur: 5))
        #expect(t.alignment == .trailing && t.verticalAlignment == .bottom)
        s.editor.setShadow(id, nil)
        guard case .text(let cleared) = try #require(s.editor.selectedObject).content else { return }
        #expect(cleared.style.shadow == nil)
    }

    @Test func textValuesStayInsideWhatCanBeDrawn() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.textBox))
        s.editor.setFontSize(id, 100_000)
        s.editor.setFontName(id, "   ")
        s.editor.setOutline(id, width: .infinity)
        s.editor.setShadow(id, TextShadow(offsetX: 9999, offsetY: -9999, blur: 9999))
        guard case .text(let t) = try #require(s.editor.selectedObject).content else { return }
        #expect(t.style.fontSize == SlideEditing.fontSizeRange.upperBound)
        #expect(t.style.fontName == ThemeEditing.defaultFontName)
        #expect(t.style.outlineWidth == 0)
        #expect(t.style.shadow?.offsetX == SlideEditing.shadowOffsetRange.upperBound)
        #expect(t.style.shadow?.offsetY == SlideEditing.shadowOffsetRange.lowerBound)
        #expect(t.style.shadow?.blur == SlideEditing.shadowBlurRange.upperBound)
        s.editor.setFontSize(id, 1)
        guard case .text(let small) = try #require(s.editor.selectedObject).content else { return }
        #expect(small.style.fontSize == SlideEditing.fontSizeRange.lowerBound)
    }

    // MARK: Shapes, images, opacity

    @Test func shapeFillStrokeAndCornersCanBeChanged() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.roundedRectangle))
        let green = ColorRGBA(red: 0, green: 1, blue: 0)
        s.editor.setFill(id, green)
        s.editor.setStrokeColor(id, .white)
        s.editor.setStrokeWidth(id, 6)
        s.editor.setCornerRadius(id, 0.35)
        guard case .shape(let shape) = try #require(s.editor.selectedObject).content else { return }
        #expect(shape.fill == green && shape.strokeColor == .white && shape.strokeWidth == 6)
        #expect(shape.shape == .roundedRectangle(cornerRadius: 0.35))
        s.editor.setCornerRadius(id, 7)
        s.editor.setStrokeWidth(id, -3)
        s.editor.setFill(id, nil)
        guard case .shape(let limited) = try #require(s.editor.selectedObject).content else { return }
        #expect(limited.shape == .roundedRectangle(cornerRadius: 0.5) && limited.strokeWidth == 0 && limited.fill == nil)
    }

    @Test func aPlainRectangleHasNoCornerRadiusToChange() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        let before = try #require(s.editor.selectedObject)
        s.editor.setCornerRadius(id, 0.3)
        #expect(s.editor.selectedObject == before)
        s.editor.setText(id, "x")                         // not a text box either
        s.editor.setImageContentMode(id, .fill)
        #expect(s.editor.selectedObject == before)
    }

    @Test func imagesCanSwitchBetweenFitAndFill() async throws {
        let s = try await ready()
        let id = try #require(s.editor.addImage(path: "/tmp/p.png"))
        s.editor.setImageContentMode(id, .fill)
        guard case .image(let image) = try #require(s.editor.selectedObject).content else { return }
        #expect(image.contentMode == .fill)
        #expect(s.editor.addImage(path: "") == nil)
    }

    @Test func opacityIsClamped() async throws {
        let s = try await ready()
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setOpacity(id, 0.4)
        #expect(s.editor.selectedObject?.opacity == 0.4)
        s.editor.setOpacity(id, 3)
        #expect(s.editor.selectedObject?.opacity == 1)
        s.editor.setOpacity(id, -1)
        #expect(s.editor.selectedObject?.opacity == 0)
    }

    @Test func anUnknownObjectChangesNothing() async throws {
        let s = try await ready()
        s.editor.add(.rectangle)
        let before = s.editor.objects
        let stranger = UUID()
        s.editor.setOpacity(stranger, 0.1)
        s.editor.setFill(stranger, .black)
        s.editor.bringToFront(stranger)
        s.editor.delete(stranger)
        #expect(s.editor.duplicate(stranger) == nil)
        #expect(s.editor.objects == before)
        s.editor.undo()                                   // the only undo step is the add
        #expect(s.editor.objects.isEmpty)
    }

    // MARK: Stacking order, duplicate, delete

    @Test func stackingOrderCanBeChanged() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let b = try #require(s.editor.add(.ellipse))
        let c = try #require(s.editor.add(.textBox))
        s.editor.bringToFront(a)
        #expect(s.editor.objects.map(\.id) == [b, c, a])
        s.editor.sendToBack(a)
        #expect(s.editor.objects.map(\.id) == [a, b, c])
        s.editor.bringForward(a)
        #expect(s.editor.objects.map(\.id) == [b, a, c])
        s.editor.sendBackward(c)
        #expect(s.editor.objects.map(\.id) == [b, c, a])
        s.editor.sendBackward(b)                          // already at the back: no step recorded
        s.editor.undo()
        #expect(s.editor.objects.map(\.id) == [b, a, c])
    }

    @Test func duplicateMakesAnOffsetCopyAboveTheOriginalAndSelectsIt() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let b = try #require(s.editor.add(.ellipse))
        s.editor.select(a)
        let copy = try #require(s.editor.duplicateSelected())
        #expect(copy != a && copy != b)
        #expect(s.editor.objects.map(\.id) == [a, copy, b])
        #expect(s.editor.selectedObjectID == copy)
        let original = try #require(s.editor.objects.first { $0.id == a })
        let made = try #require(s.editor.objects.first { $0.id == copy })
        #expect(made.content == original.content && made.frame != original.frame)
        #expect(made.frame.width == original.frame.width && made.frame.height == original.frame.height)
        #expect(abs(made.frame.x - original.frame.x) <= 0.05 && abs(made.frame.y - original.frame.y) <= 0.05)
    }

    @Test func duplicatingAgainstTheEdgeStillOffsetsTheCopy() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let start = try #require(s.editor.selectedObject).frame
        s.editor.move(a, from: start, dx: 5, dy: 5)
        let copy = try #require(s.editor.duplicate(a))
        let frames = s.editor.objects
        #expect(frames.first { $0.id == copy }?.frame != frames.first { $0.id == a }?.frame)
    }

    @Test func deleteRemovesTheSelectedObjectOnly() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let b = try #require(s.editor.add(.ellipse))
        #expect(s.editor.deleteSelected())
        #expect(s.editor.objects.map(\.id) == [a] && s.editor.selectedObjectID == nil)
        #expect(!s.editor.deleteSelected())              // nothing selected now
        #expect(s.editor.objects.map(\.id) == [a])
        s.editor.delete(a)
        #expect(s.editor.objects.isEmpty)
        _ = b
    }

    // MARK: Undo and redo

    @Test func everyKindOfEditCanBeUndoneAndRedone() async throws {
        let s = try await ready()
        let t = try #require(s.editor.add(.textBox))
        let r = try #require(s.editor.add(.rectangle))
        let actions: [(String, () -> Void)] = [
            ("move", { s.editor.move(r, from: s.editor.selectedObject!.frame, dx: 0.1, dy: 0.1) }),
            ("resize", { s.editor.resize(r, from: s.editor.selectedObject!.frame, dWidth: 0.1, dHeight: 0.1) }),
            ("text", { s.editor.setText(t, "changed") }),
            ("font", { s.editor.setFontName(t, "Georgia") }),
            ("size", { s.editor.setFontSize(t, 99) }),
            ("colour", { s.editor.setTextColor(t, ColorRGBA(red: 1, green: 0, blue: 0)) }),
            ("outline", { s.editor.setOutline(t, width: 5) }),
            ("shadow", { s.editor.setShadow(t, TextShadow(offsetX: 2, offsetY: 2, blur: 2)) }),
            ("align", { s.editor.setAlignment(t, .leading) }),
            ("fill", { s.editor.setFill(r, ColorRGBA(red: 0, green: 1, blue: 0)) }),
            ("stroke", { s.editor.setStrokeWidth(r, 5) }),
            ("opacity", { s.editor.setOpacity(r, 0.5) }),
            ("front", { s.editor.bringToFront(t) }),
            ("duplicate", { s.editor.duplicate(r) }),
            ("delete", { s.editor.delete(t) }),
        ]
        for (name, act) in actions {
            let before = s.editor.objects
            act()
            let after = s.editor.objects
            #expect(after != before, "\(name) changed nothing")
            s.editor.undo()
            #expect(s.editor.objects == before, "undo \(name)")
            s.editor.redo()
            #expect(s.editor.objects == after, "redo \(name)")
        }
        // All the way back to the start, then forward again.
        let final = s.editor.objects
        var steps = 0
        while s.editor.canUndo { s.editor.undo(); steps += 1 }
        #expect(s.editor.objects.isEmpty && steps == actions.count + 2)
        while s.editor.canRedo { s.editor.redo() }
        #expect(s.editor.objects == final)
    }

    @Test func undoOfAnAddRestoresTheSelection() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        s.editor.add(.ellipse)
        s.editor.undo()
        #expect(s.editor.objects.map(\.id) == [a] && s.editor.selectedObjectID == a)
        s.editor.undo()
        #expect(s.editor.objects.isEmpty && s.editor.selectedObjectID == nil)
        #expect(!s.editor.canUndo && s.editor.canRedo)
    }

    @Test func aNewEditAfterUndoDropsTheRedoSteps() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        s.editor.setOpacity(a, 0.5)
        s.editor.undo()
        #expect(s.editor.canRedo)
        s.editor.setOpacity(a, 0.25)
        #expect(!s.editor.canRedo)
        s.editor.redo()
        #expect(s.editor.selectedObject?.opacity == 0.25)
    }

    @Test func aDragIsOneUndoStep() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let start = try #require(s.editor.selectedObject).frame
        s.editor.beginInteraction()
        for i in 1...20 { s.editor.move(a, from: start, dx: Double(i) * 0.01, dy: 0) }
        s.editor.endInteraction()
        s.editor.undo()
        #expect(s.editor.selectedObject?.frame == start)
        s.editor.redo()
        #expect(abs((s.editor.selectedObject?.frame.x ?? 0) - (start.x + 0.2)) < 1e-9)
        s.editor.undo()
        s.editor.undo()                                    // second undo takes the add back
        #expect(s.editor.objects.isEmpty)
    }

    @Test func aDragThatMovedNothingLeavesNoStep() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        let start = try #require(s.editor.selectedObject).frame
        s.editor.beginInteraction()
        s.editor.move(a, from: start, dx: 0.1, dy: 0)
        s.editor.move(a, from: start, dx: 0, dy: 0)
        s.editor.endInteraction()
        s.editor.undo()
        #expect(s.editor.objects.isEmpty)                  // that undo went to the add: no drag step existed
    }

    @Test func typingARunOfTextIsOneStep() async throws {
        let s = try await ready()
        let t = try #require(s.editor.add(.textBox))
        for text in ["H", "He", "Hel", "Hell", "Hello"] { s.editor.setText(t, text) }
        s.editor.undo()
        guard case .text(let original) = try #require(s.editor.selectedObject).content else { return }
        #expect(original.text == "Text")
        s.editor.redo()
        guard case .text(let typed) = try #require(s.editor.selectedObject).content else { return }
        #expect(typed.text == "Hello")
        // A different edit in between starts a new step.
        s.editor.setText(t, "A")
        s.editor.setFontSize(t, 50)
        s.editor.setText(t, "AB")
        s.editor.undo()
        guard case .text(let afterUndo) = try #require(s.editor.selectedObject).content else { return }
        #expect(afterUndo.text == "A" && afterUndo.style.fontSize == 50)
    }

    @Test func historyIsBoundedToOneHundredSteps() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        s.editor.add(.ellipse)
        for i in 0..<130 { if i.isMultiple(of: 2) { s.editor.bringForward(a) } else { s.editor.sendBackward(a) } }
        var steps = 0
        while s.editor.canUndo { s.editor.undo(); steps += 1 }
        #expect(steps == SlideEditing.historyLimit)
    }

    @Test func undoDoesNotRollBackWordsTypedInTheOtherEditor() async throws {
        let s = try await ready()
        let a = try #require(s.editor.add(.rectangle))
        s.editor.setOpacity(a, 0.5)
        var content = s.model.slides[0].content
        content.primary = "typed elsewhere"
        s.model.editSlide(id: s.model.slides[0].id, content: content)
        s.editor.undo()
        #expect(s.model.slides[0].content.primary == "typed elsewhere")
        #expect(s.editor.selectedObject?.opacity == 1)
    }

    @Test func historyIsPerSlide() async throws {
        let s = try await ready()
        s.editor.add(.rectangle)
        s.model.selectSlide(1)
        #expect(!s.editor.canUndo)
        s.editor.add(.ellipse)
        s.model.selectSlide(0)
        s.editor.undo()
        #expect(s.editor.objects.isEmpty)
        s.model.selectSlide(1)
        #expect(s.editor.objects.count == 1)
    }

    // MARK: Saving, preview and live

    @Test func editsReachThePreviewAtOnceButNotTheLiveOutput() async throws {
        let s = try await ready()
        s.model.goLive(at: 0)
        let liveBefore = try #require(s.model.show.liveDeck)
        #expect(liveBefore.slides[0].objects.isEmpty)
        let id = try #require(s.editor.add(.rectangle))
        s.editor.setOpacity(id, 0.3)
        #expect(s.model.show.previewDeck?.slides[0].objects.count == 1)        // preview shows it now
        #expect(s.model.show.liveDeck == liveBefore)                          // live is untouched
        #expect(s.model.show.liveDeck?.slides[0].objects.isEmpty == true)
        s.editor.undo()
        s.editor.deleteSelected()
        #expect(s.model.show.liveDeck == liveBefore)
        s.editor.add(.ellipse)
        s.model.goLive(at: 0)                                                   // triggered again: now it goes out
        #expect(s.model.show.liveDeck?.slides[0].objects.count == 1)
    }

    @Test func undoAndRedoAreSavedLikeAnyEdit() async throws {
        let s = try await ready()
        s.editor.add(.rectangle)
        await s.model.flush()
        #expect(try await s.store.slides(of: s.presentationID)[0].content.objects.count == 1)
        s.editor.undo()
        await s.model.flush()
        #expect(try await s.store.slides(of: s.presentationID)[0].content.objects.isEmpty)
        s.editor.redo()
        await s.model.flush()
        #expect(try await s.store.slides(of: s.presentationID)[0].content.objects.count == 1)
    }

    @Test func switchingPresentationDropsTheHistory() async throws {
        let s = try await ready()
        s.editor.add(.rectangle)
        #expect(s.editor.canUndo)
        let other = try #require(await s.model.importLyrics(title: "Other", primaryText: "x", secondaryText: nil, maxLines: 1))
        await s.model.openPresentation(other.id)
        #expect(!s.editor.canUndo && s.editor.objects.isEmpty)
        s.editor.add(.ellipse)                              // first edit after the switch resets stale state
        await s.model.openPresentation(s.presentationID)
        #expect(!s.editor.canUndo)
    }
}

// A quick edit of the live slide changes the live words and saves the words, and leaves objects edited in preview alone.
@MainActor
@Suite struct QuickEditWithObjectsTests {
    @Test func quickEditSavesWordsAndKeepsThePreviewObjects() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "S", primaryText: "one", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        let editor = SlideEditorModel(workspace: model)
        model.goLive(at: 0)
        editor.add(.rectangle)                                      // an object edited in preview after going live
        var live = try #require(model.show.liveSlide)
        live.primary = "ONE"
        await model.quickEditLiveSlide(live)
        #expect(model.show.liveSlide?.primary == "ONE" && model.show.liveSlide?.objects.isEmpty == true)
        let saved = try await store.slides(of: p.id)[0].content
        #expect(saved.primary == "ONE" && saved.objects.count == 1)
    }
}

@MainActor
@Suite struct SlideEditorReservedSpaceTests {
    @Test func newObjectsKeepClearOfTheSlidesOwnWords() async throws {
        let store = try LibraryStore.inMemory()
        let model = WorkspaceModel(store: store, clock: ManualSaveClock())
        await model.load()
        let p = try #require(await model.importLyrics(title: "S", primaryText: "words", secondaryText: nil, maxLines: 1))
        await model.openPresentation(p.id)
        let editor = SlideEditorModel(workspace: model)
        let words = NormalizedRect(x: 0.1, y: 0.4, width: 0.8, height: 0.2)           // the middle band, where a new box would go
        editor.reservedFrames = { _ in [words] }
        editor.add(.rectangle)
        let frame = try #require(editor.selectedObject).frame
        #expect(FreeSpace.overlap(frame, words) == 0)
    }
}
