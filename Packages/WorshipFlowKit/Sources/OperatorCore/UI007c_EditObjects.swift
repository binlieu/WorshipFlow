// UI-007c (SLIDE): the editor's use of the v15 object fields: the Layers list (name, hide, lock, reorder, select), text Fit and Background fill,
// and the video object. Every edit is one undo step through `SlideEditorModel.edit`, goes through the one edit path (preview and save, never the
// live output), and a locked object refuses the frame and delete rules in `SlideEditorModel` itself, so the canvas, the keyboard and the inspector
// all say the same thing. Foundation and Domain only; the views are in the app target.
import Foundation
import Domain

/// One row of the Layers list: a value (cells carry it and never index the model's list, KI-193). Top first, like the design.
public struct EditLayerRow: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case text, shape, image, video, words }

    public var id: String
    /// The object this row stands for; nil for a row of the slide's own words.
    public var objectID: UUID?
    /// The lyric box a "words" row selects.
    public var lyricBox: LyricBox?
    public var kind: Kind
    public var title: String
    /// The operator's own name, when there is one (the row then shows it, and the field starts with it).
    public var customName: String?
    public var isHidden: Bool
    public var isLocked: Bool
    public var isSelected: Bool
    public var canMoveUp: Bool
    public var canMoveDown: Bool
}

extension SlideEditorModel {
    /// The slide's layers, top first: the slide's own words (drawn over the objects), then the objects from the front to the back.
    /// `mediaTitle` names a video object's clip (the model does not know the bin).
    public func layerRows(mediaTitle: (UUID) -> String? = { _ in nil }) -> [EditLayerRow] {
        var rows: [EditLayerRow] = []
        for box in [LyricBox.secondary, .primary] where lyricFrame(box) != nil {
            rows.append(EditLayerRow(id: "words.\(box.rawValue)", objectID: nil, lyricBox: box, kind: .words,
                                     title: "Words — \(box.title.lowercased())", customName: nil, isHidden: false, isLocked: false,
                                     isSelected: selectedLyricBox == box, canMoveUp: false, canMoveDown: false))
        }
        let all = objects
        let selected = selectedObjectID
        for (index, object) in all.enumerated().reversed() {
            rows.append(EditLayerRow(id: object.id.uuidString, objectID: object.id, lyricBox: nil, kind: Self.kind(of: object),
                                     title: Self.layerTitle(object, mediaTitle: mediaTitle), customName: object.name,
                                     isHidden: object.isHidden, isLocked: object.isLocked, isSelected: selected == object.id,
                                     canMoveUp: index < all.count - 1, canMoveDown: index > 0))
        }
        return rows
    }

    static func kind(of object: SlideObject) -> EditLayerRow.Kind {
        switch object.content {
        case .text: .text
        case .shape: .shape
        case .image: .image
        case .video: .video
        }
    }

    /// The name a row shows: the operator's, else what the object is ("Text: first words", "Rectangle", the picture's file, the clip's name).
    public static func layerTitle(_ object: SlideObject, mediaTitle: (UUID) -> String? = { _ in nil }) -> String {
        if let name = object.name { return name }
        switch object.content {
        case .text(let t):
            let line = t.text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return line.isEmpty ? "Text box" : "Text: " + (line.count > 28 ? String(line.prefix(28)) + "…" : line)
        case .shape(let s):
            switch s.shape {
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .roundedRectangle: return "Rounded rectangle"
            }
        case .image(let i):
            let file = URL(fileURLWithPath: i.path).lastPathComponent
            return file.isEmpty ? "Image" : "Image: \(file)"
        case .video(let v):
            return mediaTitle(v.mediaID).map { "Video: \($0)" } ?? "Video"
        }
    }

    // MARK: Name, hide, lock, order

    /// The operator's name for an object; blank gives it back its own title. One undo step.
    public func setName(_ id: UUID, _ name: String?) {
        edit(id) { $0.name = SlideObject.cleanName(name) }
    }

    /// A hidden object stays on the slide and in the list (struck through) and is not drawn on any screen. One undo step.
    public func setHidden(_ id: UUID, _ hidden: Bool) {
        edit(id) { $0.isHidden = hidden }
    }

    /// A locked object cannot be moved, resized, nudged, aligned or deleted until it is unlocked. One undo step.
    public func setLocked(_ id: UUID, _ locked: Bool) {
        edit(id) { $0.isLocked = locked }
    }

    /// Shows the reason a locked object stays where it is (a press that tried to drag it). Nothing is written.
    public func explainLocked(_ id: UUID) { _ = refusesBecauseLocked(id) }

    /// Moves a layer one step toward the front (`up`) or the back. Nothing happens at the end of the stack.
    public func moveLayer(_ id: UUID, up: Bool) {
        if up { bringForward(id) } else { sendBackward(id) }
    }

    // MARK: Text Fit and Background fill

    /// "Shrink to fit box": the words are drawn smaller until they fit inside the box (never below the lyric floor, `Theme.fitFloor`), and are
    /// clipped to the box when they still do not fit. One undo step.
    public func setFit(_ id: UUID, _ fit: TextFit) {
        edit(id) { o in if case .text(var t) = o.content { t.fit = fit; o.content = .text(t) } }
    }

    /// The colour behind the words, filling the whole box; nil is none. A run of colour choices is one undo step.
    public func setBackgroundFill(_ id: UUID, _ color: ColorRGBA?) {
        edit(id, key: "textFill") { o in if case .text(var t) = o.content { t.backgroundFill = color; o.content = .text(t) } }
    }

    // MARK: Video objects

    /// Places a clip from the bin on the selected slide as a video object (looped and muted), selects it, and returns its id.
    @discardableResult
    public func addVideo(mediaID: UUID) -> UUID? { add(.video(mediaID: mediaID)) }

    public func setVideoLoops(_ id: UUID, _ loops: Bool) {
        edit(id) { o in if case .video(var v) = o.content { v.loops = loops; o.content = .video(v) } }
    }

    public func setVideoMuted(_ id: UUID, _ muted: Bool) {
        edit(id) { o in if case .video(var v) = o.content { v.muted = muted; o.content = .video(v) } }
    }
}
