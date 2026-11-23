// SLIDE-001a: objects on a slide (PRES-01, MEDIA-07): text boxes, shapes and images, back to front. Foundation only.
import Foundation

/// SYS-015: how a text box handles words that do not fit its frame. `none` draws them at the style's size as before.
public enum TextFit: String, Sendable, Equatable, Codable, Hashable, CaseIterable {
    case none
    case shrinkToFit
}

public struct TextObject: Sendable, Equatable, Codable, Hashable {
    public var text: String
    public var style: TextStyle
    public var alignment: TextAlignment
    public var verticalAlignment: VerticalAlignment
    /// SYS-015: stored only; drawing it is the feature slice's work. Absent in objects stored before: `.none`.
    public var fit: TextFit
    /// SYS-015: stored only. A colour behind the words inside the box; nil (and absent in objects stored before) is none.
    public var backgroundFill: ColorRGBA?

    public init(text: String, style: TextStyle, alignment: TextAlignment = .center,
                verticalAlignment: VerticalAlignment = .center, fit: TextFit = .none, backgroundFill: ColorRGBA? = nil) {
        self.text = text
        self.style = style
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.fit = fit
        self.backgroundFill = backgroundFill
    }

    private enum CodingKeys: String, CodingKey { case text, style, alignment, verticalAlignment, fit, backgroundFill }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(text: try c.decode(String.self, forKey: .text), style: try c.decode(TextStyle.self, forKey: .style),
                  alignment: try c.decode(TextAlignment.self, forKey: .alignment),
                  verticalAlignment: try c.decode(VerticalAlignment.self, forKey: .verticalAlignment),
                  fit: (try? c.decodeIfPresent(TextFit.self, forKey: .fit)) ?? .none,
                  backgroundFill: try? c.decodeIfPresent(ColorRGBA.self, forKey: .backgroundFill))
    }

    /// A value at its default writes no key, so an object that uses none of the new fields stores exactly what it stored before them.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(style, forKey: .style)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(verticalAlignment, forKey: .verticalAlignment)
        if fit != .none { try c.encode(fit, forKey: .fit) }
        try c.encodeIfPresent(backgroundFill, forKey: .backgroundFill)
    }
}

public struct ShapeObject: Sendable, Equatable, Codable, Hashable {
    public enum Shape: Sendable, Equatable, Codable, Hashable {
        case rectangle
        case ellipse
        /// `cornerRadius` is a fraction of the shorter side, 0...0.5.
        case roundedRectangle(cornerRadius: Double)
    }

    public var shape: Shape
    /// Nil: no fill.
    public var fill: ColorRGBA?
    /// Nil or a zero width: no stroke.
    public var strokeColor: ColorRGBA?
    /// Points at a 1080-line reference height, drawn inside the frame edge.
    public var strokeWidth: Double

    public init(shape: Shape, fill: ColorRGBA?, strokeColor: ColorRGBA? = nil, strokeWidth: Double = 0) {
        self.shape = shape
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth.isFinite ? max(0, strokeWidth) : 0
    }
}

public struct ImageObject: Sendable, Equatable, Codable, Hashable {
    public var path: String
    public var contentMode: ImageContentMode

    public init(path: String, contentMode: ImageContentMode = .fit) {
        self.path = path
        self.contentMode = contentMode
    }
}

/// SYS-015: a video that plays inside a slide object's frame. Stored only in this slice: the compositor draws nothing for it yet. `mediaID` is a bin item.
public struct VideoObject: Sendable, Equatable, Codable, Hashable {
    public var mediaID: UUID
    public var loops: Bool
    public var muted: Bool

    public init(mediaID: UUID, loops: Bool = true, muted: Bool = true) {
        self.mediaID = mediaID
        self.loops = loops
        self.muted = muted
    }

    private enum CodingKeys: String, CodingKey { case mediaID, loops, muted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mediaID: try c.decode(UUID.self, forKey: .mediaID), loops: try c.decodeIfPresent(Bool.self, forKey: .loops) ?? true,
                  muted: try c.decodeIfPresent(Bool.self, forKey: .muted) ?? true)
    }
}

