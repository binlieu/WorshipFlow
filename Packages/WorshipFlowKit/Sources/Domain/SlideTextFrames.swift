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
        self.init(primary: try c.decodeIfPresent(NormalizedRect.self, forKey: .primary),
                  secondary: try c.decodeIfPresent(NormalizedRect.self, forKey: .secondary))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(primary, forKey: .primary)
        try c.encodeIfPresent(secondary, forKey: .secondary)
    }
}
