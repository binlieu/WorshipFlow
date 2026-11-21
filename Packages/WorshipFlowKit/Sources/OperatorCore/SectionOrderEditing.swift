// APP-001 / KI-023 / SLIDE-003: pure edits of a section order (arrangement), a list of group ids in which a group
// may repeat. The editor's palette, remove and drag-reorder all go through these. Foundation and Domain only.
import Foundation
import Domain

public enum SectionOrderEditing {
    public static func appending(_ groupID: UUID, to order: [UUID]) -> [UUID] { order + [groupID] }

    /// Out-of-range indices change nothing.
    public static func removing(at index: Int, from order: [UUID]) -> [UUID] {
        guard order.indices.contains(index) else { return order }
        var order = order
        order.remove(at: index)
        return order
    }

    /// Moves the entry at `from` so that it ends at index `to` (the same meaning as `moveSlide`). Both are clamped.
    public static func moving(from: Int, to: Int, in order: [UUID]) -> [UUID] {
        guard order.indices.contains(from) else { return order }
        var order = order
        let entry = order.remove(at: from)
        order.insert(entry, at: max(0, min(to, order.count)))
        return order
    }

    /// SwiftUI `onMove` semantics: `offset` is a position in the list before the move.
    public static func moving(from: Int, toOffset offset: Int, in order: [UUID]) -> [UUID] {
        moving(from: from, to: offset > from ? offset - 1 : offset, in: order)
    }

    /// Every group once, in the song's own order: the starting point for a new section order.
    public static func naturalOrder(of groups: [SlideGroup]) -> [UUID] {
        groups.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
    }

    /// "Order 1", "Order 2" ... the first not already used (ignoring case).
    public static func newName(existing: [String], base: String = "Order") -> String {
        let used = Set(existing.map { $0.lowercased() })
        var n = existing.count + 1
        while used.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// How many slides each section has, from the song's slides in any order (each slide counted once).
    public static func slideCounts(of slides: [Slide]) -> [UUID: Int] {
        var seen = Set<UUID>()
        var counts: [UUID: Int] = [:]
        for slide in slides where seen.insert(slide.id).inserted {
            if let group = slide.groupID { counts[group, default: 0] += 1 }
        }
        return counts
    }

    /// How many slides the order plays: each entry plays all the slides of its section.
    public static func slideCount(of order: [UUID], counts: [UUID: Int]) -> Int {
        order.reduce(0) { $0 + (counts[$1] ?? 0) }
    }
}
