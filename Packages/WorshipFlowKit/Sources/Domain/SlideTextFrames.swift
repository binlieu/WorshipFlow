// FIX-K item 3 (SLIDE): a slide's own place for its words. The theme gives every slide the same frame for the first and the second language; the
// operator may move or resize one language's box on ONE slide in Edit, and that slide then carries its own frame, stored with the slide. A frame is a
// fraction of the output frame (the theme's own coordinate space), so it holds at every output resolution. Foundation only.
import Foundation

/// The two lyric boxes of a slide.
public enum LyricBox: String, Sendable, Codable, CaseIterable, Hashable {
    case primary, secondary

    public var title: String { self == .primary ? "First language" : "Second language" }
}

public struct SlideTextFrames: Sendable, Equatable, Codable, Hashable {
    /// Nil: the theme's frame for that language.
    public var primary: NormalizedRect?
    public var secondary: NormalizedRect?

    public init(primary: NormalizedRect? = nil, secondary: NormalizedRect? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    /// No frame of its own for either language: the same as having none.
    public var isEmpty: Bool { primary == nil && secondary == nil }

    public subscript(box: LyricBox) -> NormalizedRect? {
        get { box == .primary ? primary : secondary }
        set { if box == .primary { primary = newValue } else { secondary = newValue } }
    }

    private enum CodingKeys: String, CodingKey { case primary, secondary }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // FIX-N item 2: a stored frame is checked when it is read, so a bad one (a hand-edited file, a package from elsewhere) is no override.
        self.init(primary: Self.usable(try c.decodeIfPresent(NormalizedRect.self, forKey: .primary)),
                  secondary: Self.usable(try c.decodeIfPresent(NormalizedRect.self, forKey: .secondary)))
    }

    /// FIX-N item 2: the frame as it may be used, or nil for "the theme's own". A frame with a non-finite value, a size of zero or less, or one
    /// wholly outside the canvas is no override. Any other is clamped onto the slide the way the editor clamps what it writes.
    public static func usable(_ frame: NormalizedRect?) -> NormalizedRect? {
        guard let f = frame, f.x.isFinite, f.y.isFinite, f.width.isFinite, f.height.isFinite,
              f.width > 0, f.height > 0, f.x < 1, f.y < 1, f.x + f.width > 0, f.y + f.height > 0 else { return nil }
        return f.clampedToSlide()
    }

    /// The same frames with each one passed through `usable`.
    public var validated: SlideTextFrames { SlideTextFrames(primary: Self.usable(primary), secondary: Self.usable(secondary)) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(primary, forKey: .primary)
        try c.encodeIfPresent(secondary, forKey: .secondary)
    }
}

extension NormalizedRect {
    /// A frame on the slide, at least `SlideObject.minimumSize` wide and high. The size is kept first and the position moved inside it. The
    /// editor's clamp (`SlideEditing.clampedFrame`), shared so what is stored and what is read follow one rule.
    public func clampedToSlide() -> NormalizedRect {
        func limit(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
            guard value.isFinite else { return fallback }
            return min(range.upperBound, max(range.lowerBound, value))
        }
        let minimum = SlideObject.minimumSize
        let w = limit(width, minimum...1, fallback: 0.2)
        let h = limit(height, minimum...1, fallback: 0.2)
        return NormalizedRect(x: limit(x, 0...(1 - w), fallback: 0), y: limit(y, 0...(1 - h), fallback: 0), width: w, height: h)
    }
}