public struct SlideObject: Sendable, Equatable, Codable, Hashable, Identifiable {
    public enum Content: Sendable, Equatable, Codable, Hashable {
        case text(TextObject)
        case shape(ShapeObject)
        case image(ImageObject)
        /// SYS-015. A build that does not know this case cannot read the object, so it must never open a library that holds one: the
        /// migration that introduced it (v15) makes every older build refuse that library (`LibraryFromNewerBuildError`). A later content case needs a migration for the same reason.
        case video(VideoObject)
    }

    /// SYS-015: the longest object name kept.
    public static let maxNameLength = 120

    /// Smallest width or height an object can be given, as a fraction of the slide.
    public static let minimumSize = 0.02

    public var id: UUID
    public var frame: NormalizedRect
    /// 0...1; values outside are clamped.
    public var opacity: Double {
        didSet { opacity = Self.clamp(opacity) }
    }
    public var content: Content
    /// SYS-015: the operator's name for the object (an object list, a Section later). Trimmed, at most `maxNameLength` characters; blank is nil.
    public var name: String? {
        didSet { name = Self.cleanName(name) }
    }
    /// SYS-015: a hidden object stays on the slide and in the editor and is not drawn on any screen.
    public var isHidden: Bool
    /// SYS-015: stored only; the editor honouring it (no move, no edit) is the feature slice's work. A locked object is still drawn.
    public var isLocked: Bool

    public init(id: UUID = UUID(), frame: NormalizedRect, opacity: Double = 1, name: String? = nil, isHidden: Bool = false,
                isLocked: Bool = false, content: Content) {
        self.id = id
        self.frame = frame
        self.opacity = Self.clamp(opacity)
        self.name = Self.cleanName(name)
        self.isHidden = isHidden
        self.isLocked = isLocked
        self.content = content
    }

    /// Trimmed, bounded, and nil when nothing is left.
    public static func cleanName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxNameLength))
    }

    private static func clamp(_ v: Double) -> Double { v.isNaN ? 1 : min(1, max(0, v)) }

    private enum CodingKeys: String, CodingKey { case id, frame, opacity, content, name, isHidden, isLocked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(UUID.self, forKey: .id), frame: try c.decode(NormalizedRect.self, forKey: .frame),
                  opacity: try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1,
                  name: try c.decodeIfPresent(String.self, forKey: .name),
                  isHidden: try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false,
                  isLocked: try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false,
                  content: try c.decode(Content.self, forKey: .content))
    }

    /// A value at its default writes no key, so an object that uses none of the new fields stores exactly what it stored before them.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(frame, forKey: .frame)
        try c.encode(opacity, forKey: .opacity)
        try c.encode(content, forKey: .content)
        try c.encodeIfPresent(name, forKey: .name)
        if isHidden { try c.encode(true, forKey: .isHidden) }
        if isLocked { try c.encode(true, forKey: .isLocked) }
    }

    /// Moves the frame, keeping it on the slide.
    public mutating func move(dx: Double, dy: Double) {
        let nx = frame.x + (dx.isFinite ? dx : 0), ny = frame.y + (dy.isFinite ? dy : 0)
        frame.x = max(0, min(1 - frame.width, nx))
        frame.y = max(0, min(1 - frame.height, ny))
    }

    /// Sets the size, keeping the top-left corner where it is when it can and the frame on the slide.
    /// Never smaller than `minimumSize`; if that no longer fits to the right or below, the frame slides back.
    public mutating func resize(width: Double, height: Double) {
        let minimum = Self.minimumSize
        var w = width.isNaN ? minimum : min(width, 1 - frame.x)
        var h = height.isNaN ? minimum : min(height, 1 - frame.y)
        if w < minimum { w = minimum; frame.x = 1 - minimum }
        if h < minimum { h = minimum; frame.y = 1 - minimum }
        frame.width = w
        frame.height = h
    }
}

// MARK: Scene layers

/// A shape ready to draw. Stroke width is in points at a 1080-line reference height.
public struct ShapeLayer: Sendable, Equatable, Codable, Hashable {
    public var shape: ShapeObject.Shape
    public var fill: ColorRGBA?
    public var strokeColor: ColorRGBA?
    public var strokeWidth: Double
    public var frame: NormalizedRect
    public var opacity: Double

