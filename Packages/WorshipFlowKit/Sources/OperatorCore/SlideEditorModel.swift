// SLIDE-001b (PRES-01, MEDIA-07): editing the objects (text boxes, shapes, images) of the selected slide of the open
// presentation. Every change goes through `WorkspaceModel.editSlide`, so it shows in preview at once, is saved by the
// same debounced path as typed text, and never reaches the live output until the slide is triggered again.
// Undo keeps snapshots of the slide's object list, so words typed in the other editor are never rolled back.
// Foundation, Observation and Domain only; the views live in the app target.
import Foundation
import Observation
import Domain

/// Returns the path of an image the operator chose, or nil if they cancelled. The app shows the open panel; tests pass a closure.
public typealias SlideImageChooser = @MainActor () async -> String?

@MainActor
@Observable
public final class SlideEditorModel {
    private struct Snapshot {
        var objects: [SlideObject]
        var selected: UUID?
    }

    private struct History {
        var undo: [Snapshot] = []
        var redo: [Snapshot] = []
        /// The kind of the last edit, so a run of the same edit (typing, dragging a slider) is one undo step.
        var lastKey: String?
    }

    @ObservationIgnored private let workspace: WorkspaceModel
    @ObservationIgnored private let chooseImage: SlideImageChooser?
    @ObservationIgnored private var histories: [UUID: History] = [:]
    @ObservationIgnored private var historyPresentation: UUID?
    @ObservationIgnored private var interactionBase: (slideID: UUID, snapshot: Snapshot)?

    /// Selection is remembered with its slide, so choosing another slide shows no selection.
    private var selection: (slideID: UUID, objectID: UUID)?
    /// Set when something could not be done (for example no image was chosen); a message a volunteer can act on.
    public private(set) var lastMessage: String?

    /// Frames the slide's own words take on screen (from the theme), which new objects keep clear of where there is room.
    /// The app supplies them, because the theme is not known here.
    @ObservationIgnored public var reservedFrames: @MainActor (SlideContent) -> [NormalizedRect] = { _ in [] }

    public init(workspace: WorkspaceModel, imageChooser: SlideImageChooser? = nil) {
        self.workspace = workspace
        self.chooseImage = imageChooser
    }

    // MARK: What the interface reads

    /// The selected slide of the open presentation.
    public var slide: Slide? {
        let slides = workspace.slides
        let index = workspace.show.selectedIndex
        return slides.indices.contains(index) ? slides[index] : nil
    }

    /// Objects of the selected slide, back to front.
    public var objects: [SlideObject] { slide?.content.objects ?? [] }

    public var selectedObjectID: UUID? {
        guard let slide, let selection, selection.slideID == slide.id,
              slide.content.objects.contains(where: { $0.id == selection.objectID }) else { return nil }
        return selection.objectID
    }

    public var selectedObject: SlideObject? {
        guard let id = selectedObjectID else { return nil }
        return objects.first { $0.id == id }
    }

    public var canUndo: Bool { !(history?.undo.isEmpty ?? true) }
    public var canRedo: Bool { !(history?.redo.isEmpty ?? true) }

    public func dismissMessage() { lastMessage = nil }

    // MARK: Selection

    public func select(_ id: UUID?) {
        guard let slide else { return }
        if let id, slide.content.objects.contains(where: { $0.id == id }) {
            selection = (slide.id, id)
        } else {
            selection = nil
        }
    }

    // MARK: Adding

    /// Adds an object in free space where there is room, selects it, and returns its id.
    @discardableResult
    public func add(_ template: NewSlideObject) -> UUID? {
        guard let slide else { lastMessage = "Select a slide first."; return nil }
        let size = SlideEditing.defaultSize(of: template)
        let frame = FreeSpace.place(width: size.width, height: size.height, avoiding: slide.content.objects.map(\.frame) + reservedFrames(slide.content),
                                    preferred: ((1 - size.width) / 2, (1 - size.height) / 2))
        let object = SlideEditing.newObject(template, frame: frame)
        mutate(slide, key: nil, selecting: object.id) { $0.append(object) }
        return object.id
    }

    /// Asks the chooser for an image and adds it. Nothing happens if it is cancelled.
    @discardableResult
    public func addImage() async -> UUID? {
        guard let chooseImage else { lastMessage = "Choosing an image is not available."; return nil }
        guard let path = await chooseImage() else { return nil }
        return addImage(path: path)
    }

    @discardableResult
    public func addImage(path: String) -> UUID? {
        guard !path.isEmpty else { return nil }
        return add(.image(path: path))
    }

    // MARK: Moving and resizing

    /// Call when a drag begins and `endInteraction()` when it ends, so the whole drag is one undo step.
    public func beginInteraction() {
        guard let slide else { return }
        interactionBase = (slide.id, Snapshot(objects: slide.content.objects, selected: selectedObjectID))
    }

    public func endInteraction() {
        guard let base = interactionBase else { return }
        interactionBase = nil
        guard let current = workspace.slides.first(where: { $0.id == base.slideID }),
              current.content.objects != base.snapshot.objects else { return }
        record(base.snapshot, forSlide: base.slideID, key: nil)
    }

