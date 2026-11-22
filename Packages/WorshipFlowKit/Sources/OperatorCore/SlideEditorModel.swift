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
        /// MEDIA-010: the slide's own background at that moment, so one undo covers it too.
        var background: MediaSelection?
        /// FIX-K: the slide's own text frames at that moment.
        var textFrames: SlideTextFrames?
        /// FIX-N item 7: steps that belong to one action on several slides ("Apply to all slides") share a group; one undo restores them all.
        var group: UUID?
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
    /// FIX-N item 6: true while `endInteraction` writes, so its own writes do not close the interaction they belong to.
    @ObservationIgnored private var closingInteraction = false
    /// FIX-N item 6: counts the interactions that ended; the canvas's boxes reset their pressed state when it changes (a drag that SwiftUI cancelled
    /// never called their `onEnded`).
    public private(set) var interactionEpoch = 0
    /// FIX-N item 8: a run of nudges ends after this long without one (an injected clock, so a test needs no wait).
    @ObservationIgnored public var nudgeQuietPeriod: TimeInterval = 1.0
    @ObservationIgnored public var nudgeClock: () -> Date = { Date() }
    @ObservationIgnored private var lastNudgeAt: Date?
    /// FIX-N item 8: the theme frames of the selected slide's lyric boxes, composed once per content and theme revision, not on every read.
    @ObservationIgnored private var lyricCache: (key: LyricCacheKey, frames: [LyricBox: NormalizedRect])?
    private struct LyricCacheKey: Equatable { var slideID: UUID; var primary: String; var secondary: String?; var revision: Int }
    /// FIX-N item 8: changes when the theme or the screens change, so the cached theme frames are composed again. The app supplies it.
    @ObservationIgnored public var lyricThemeRevision: @MainActor () -> Int = { 0 }
    #if DEBUG
    /// FIX-N item 8 (debug only, compiled out of release): how many times the theme frames were composed, for the cache test.
    @ObservationIgnored public private(set) var debugLyricComposeCount = 0
    #endif

    /// UI-004: where a dragged or resized object is while the pointer is down. Nothing else is touched until the pointer is released:
    /// not the presentation, the preview, the live output or the save queue. `objects` and `selectedObject` show these frames, so
    /// the canvas and the inspector follow the pointer; `endInteraction()` writes them once.
    public private(set) var dragFrames: [UUID: NormalizedRect] = [:]
    /// FIX-K: the same for a lyric box being dragged or resized. `lyricBoxes` shows these; `endInteraction()` writes them once, to the slide's own text frames.
    public private(set) var lyricDragFrames: [LyricBox: NormalizedRect] = [:]

    /// Selection is remembered with its slide, so choosing another slide shows no selection.
    private var selection: (slideID: UUID, objectID: UUID)?
    /// FIX-K: a lyric box is selected instead of an object (never both).
    private var lyricSelection: (slideID: UUID, box: LyricBox)?
    /// Set when something could not be done (for example no image was chosen); a message a volunteer can act on.
    public private(set) var lastMessage: String?

    /// Frames the slide's own words take on screen (from the theme), which new objects keep clear of where there is room.
    /// The app supplies them, because the theme is not known here.
    @ObservationIgnored public var reservedFrames: @MainActor (SlideContent) -> [NormalizedRect] = { _ in [] }

    /// FIX-K: the theme's frame of each lyric box that exists for this slide (a language with no words, and a plated theme, have none). The app supplies it,
    /// because the theme is not known here.
    @ObservationIgnored public var lyricThemeFrames: @MainActor (SlideContent) -> [LyricBox: NormalizedRect] = { _ in [:] }

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
    public var objects: [SlideObject] {
        let stored = slide?.content.objects ?? []
        guard !dragFrames.isEmpty else { return stored }
        return stored.map { object in
            guard let frame = dragFrames[object.id] else { return object }
            var o = object
            o.frame = frame
            return o
        }
    }

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
        endInteraction()                      // FIX-N item 6: a stray open drag is over by the time something is selected
        histories[slide?.id ?? UUID()]?.lastKey = nil      // FIX-N item 8: a new selection ends a run of nudges
        guard let slide else { return }
        lyricSelection = nil
        if let id, slide.content.objects.contains(where: { $0.id == id }) {
            selection = (slide.id, id)
        } else {
            selection = nil
        }
    }

    // MARK: Lyric boxes (FIX-K)

    /// The lyric boxes of the selected slide and where they are now: the slide's own frame, else the theme's; a box being dragged shows the pointer's.
    public var lyricBoxes: [LyricBox: NormalizedRect] {
        guard let slide else { return [:] }
        var boxes: [LyricBox: NormalizedRect] = [:]
        for (box, themeFrame) in cachedLyricThemeFrames(for: slide) {
            boxes[box] = lyricDragFrames[box] ?? slide.content.textFrames?[box] ?? themeFrame
        }
        return boxes
    }

    /// FIX-N item 8: the theme's frames for the slide's words, from the cache while its text and the theme revision are unchanged.
    private func cachedLyricThemeFrames(for slide: Slide) -> [LyricBox: NormalizedRect] {
        let key = LyricCacheKey(slideID: slide.id, primary: slide.content.primary, secondary: slide.content.secondary, revision: lyricThemeRevision())
        if let cache = lyricCache, cache.key == key { return cache.frames }
        let frames = lyricThemeFrames(slide.content)
        lyricCache = (key, frames)
        #if DEBUG
        debugLyricComposeCount += 1
        #endif
        return frames
    }

    public func lyricFrame(_ box: LyricBox) -> NormalizedRect? { lyricBoxes[box] }

    /// True when the selected slide has its own frame for this language (the inspector offers "Reset to theme position").
    public func hasOwnFrame(_ box: LyricBox) -> Bool { slide?.content.textFrames?[box] != nil }

    public var selectedLyricBox: LyricBox? {
        guard let slide, let lyricSelection, lyricSelection.slideID == slide.id, lyricBoxes[lyricSelection.box] != nil else { return nil }
        return lyricSelection.box
    }

    /// Selects a lyric box (and deselects any object). A language with no words has no box: nothing is selected.
    public func selectLyric(_ box: LyricBox?) {
        endInteraction()
        histories[slide?.id ?? UUID()]?.lastKey = nil
        selection = nil
        guard let slide, let box, cachedLyricThemeFrames(for: slide)[box] != nil else { lyricSelection = nil; return }
        lyricSelection = (slide.id, box)
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
        resetHistoryIfPresentationChanged()         // FIX-K: a drag may be the first edit of this presentation: it must not clear itself
        guard let slide else { return }
        dragFrames = [:]
        lyricDragFrames = [:]
        interactionBase = (slide.id, snapshot(of: slide))
    }

    public func endInteraction() {
        guard let base = interactionBase else { return }
        closingInteraction = true
        interactionEpoch &+= 1
        defer { closingInteraction = false }
        // UI-004: the one write of the drag. It goes through `mutate` while the interaction is still open, so it records no step of its
        // own; the step is recorded below, from the snapshot taken when the pointer went down.
        let dragged = dragFrames
        let draggedLyric = lyricDragFrames
        dragFrames = [:]
        lyricDragFrames = [:]
        if !draggedLyric.isEmpty, let target = workspace.slides.first(where: { $0.id == base.slideID }) {
            var frames = target.content.textFrames ?? SlideTextFrames()
            for (box, frame) in draggedLyric { frames[box] = SlideEditing.clampedFrame(frame) }
            writeTextFrames(target, frames, key: nil)
        }
        if !dragged.isEmpty, let target = workspace.slides.first(where: { $0.id == base.slideID }) {
            mutate(target, key: nil, selecting: nil) { objects in
                for i in objects.indices {
                    guard let frame = dragged[objects[i].id] else { continue }
                    var o = objects[i]
                    o.frame = frame
                    objects[i] = SlideEditing.sanitized(o)
                }
            }
        }
        interactionBase = nil
        guard let current = workspace.slides.first(where: { $0.id == base.slideID }),
              current.content.objects != base.snapshot.objects || current.content.textFrames != base.snapshot.textFrames else { return }
        record(base.snapshot, forSlide: base.slideID, key: nil)
    }

    /// Puts the object where `start` was, moved by (`dx`, `dy`) slide fractions, kept on the slide. Measuring from the
    /// start frame lets a drag go back to exactly where it began.
    public func move(_ id: UUID, from start: NormalizedRect, dx: Double, dy: Double) {
        editFrame(id) { o in
            o.frame = start
            o.move(dx: dx, dy: dy)
        }
    }

    /// Resizes from the corner that does not move: the size is `start`'s plus the given change.
    public func resize(_ id: UUID, from start: NormalizedRect, dWidth: Double, dHeight: Double) {
        editFrame(id) { o in
            o.frame = start
            o.resize(width: start.width + dWidth, height: start.height + dHeight)
        }
    }

    /// FIX-K: moves a lyric box from `start` by (`dx`, `dy`) slide fractions, kept on the slide. Inside an open interaction it only moves the transient frame
    /// (see `lyricDragFrames`); outside one (the keyboard, a test) it is written at once, as an object's is.
    public func moveLyric(_ box: LyricBox, from start: NormalizedRect, dx: Double, dy: Double) {
        var o = SlideEditing.newObject(.rectangle, frame: start)
        o.move(dx: dx, dy: dy)
        editLyricFrame(box, o.frame)
    }

    /// FIX-K: resizes a lyric box from the corner that does not move.
    public func resizeLyric(_ box: LyricBox, from start: NormalizedRect, dWidth: Double, dHeight: Double) {
        var o = SlideEditing.newObject(.rectangle, frame: start)
        o.resize(width: start.width + dWidth, height: start.height + dHeight)
        editLyricFrame(box, o.frame)
    }

    /// FIX-K: a handle drag of an object: the whole new frame at once (opposite edge fixed, see `SlideEditing.resizedFrame`). Inside an open interaction it only moves
    /// the transient frame, like `move` and `resize`.
    public func dragFrame(_ id: UUID, to frame: NormalizedRect) {
        editFrame(id) { $0.frame = frame }
    }

    /// FIX-K: the same for a lyric box.
    public func dragLyricFrame(_ box: LyricBox, to frame: NormalizedRect) {
        editLyricFrame(box, frame)
    }

    private func editLyricFrame(_ box: LyricBox, _ new: NormalizedRect, typed: Bool = false) {
        resetHistoryIfPresentationChanged()
        if typed { endInteraction() }         // FIX-N item 6: a typed position always writes, whatever drag was left open
        guard let slide, let themeFrame = cachedLyricThemeFrames(for: slide)[box] else { return }
        let target = SlideEditing.clampedFrame(new)
        let stored = slide.content.textFrames?[box] ?? themeFrame
        if interactionBase?.slideID == slide.id {
            if target == stored { lyricDragFrames[box] = nil } else { lyricDragFrames[box] = target }
            return
        }
        guard target != stored else { return }          // the same place: nothing to write (and no frame of its own made)
        var frames = slide.content.textFrames ?? SlideTextFrames()
        frames[box] = target
        writeTextFrames(slide, frames, key: "lyric:\(box.rawValue):\(slide.id)")
    }

    /// Sets a lyric box's frame from typed values (fractions of the slide), kept on the slide.
    public func setLyricFrame(_ box: LyricBox, x: Double, y: Double, width: Double, height: Double) {
        editLyricFrame(box, NormalizedRect(x: x, y: y, width: width, height: height), typed: true)
    }

    /// "Reset to theme position": this slide's frame for one language is dropped. One undo step.
    public func resetLyricFrame(_ box: LyricBox) {
        resetHistoryIfPresentationChanged()
        guard let slide, var frames = slide.content.textFrames, frames[box] != nil else { return }
        frames[box] = nil
        writeTextFrames(slide, frames.isEmpty ? nil : frames, key: nil)
    }

    /// "Apply to all slides in this song": every slide of the open presentation takes the selected slide's frame for this language (the theme's, when the
    /// slide has none of its own, which resets them all). Each slide records its own undo step.
    public func applyLyricFrameToAllSlides(_ box: LyricBox) {
        resetHistoryIfPresentationChanged()
        guard let source = slide else { return }
        let frame = source.content.textFrames?[box]
        let group = UUID()            // FIX-N item 7: one undo step for every slide the action changed
        for target in lyricApplyTargets(box, frame: frame, source: source.id) {
            var frames = target.content.textFrames ?? SlideTextFrames()
            frames[box] = frame
            writeTextFrames(target, frames.isEmpty ? nil : frames, key: nil, group: group)
        }
    }

    /// FIX-N item 7: how many slides "Apply to all slides in this song" would change: those other than the selected one that have words in this language
    /// and do not already hold that position. The app asks "Apply this position to N slides?" with this number before it applies.
    public func lyricApplyCount(_ box: LyricBox) -> Int {
        guard let source = slide else { return 0 }
        return lyricApplyTargets(box, frame: source.content.textFrames?[box], source: source.id).count
    }

    private func lyricApplyTargets(_ box: LyricBox, frame: NormalizedRect?, source: UUID) -> [Slide] {
        workspace.slides.filter { target in
            guard target.id != source else { return false }
            let words = box == .primary ? target.content.primary : (target.content.secondary ?? "")
            guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }      // a slide with no words in that language is skipped
            return target.content.textFrames?[box] != frame
        }
    }

    // MARK: Nudging (FIX-K)

    /// An arrow key on the canvas: moves the selected object, or the selected lyric box, by one point of the 1920 x 1080 slide per press (ten with Shift).
    /// A run of nudges is one undo step. Returns false when nothing is selected, so the key can do its usual job (moving the slide selection).
    @discardableResult
    public func nudgeSelection(columns: Int, rows: Int, big: Bool) -> Bool {
        let step = big ? 10.0 : 1.0
        let dx = Double(columns) * step / SlideEditing.referenceWidth, dy = Double(rows) * step / SlideEditing.referenceHeight
        // FIX-N item 8: a run of nudges is one undo step only while the arrows keep coming; after a quiet period the next nudge is a new step.
        let now = nudgeClock()
        if let last = lastNudgeAt, now.timeIntervalSince(last) >= nudgeQuietPeriod, let id = slide?.id { histories[id]?.lastKey = nil }
        lastNudgeAt = now
        if let id = selectedObjectID {
            edit(id, key: "nudge") { $0.move(dx: dx, dy: dy) }
            return true
        }
        if let box = selectedLyricBox, let current = lyricBoxes[box], let slide {
            var o = SlideEditing.newObject(.rectangle, frame: current)
            o.move(dx: dx, dy: dy)
            let target = SlideEditing.clampedFrame(o.frame)
            if target != current {
                var frames = slide.content.textFrames ?? SlideTextFrames()
                frames[box] = target
                writeTextFrames(slide, frames, key: "nudge:\(box.rawValue):\(slide.id)")
            }
            return true
        }
        return false
    }

    /// A frame change from a drag. Inside an open interaction it only moves the transient frame (see `dragFrames`); outside one
    /// (the keyboard, a test) it is written at once, as before.
    private func editFrame(_ id: UUID, _ change: @escaping (inout SlideObject) -> Void) {
        resetHistoryIfPresentationChanged()
        guard let slide, interactionBase?.slideID == slide.id,
              let stored = slide.content.objects.first(where: { $0.id == id }) else {
            edit(id, key: "frame", change)
            return
        }
        var o = stored
        change(&o)
        o.id = id
        o = SlideEditing.sanitized(o)
        if o.frame == stored.frame { dragFrames[id] = nil } else { dragFrames[id] = o.frame }
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

    // MARK: The slide's own background (MEDIA-010)

    /// Sets (or, with nil, removes) one slide's own background. An edit to the presentation: it shows in the open presentation
    /// at once, is saved by the same debounced path as typed text, and can be undone while that slide is selected. It never
    /// reaches the live output until the slide goes live again. Returns false when the slide is not in the open presentation.
    @discardableResult
    public func setBackground(_ selection: MediaSelection?, forSlide slideID: UUID) -> Bool {
        guard let slide = workspace.slides.first(where: { $0.id == slideID }) else { return false }
        resetHistoryIfPresentationChanged()
        guard slide.content.background != selection else { return true }
        let selected = self.slide?.id == slideID ? selectedObjectID : nil
        var before = snapshot(of: slide)
        before.selected = selected
        record(before, forSlide: slideID, key: nil)
        var content = slide.content
        content.background = selection
        workspace.editSlide(id: slideID, content: content)
        return true
    }

    /// FIX-I item 6: the thumbnail's context menu ("Set background…", "Clear this slide's background"). Undo works on the selected slide, so the
    /// slide is selected first (Preview only: nothing goes live); then it is one undo step on that slide.
    @discardableResult
    public func setBackgroundFromMenu(_ selection: MediaSelection?, forSlide slideID: UUID) -> Bool {
        guard let index = workspace.slides.firstIndex(where: { $0.id == slideID }) else { return false }
        workspace.selectSlide(index)
        return setBackground(selection, forSlide: slideID)
    }

    // MARK: Undo and redo

    private var history: History? { slide.flatMap { histories[$0.id] } }

    public func undo() {
        guard let slide, var h = histories[slide.id], let previous = h.undo.popLast() else { return }
        var now = snapshot(of: slide)
        now.group = previous.group
        h.redo.append(now)
        h.lastKey = nil
        histories[slide.id] = h
        restore(previous, on: slide)
        // FIX-N item 7: the other slides of a grouped action ("Apply to all slides") go back with it, in the same step.
        if let group = previous.group { stepGroup(group, undoing: true, except: slide.id) }
    }

    public func redo() {
        guard let slide, var h = histories[slide.id], let next = h.redo.popLast() else { return }
        var now = snapshot(of: slide)
        now.group = next.group
        h.undo.append(now)
        h.lastKey = nil
        histories[slide.id] = h
        restore(next, on: slide)
        if let group = next.group { stepGroup(group, undoing: false, except: slide.id) }
    }

    /// Undoes (or redoes) the step of `group` that sits on top of every other slide's history.
    private func stepGroup(_ group: UUID, undoing: Bool, except skip: UUID) {
        for other in workspace.slides where other.id != skip {
            guard var h = histories[other.id] else { continue }
            if undoing {
                guard h.undo.last?.group == group, let previous = h.undo.popLast() else { continue }
                var now = snapshot(of: other); now.group = group
                h.redo.append(now)
                h.lastKey = nil
                histories[other.id] = h
                restoreContent(previous, on: other)
            } else {
                guard h.redo.last?.group == group, let next = h.redo.popLast() else { continue }
                var now = snapshot(of: other); now.group = group
                h.undo.append(now)
                h.lastKey = nil
                histories[other.id] = h
                restoreContent(next, on: other)
            }
        }
    }

    /// Puts a snapshot's objects, background and frames back on a slide that is not the selected one (no selection change).
    private func restoreContent(_ snapshot: Snapshot, on slide: Slide) {
        var content = slide.content
        content.objects = snapshot.objects
        content.background = snapshot.background
        content.textFrames = snapshot.textFrames
        workspace.editSlide(id: slide.id, content: content)
    }

    private func restore(_ snapshot: Snapshot, on slide: Slide) {
        var content = slide.content
        content.objects = snapshot.objects
        content.background = snapshot.background
        content.textFrames = snapshot.textFrames
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
    private func mutate(_ given: Slide, key: String?, selecting: UUID?, clearSelection: Bool = false,
                        _ change: (inout [SlideObject]) -> Void) {
        resetHistoryIfPresentationChanged()
        var slide = given
        if !closingInteraction, interactionBase != nil {      // FIX-N item 6: a write that is not the drag's own ends a stray drag first
            endInteraction()
            slide = workspace.slides.first { $0.id == given.id } ?? given
        }
        var objects = slide.content.objects
        change(&objects)
        guard objects != slide.content.objects else { return }
        let before = snapshot(of: slide)
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
            lyricSelection = nil
        } else if clearSelection {
            selection = nil
        }
    }

    /// The slide as an undo step keeps it: its objects, background and text frames, with the object selected now.
    private func snapshot(of slide: Slide) -> Snapshot {
        Snapshot(objects: slide.content.objects, selected: selectedObjectID, background: slide.content.background, textFrames: slide.content.textFrames)
    }

    /// FIX-K: writes the slide's own text frames through the one edit path. Records one undo step, unless this continues a run of the same kind of edit
    /// or a drag is open (`endInteraction` records that step). Nothing is written when the frames are unchanged.
    private func writeTextFrames(_ given: Slide, _ frames: SlideTextFrames?, key: String?, group: UUID? = nil) {
        var slide = given
        if !closingInteraction, interactionBase != nil {
            endInteraction()
            slide = workspace.slides.first { $0.id == given.id } ?? given
        }
        let new = (frames?.isEmpty ?? true) ? nil : frames
        guard new != slide.content.textFrames else { return }
        var before = snapshot(of: slide)
        before.group = group
        if interactionBase?.slideID == slide.id {
            // inside a drag: endInteraction records the single step
        } else if let key, histories[slide.id]?.lastKey == key, !(histories[slide.id]?.undo.isEmpty ?? true) {
            histories[slide.id]?.redo = []
        } else {
            record(before, forSlide: slide.id, key: key)
        }
        var content = slide.content
        content.textFrames = new
        workspace.editSlide(id: slide.id, content: content)
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
            dragFrames = [:]
            lyricDragFrames = [:]
            lyricSelection = nil
            historyPresentation = workspace.openPresentationID
        }
    }
}