    public init(shape: ShapeObject.Shape, fill: ColorRGBA?, strokeColor: ColorRGBA? = nil, strokeWidth: Double = 0,
                frame: NormalizedRect, opacity: Double = 1) {
        self.shape = shape
        self.fill = fill
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth.isFinite ? max(0, strokeWidth) : 0
        self.frame = frame
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
    }
}

/// UI-007c: a clip playing inside its frame on a slide. The output looks the clip's current frame up by `mediaID` (the media bin's id) and draws it
/// filling the frame (cropped to it), clipped to the frame, at `opacity`. Nothing is drawn until a frame has arrived.
public struct VideoLayer: Sendable, Equatable, Codable, Hashable {
    public var mediaID: UUID
    public var frame: NormalizedRect
    public var opacity: Double
    public var loops: Bool
    public var muted: Bool

    public init(mediaID: UUID, frame: NormalizedRect, opacity: Double = 1, loops: Bool = true, muted: Bool = true) {
        self.mediaID = mediaID
        self.frame = frame
        self.opacity = opacity.isNaN ? 1 : min(1, max(0, opacity))
        self.loops = loops
        self.muted = muted
    }
}

/// One drawable slide object. A scene lists them back to front.
public enum SceneObjectLayer: Sendable, Equatable, Codable, Hashable {
    case shape(ShapeLayer)
    case text(TextLayer)
    case image(ImageLayer)
    /// UI-007c.
    case video(VideoLayer)
}

extension SlideObject {
    /// The drawable form of this object.
    public var sceneLayer: SceneObjectLayer {
        switch content {
        case .shape(let s):
            return .shape(ShapeLayer(shape: s.shape, fill: s.fill, strokeColor: s.strokeColor, strokeWidth: s.strokeWidth,
                                     frame: frame, opacity: opacity))
        case .text(let t):
            // UI-007c: a text box with "Shrink to fit box" carries the lyric floor, so the compositor shrinks it (alone, by its own factor) until it fits.
            return .text(TextLayer(text: t.text, style: t.style, frame: frame, alignment: t.alignment,
                                   verticalAlignment: t.verticalAlignment, opacity: opacity,
                                   fitFloor: t.fit == .shrinkToFit ? Theme.fitFloor : nil))
        case .image(let i):
            return .image(ImageLayer(path: i.path, frame: frame, opacity: opacity, contentMode: i.contentMode))
        case .video(let v):
            return .video(VideoLayer(mediaID: v.mediaID, frame: frame, opacity: opacity, loops: v.loops, muted: v.muted))
        }
    }

    /// SYS-015: what the compositor draws for this object: nothing for a hidden object.
    public var drawableLayer: SceneObjectLayer? {
        if isHidden { return nil }
        return sceneLayer
    }

    /// UI-007c: every layer this object draws, back to front: nothing for a hidden object; a text box with a Background fill is that fill (a plain
    /// rectangle in the box's frame and opacity) and then its words. An object that uses no new value is its one `sceneLayer`, as before.
    public var drawableLayers: [SceneObjectLayer] {
        guard !isHidden else { return [] }
        if case .text(let t) = content, let fill = t.backgroundFill {
            return [.shape(ShapeLayer(shape: .rectangle, fill: fill, frame: frame, opacity: opacity)), sceneLayer]
        }
        return [sceneLayer]
    }
}

extension SceneDescription {
    /// The video objects this scene asks its output to play.
    public var videoObjectLayers: [VideoLayer] {
        objectLayers.compactMap { if case .video(let v) = $0 { v } else { nil } }
    }

    /// UI-007c: the same scene with each video object drawn as a still picture (`poster` gives the file for a clip, nil for none: the video then draws
    /// nothing). For the editor and the thumbnails, which show a still frame and never play.
    public func replacingVideoObjects(poster: (UUID) -> String?) -> SceneDescription {
        guard objectLayers.contains(where: { if case .video = $0 { true } else { false } }) else { return self }
        var scene = self
        scene.objectLayers = objectLayers.compactMap { layer in
            guard case .video(let v) = layer else { return layer }
            return poster(v.mediaID).map { .image(ImageLayer(path: $0, frame: v.frame, opacity: v.opacity, contentMode: .fill)) }
        }
        return scene
    }
}
