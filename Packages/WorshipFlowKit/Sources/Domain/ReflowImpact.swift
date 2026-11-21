// R11: what re-flowing a song would do to its section orders. Foundation only.
import Foundation

/// One section order that a re-flow damages.
public struct SectionOrderLoss: Sendable, Equatable {
    public var arrangementName: String
    /// Names of the sections the order plays that the new text no longer has, each once, in the order's own order.
    public var lostSections: [String]
    /// True when no section of the order survives: playlist items that use it would play no slides at all.
    public var becomesEmpty: Bool
    /// Titles of the playlist items (in every playlist) that play this order.
    public var playlistItemTitles: [String]

    public init(arrangementName: String, lostSections: [String], becomesEmpty: Bool, playlistItemTitles: [String]) {
        self.arrangementName = arrangementName
        self.lostSections = lostSections
        self.becomesEmpty = becomesEmpty
        self.playlistItemTitles = playlistItemTitles
    }
}

public enum ReflowImpact {
    /// Re-flowing keeps a section by its exact name; a section whose name is not in the new text is deleted and drops out
    /// of every order. This lists the orders that lose at least one section they play. An order that was already
    /// empty is not listed: nothing is being lost.
    public static func sectionOrderLosses(groups: [SlideGroup], arrangements: [Arrangement], newSectionNames: [String],
                                          playlistTitlesByArrangement: [UUID: [String]]) -> [SectionOrderLoss] {
        let surviving = Set(newSectionNames)
        let nameByID = Dictionary(groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var result: [SectionOrderLoss] = []
        for order in arrangements {
            var lost: [String] = []
            var survivors = 0
            for id in order.groupIDs {
                guard let name = nameByID[id] else { continue }       // not a section of this song: it never played anything
                if surviving.contains(name) { survivors += 1 } else if !lost.contains(name) { lost.append(name) }
            }
            guard !lost.isEmpty else { continue }
            result.append(SectionOrderLoss(arrangementName: order.name, lostSections: lost, becomesEmpty: survivors == 0,
                                           playlistItemTitles: playlistTitlesByArrangement[order.id] ?? []))
        }
        return result
    }
}
