// SLIDE-003: song sections (slide groups), arrangements and the resolver. Foundation only.
import Foundation

/// A named section of a presentation, such as "Verse 1" or "Chorus". Slides point at it by `groupID`.
public struct SlideGroup: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let presentationID: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), presentationID: UUID, name: String, sortOrder: Int = 0) {
        self.id = id
        self.presentationID = presentationID
        self.name = name
        self.sortOrder = sortOrder
    }
}

/// A named play order over a presentation's groups. A group may appear any number of times.
public struct Arrangement: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public let presentationID: UUID
    public var name: String
    public var groupIDs: [UUID]

    public init(id: UUID = UUID(), presentationID: UUID, name: String, groupIDs: [UUID] = []) {
        self.id = id
        self.presentationID = presentationID
        self.name = name
        self.groupIDs = groupIDs
    }
}

public enum ArrangementResolver {
    /// SYS-015: the section name of each slide, in the order given, nil for a slide that is in no group or in one that is not listed.
    public static func sectionNames(for slides: [Slide], groups: [SlideGroup]) -> [String?] {
        let names = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return slides.map { slide in slide.groupID.flatMap { names[$0] } }
    }

    /// With no arrangement: all slides in natural (`sortOrder`) order. With one: the slides of each
    /// listed group in turn, so repeated groups repeat their slides. Slides outside any group and
    /// group ids not in `groups` are left out.
    public static func order(slides: [Slide], groups: [SlideGroup], arrangement: Arrangement?) -> [Slide] {
        let natural = slides.enumerated().sorted {
            ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset)
        }.map(\.element)
        guard let arrangement else { return natural }
        let known = Set(groups.map(\.id))
        var byGroup: [UUID: [Slide]] = [:]
        for slide in natural {
            if let group = slide.groupID { byGroup[group, default: []].append(slide) }
        }
        return arrangement.groupIDs.filter(known.contains).flatMap { byGroup[$0] ?? [] }
    }
}