    /// Puts the object where `start` was, moved by (`dx`, `dy`) slide fractions, kept on the slide. Measuring from the
    /// start frame lets a drag go back to exactly where it began.
    public func move(_ id: UUID, from start: NormalizedRect, dx: Double, dy: Double) {
        edit(id, key: "frame") { o in
            o.frame = start
            o.move(dx: dx, dy: dy)
        }
    }

    /// Resizes from the corner that does not move: the size is `start`'s plus the given change.
    public func resize(_ id: UUID, from start: NormalizedRect, dWidth: Double, dHeight: Double) {
        edit(id, key: "frame") { o in
            o.frame = start
            o.resize(width: start.width + dWidth, height: start.height + dHeight)
        }
    }

    /// Sets the frame from typed values (fractions of the slide), kept on the slide and at least the minimum size.
    public func setFrame(_ id: UUID, x: Double, y: Double, width: Double, height: Double) {
        edit(id, key: "frame") { $0.frame = NormalizedRect(x: x, y: y, width: width, height: height) }
    }

    // MARK: Text

    public func setText(_ id: UUID, _ text: String) {
        edit(id, key: "text") { o in if case .text(var t) = o.content { t.text = text; o.content = .text(t) } }
    }

    public func setFontName(_ id: UUID, _ name: String) {
        editStyle(id, key: "font") { $0.fontName = name }
    }

    public func setFontSize(_ id: UUID, _ size: Double) {
        editStyle(id, key: "size") { $0.fontSize = size }
    }

    public func setTextColor(_ id: UUID, _ color: ColorRGBA) {
        editStyle(id, key: "colour") { $0.color = color }
    }

    public func setOutline(_ id: UUID, width: Double? = nil, color: ColorRGBA? = nil) {
        editStyle(id, key: "outline") { style in
            if let width { style.outlineWidth = width }
            if let color { style.outlineColor = color }
        }
    }

    /// Nil removes the shadow.
    public func setShadow(_ id: UUID, _ shadow: TextShadow?) {
        editStyle(id, key: "shadow") { $0.shadow = shadow }
    }

    public func setAlignment(_ id: UUID, _ alignment: Domain.TextAlignment) {
        edit(id, key: "alignment") { o in if case .text(var t) = o.content { t.alignment = alignment; o.content = .text(t) } }
    }

    public func setVerticalAlignment(_ id: UUID, _ alignment: VerticalAlignment) {
        edit(id, key: "vertical") { o in if case .text(var t) = o.content { t.verticalAlignment = alignment; o.content = .text(t) } }
    }

    private func editStyle(_ id: UUID, key: String, _ change: @escaping (inout TextStyle) -> Void) {
        edit(id, key: key) { o in
            if case .text(var t) = o.content { change(&t.style); o.content = .text(t) }
        }
    }

    // MARK: Shapes and images

    /// Nil: no fill.
    public func setFill(_ id: UUID, _ color: ColorRGBA?) {
        editShape(id, key: "fill") { $0.fill = color }
    }

    public func setStrokeColor(_ id: UUID, _ color: ColorRGBA?) {
        editShape(id, key: "strokeColour") { $0.strokeColor = color }
    }

    public func setStrokeWidth(_ id: UUID, _ width: Double) {
        editShape(id, key: "strokeWidth") { $0.strokeWidth = width }
    }

    /// Fraction of the shorter side, 0...0.5. Only a rounded rectangle has one; for other shapes nothing changes.
    public func setCornerRadius(_ id: UUID, _ radius: Double) {
        editShape(id, key: "radius") { s in
            if case .roundedRectangle = s.shape { s.shape = .roundedRectangle(cornerRadius: radius) }
        }
    }

    public func setImageContentMode(_ id: UUID, _ mode: ImageContentMode) {
        edit(id, key: "imageMode") { o in if case .image(var i) = o.content { i.contentMode = mode; o.content = .image(i) } }
    }

    private func editShape(_ id: UUID, key: String, _ change: @escaping (inout ShapeObject) -> Void) {
        edit(id, key: key) { o in
            if case .shape(var s) = o.content { change(&s); o.content = .shape(s) }
        }
    }

    // MARK: Any object

    public func setOpacity(_ id: UUID, _ opacity: Double) {
        edit(id, key: "opacity") { $0.opacity = opacity }
    }

    /// Changes one object and keeps every value inside what the compositor can draw. An unknown id changes nothing.
    public func edit(_ id: UUID, key: String? = nil, _ change: @escaping (inout SlideObject) -> Void) {
        guard let slide, let i = slide.content.objects.firstIndex(where: { $0.id == id }) else { return }
        mutate(slide, key: key.map { "\($0):\(id)" }, selecting: nil) { objects in
            var o = objects[i]
            change(&o)
            o.id = id
            objects[i] = SlideEditing.sanitized(o)
        }
    }

    // MARK: Stacking order

