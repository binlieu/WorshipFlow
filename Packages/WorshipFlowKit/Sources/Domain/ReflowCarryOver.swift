// SLIDE-001b (KI-019): what a re-flow keeps from the slides it replaces. Foundation only.
import Foundation

/// A slide as it stands before a re-flow, with the name of the section it belongs to (nil: none).
public struct ExistingSlide: Sendable, Equatable {
    public var sectionName: String?
    public var content: SlideContent
    public var notes: String

    public init(sectionName: String?, content: SlideContent, notes: String) {
        self.sectionName = sectionName
        self.content = content
        self.notes = notes
    }
}

/// Speaker notes or objects of an old slide that no new slide takes over. The operator is told before they are lost.
public struct ReflowLoss: Sendable, Equatable {
    public var sectionName: String?
    /// The first language words of the old slide, so the operator can tell which one it was.
    public var primary: String
    public var notes: String
    public var objectCount: Int

    public init(sectionName: String?, primary: String, notes: String, objectCount: Int) {
        self.sectionName = sectionName
        self.primary = primary
        self.notes = notes
        self.objectCount = objectCount
    }
}

/// For each new slide, the notes and objects it takes over from an old slide, and what is lost.
public struct ReflowCarry: Sendable, Equatable {
    /// One entry per new slide, in order. Empty notes and no objects when no old slide matched.
    public var notes: [String]
    public var objects: [[SlideObject]]
    public var losses: [ReflowLoss]
}

extension Reflow {
    /// A new slide takes the notes and objects of the first old slide that has the same words (first language, compared
    /// without capitals, accents or punctuation) and the same section name, and that no earlier new slide took. Old slides
    /// with notes or objects that nothing takes are listed as losses, in their old order.
    public static func carryOver(from old: [ExistingSlide], to results: [ReflowResult]) -> ReflowCarry {
        var used = Set<Int>()
        var notes: [String] = []
        var objects: [[SlideObject]] = []
        let oldKeys = old.map { SearchFolding.fold($0.content.primary) }
        for result in results {
            let key = SearchFolding.fold(result.content.primary)
            let match = old.indices.first { !used.contains($0) && oldKeys[$0] == key && old[$0].sectionName == result.sectionName }
            if let match {
                used.insert(match)
                notes.append(old[match].notes)
                objects.append(old[match].content.objects)
            } else {
                notes.append("")
                objects.append([])
            }
        }
        var losses: [ReflowLoss] = []
        for (i, slide) in old.enumerated() where !used.contains(i) {
            let hasNotes = !slide.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard hasNotes || !slide.content.objects.isEmpty else { continue }
            losses.append(ReflowLoss(sectionName: slide.sectionName, primary: slide.content.primary, notes: slide.notes,
                                     objectCount: slide.content.objects.count))
        }
        return ReflowCarry(notes: notes, objects: objects, losses: losses)
    }
}
