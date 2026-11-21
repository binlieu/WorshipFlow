// OUT-001: bilingual slide content. SLIDE-001a: plus ordered objects. Foundation only.
import Foundation

public struct SlideContent: Sendable, Equatable, Codable, Hashable {
    public var primary: String
    public var secondary: String?
    /// Text boxes, shapes and images, back to front. Absent from content saved before objects existed.
    public var objects: [SlideObject]

    public init(primary: String, secondary: String? = nil, objects: [SlideObject] = []) {
        self.primary = primary
        self.secondary = secondary
        self.objects = objects
    }

    private enum CodingKeys: String, CodingKey { case primary, secondary, objects }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(primary: try c.decode(String.self, forKey: .primary),
                  secondary: try c.decodeIfPresent(String.self, forKey: .secondary),
                  objects: try c.decodeIfPresent([SlideObject].self, forKey: .objects) ?? [])
    }

    /// Slides without objects encode exactly as they did before objects existed.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(primary, forKey: .primary)
        try c.encodeIfPresent(secondary, forKey: .secondary)
        if !objects.isEmpty { try c.encode(objects, forKey: .objects) }
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