    public func bringToFront(_ id: UUID) { restack(id) { $0.bringToFront(id) } }
    public func sendToBack(_ id: UUID) { restack(id) { $0.sendToBack(id) } }
    public func bringForward(_ id: UUID) { restack(id) { $0.moveForward(id) } }
    public func sendBackward(_ id: UUID) { restack(id) { $0.moveBackward(id) } }

    private func restack(_ id: UUID, _ change: (inout SlideContent) -> Void) {
        guard let slide, slide.content.objects.contains(where: { $0.id == id }) else { return }
        mutate(slide, key: nil, selecting: nil) { objects in
            var content = SlideContent(primary: "", objects: objects)
            change(&content)
            objects = content.objects
        }
    }

    // MARK: Duplicate and delete

    /// A copy a little to one side, directly above the original; the copy is selected. Returns its id.
    @discardableResult
    public func duplicate(_ id: UUID) -> UUID? {
        guard let slide, let i = slide.content.objects.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = slide.content.objects[i]
        copy.id = UUID()
        copy.move(dx: SlideEditing.duplicateOffset.dx, dy: SlideEditing.duplicateOffset.dy)
        if copy.frame == slide.content.objects[i].frame {       // against the far edge: go the other way
            copy.move(dx: -SlideEditing.duplicateOffset.dx, dy: -SlideEditing.duplicateOffset.dy)
        }
        let made = copy
        mutate(slide, key: nil, selecting: made.id) { $0.insert(made, at: i + 1) }
        return made.id
    }

    public func delete(_ id: UUID) {
        guard let slide, slide.content.objects.contains(where: { $0.id == id }) else { return }
        mutate(slide, key: nil, selecting: nil, clearSelection: selectedObjectID == id) { $0.removeAll { $0.id == id } }
    }

    /// Delete key: removes the selected object, if there is one. Returns whether it did.
    @discardableResult
    public func deleteSelected() -> Bool {
        guard let id = selectedObjectID else { return false }
        delete(id)
        return true
    }

    /// Command-D.
    @discardableResult
    public func duplicateSelected() -> UUID? {
        selectedObjectID.flatMap { duplicate($0) }
    }

    // MARK: Undo and redo

    private var history: History? { slide.flatMap { histories[$0.id] } }

    public func undo() {
        guard let slide, var h = histories[slide.id], let previous = h.undo.popLast() else { return }
        h.redo.append(Snapshot(objects: slide.content.objects, selected: selectedObjectID))
        h.lastKey = nil
        histories[slide.id] = h
        restore(previous, on: slide)
    }

    public func redo() {
        guard let slide, var h = histories[slide.id], let next = h.redo.popLast() else { return }
        h.undo.append(Snapshot(objects: slide.content.objects, selected: selectedObjectID))
        h.lastKey = nil
        histories[slide.id] = h
        restore(next, on: slide)
    }

    private func restore(_ snapshot: Snapshot, on slide: Slide) {
        var content = slide.content
        content.objects = snapshot.objects
        workspace.editSlide(id: slide.id, content: content)
        if let id = snapshot.selected, snapshot.objects.contains(where: { $0.id == id }) {
            selection = (slide.id, id)
        } else {
            selection = nil
        }
    }

    // MARK: Internals

    /// Applies `change` to a copy of the slide's objects; if anything differs, records one undo step (unless this
    /// continues a run of the same kind of edit, or a drag is open) and hands the new content to the workspace.
    private func mutate(_ slide: Slide, key: String?, selecting: UUID?, clearSelection: Bool = false,
                        _ change: (inout [SlideObject]) -> Void) {
        resetHistoryIfPresentationChanged()
        var objects = slide.content.objects
        change(&objects)
        guard objects != slide.content.objects else { return }
        let before = Snapshot(objects: slide.content.objects, selected: selectedObjectID)
        if interactionBase?.slideID == slide.id {
            // inside a drag: endInteraction records the single step
        } else if let key, histories[slide.id]?.lastKey == key, !(histories[slide.id]?.undo.isEmpty ?? true) {
            histories[slide.id]?.redo = []
        } else {
            record(before, forSlide: slide.id, key: key)
        }
        var content = slide.content
        content.objects = objects
        workspace.editSlide(id: slide.id, content: content)
        if let selecting {
            selection = (slide.id, selecting)
        } else if clearSelection {
            selection = nil
        }
    }

    private func record(_ snapshot: Snapshot, forSlide id: UUID, key: String?) {
        var h = histories[id] ?? History()
        h.undo.append(snapshot)
        if h.undo.count > SlideEditing.historyLimit { h.undo.removeFirst(h.undo.count - SlideEditing.historyLimit) }
        h.redo = []
        h.lastKey = key
        histories[id] = h
    }

    /// Slide ids belong to one presentation, so history from another one is dropped when it changes.
    private func resetHistoryIfPresentationChanged() {
        if historyPresentation != workspace.openPresentationID {
            histories = [:]
            interactionBase = nil
            historyPresentation = workspace.openPresentationID
        }
    }
}
