// SLIDE-001b (PRES-01, MEDIA-07): rules for the slide editor that are not interface: what a new object looks like,
// and keeping every value inside what the compositor can draw. Foundation and Domain only.
import Foundation
import Domain

/// What the Insert menu can add.
public enum NewSlideObject: Sendable, Equatable {
    case textBox, rectangle, ellipse, roundedRectangle
    case image(path: String)

    public var title: String {
        switch self {
        case .textBox: "Text box"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .roundedRectangle: "Rounded rectangle"
        case .image: "Image"
        }
    }
}

public enum SlideEditing {
    /// UI-004: how far the pointer must move (in points) before a press on an object becomes a drag. A press that stays inside it is a click.
    public static let dragThreshold: Double = 3
    /// UI-004: the side, in points, of the area that grabs the resize handle. The drawn handle is smaller; the area is not.
    public static let handleHitSize: Double = 28

    /// FIX-K: a point of the slide as the operator thinks of it: the theme's 1920 x 1080 frame. A nudge is one point (ten with Shift).
    public static let referenceWidth = 1920.0
    public static let referenceHeight = 1080.0

    /// FIX-K: the frame a handle gives when dragged by (`dx`, `dy`) slide fractions from `start`. `px` and `py` say which handle: 0 is the left / top edge, 1 the right /
    /// bottom edge, 0.5 the middle (that axis does not change). The opposite edge stays where it is; the frame is never smaller than `SlideObject.minimumSize`.
    public static func resizedFrame(from s: NormalizedRect, handleX px: Double, handleY py: Double, dx: Double, dy: Double) -> NormalizedRect {
        let minimum = SlideObject.minimumSize
        var x = s.x, y = s.y, w = s.width, h = s.height
        if px == 0 { let right = s.x + s.width; x = min(s.x + dx, right - minimum); w = right - x }
        if px == 1 { w = max(s.width + dx, minimum) }
        if py == 0 { let bottom = s.y + s.height; y = min(s.y + dy, bottom - minimum); h = bottom - y }
        if py == 1 { h = max(s.height + dy, minimum) }
        return NormalizedRect(x: x, y: y, width: w, height: h)
    }

    public static func dragHasStarted(dx: Double, dy: Double) -> Bool { (dx * dx + dy * dy).squareRoot() >= dragThreshold }
    public static let fontSizeRange = ThemeEditing.fontSizeRange
    public static let outlineRange = ThemeEditing.outlineRange
    public static let strokeRange: ClosedRange<Double> = 0...40
    public static let shadowOffsetRange: ClosedRange<Double> = -100...100
    public static let shadowBlurRange: ClosedRange<Double> = 0...100
    /// How far a duplicate is moved from the original, as a fraction of the slide.
    public static let duplicateOffset = (dx: 0.02, dy: 0.035)
    /// Most undo steps kept for one slide.
    public static let historyLimit = 100

    public static let defaultShapeFill = ColorRGBA(red: 0.2, green: 0.5, blue: 0.95)
    public static let defaultCornerRadius = 0.2

    /// The size a new object starts with, as a fraction of the slide. Shapes start as squares on a 16:9 slide.
    static func defaultSize(of template: NewSlideObject) -> (width: Double, height: Double) {
        switch template {
        case .textBox: (0.5, 0.2)
        case .rectangle, .ellipse, .roundedRectangle: (0.2, 0.2 * 16 / 9)
        case .image: (0.4, 0.4 * 16 / 9)
        }
    }

    /// A new object of the given kind placed at `frame`.
    static func newObject(_ template: NewSlideObject, frame: NormalizedRect, id: UUID = UUID()) -> SlideObject {
        switch template {
        case .textBox:
            let style = TextStyle(fontName: ThemeEditing.defaultFontName, fontSize: 72, color: .white)
            return SlideObject(id: id, frame: frame, content: .text(TextObject(text: "Text", style: style)))
        case .rectangle:
            return SlideObject(id: id, frame: frame, content: .shape(ShapeObject(shape: .rectangle, fill: defaultShapeFill)))
        case .ellipse:
            return SlideObject(id: id, frame: frame, content: .shape(ShapeObject(shape: .ellipse, fill: defaultShapeFill)))
        case .roundedRectangle:
            return SlideObject(id: id, frame: frame,
                               content: .shape(ShapeObject(shape: .roundedRectangle(cornerRadius: defaultCornerRadius),
                                                           fill: defaultShapeFill)))
        case .image(let path):
            return SlideObject(id: id, frame: frame, content: .image(ImageObject(path: path, contentMode: .fit)))
        }
    }

    /// Every value inside what the compositor can draw. The id and the kind of object never change. Equal input stays equal.
    public static func sanitized(_ object: SlideObject) -> SlideObject {
        var o = object
        o.frame = clampedFrame(o.frame)
        switch o.content {
        case .text(var t):
            let name = t.style.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
            t.style.fontName = name.isEmpty ? ThemeEditing.defaultFontName : name
            t.style.fontSize = limit(t.style.fontSize, fontSizeRange, fallback: 72)
            t.style.outlineWidth = limit(t.style.outlineWidth, outlineRange, fallback: 0)
            if var shadow = t.style.shadow {
                shadow.offsetX = limit(shadow.offsetX, shadowOffsetRange, fallback: 0)
                shadow.offsetY = limit(shadow.offsetY, shadowOffsetRange, fallback: 0)
                shadow.blur = limit(shadow.blur, shadowBlurRange, fallback: 0)
                t.style.shadow = shadow
            }
            o.content = .text(t)
        case .shape(var s):
            s.strokeWidth = limit(s.strokeWidth, strokeRange, fallback: 0)
            if case .roundedRectangle(let radius) = s.shape {
                s.shape = .roundedRectangle(cornerRadius: limit(radius, 0...0.5, fallback: defaultCornerRadius))
            }
            o.content = .shape(s)
        case .image:
            break
        }
        return o
    }

    /// A frame on the slide, at least `SlideObject.minimumSize` wide and high. The size is kept first and the position
    /// moved inside it.
    static func clampedFrame(_ frame: NormalizedRect) -> NormalizedRect {
        let minimum = SlideObject.minimumSize
        let w = limit(frame.width, minimum...1, fallback: 0.2)
        let h = limit(frame.height, minimum...1, fallback: 0.2)
        return NormalizedRect(x: limit(frame.x, 0...(1 - w), fallback: 0), y: limit(frame.y, 0...(1 - h), fallback: 0),
                              width: w, height: h)
    }

    private static func limit(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}
