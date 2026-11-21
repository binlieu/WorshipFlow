// OUT-001: bilingual slide content. Foundation only.
import Foundation

public struct SlideContent: Sendable, Equatable, Codable, Hashable {
    public var primary: String
    public var secondary: String?

    public init(primary: String, secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    /// True when neither line has visible text.
    public var isBlank: Bool {
        let p = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = (secondary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return p.isEmpty && s.isEmpty
    }
}
