// OUT-001: bilingual slide content. SLIDE-001a: plus ordered objects. Foundation only.
import Foundation

public struct SlideContent: Sendable, Equatable, Codable, Hashable {
    public var primary: String
    public var secondary: String?
    /// Text boxes, shapes and images, back to front. Absent from content saved before objects existed.
    public var objects: [SlideObject]
    /// MEDIA-010: this slide's own background (a bin video or picture). Nil means the presentation's own. A live override
    /// from the media bin beats it while that is on.
    public var background: MediaSelection?
    /// FIX-K: this slide's own frame for the first and/or second language's words, in the theme's coordinate space. Nil (never an empty value) means
    /// the theme's frames, exactly as before this field existed. Used by the audience screen; the broadcast look and the stage keep their own.
    public var textFrames: SlideTextFrames?

    public init(primary: String, secondary: String? = nil, objects: [SlideObject] = [], background: MediaSelection? = nil,
                textFrames: SlideTextFrames? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.objects = objects
        self.background = background
        self.textFrames = (textFrames?.isEmpty ?? true) ? nil : textFrames
    }

    private enum CodingKeys: String, CodingKey { case primary, secondary, objects, background, textFrames }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(primary: try c.decode(String.self, forKey: .primary),
                  secondary: try c.decodeIfPresent(String.self, forKey: .secondary),
                  objects: try c.decodeIfPresent([SlideObject].self, forKey: .objects) ?? [],
                  background: try c.decodeIfPresent(MediaSelection.self, forKey: .background),
                  textFrames: try? c.decodeIfPresent(SlideTextFrames.self, forKey: .textFrames))
    }

    /// Slides without objects encode exactly as they did before objects existed.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(primary, forKey: .primary)
        try c.encodeIfPresent(secondary, forKey: .secondary)
        if !objects.isEmpty { try c.encode(objects, forKey: .objects) }
        try c.encodeIfPresent(background, forKey: .background)
        if let textFrames, !textFrames.isEmpty { try c.encode(textFrames, forKey: .textFrames) }
    }

    /// True when neither line has visible text and there are no objects.
    public var isBlank: Bool {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = (secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty && s.isEmpty && objects.isEmpty
    }

    // MARK: Stacking order (the array is back to front). An unknown id changes nothing.

    public mutating func bringToFront(_ id: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == id }), i != objects.count - 1 else { return }
        objects.append(objects.remove(at: i))
    }

    public mutating func sendToBack(_ id: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == id }), i != 0 else { return }
        objects.insert(objects.remove(at: i), at: 0)
    }

    /// One step towards the front.
    public mutating func moveForward(_ id: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == id }), i < objects.count - 1 else { return }
        objects.swapAt(i, i + 1)
    }

    /// One step towards the back.
    public mutating func moveBackward(_ id: UUID) {
        guard let i = objects.firstIndex(where: { $0.id == id }), i > 0 else { return }
        objects.swapAt(i, i - 1)
    }

    public mutating func removeObject(_ id: UUID) {
        objects.removeAll { $0.id == id }
    }
}
