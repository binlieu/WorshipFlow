// OUT-004 / PRES-05: the import sheet's split of pasted lyrics into slides, with adjustable breaks. Foundation and Domain only.
import Foundation
import Domain

/// Two pasted texts split into slides. `slides` follows the first language; the second language is paired with it
/// section by section and line by line (PRES-10), so moving a break moves both together.
public struct ImportPlan: Equatable, Sendable {
    public private(set) var sections: [ReflowSection]
    public private(set) var slides: [ReflowSlide]
    private let secondarySections: [ReflowSection]
    public let hasSecondary: Bool

    public init(primary: String, secondary: String?, maxLines: Int) {
        let first = Reflow.sections(from: primary)
        sections = first
        slides = Reflow.slides(from: first, maxLines: maxLines)
        let second = secondary.map(Reflow.sections(from:)) ?? []
        secondarySections = second
        hasSecondary = !second.isEmpty
    }

    /// The name of the section a slide belongs to.
    public func sectionName(ofSlide index: Int) -> String? {
        guard slides.indices.contains(index), sections.indices.contains(slides[index].sectionIndex) else { return nil }
        return sections[slides[index].sectionIndex].name
    }

    /// Moves the break after slide `index` by `delta` lines (see `Reflow.moveBreak`).
    public mutating func moveBreak(after index: Int, by delta: Int) {
        slides = Reflow.moveBreak(in: slides, after: index, by: delta)
    }

    /// True when the break after slide `index` can move, that is when the next slide is in the same section.
    public func canMoveBreak(after index: Int) -> Bool {
        slides.indices.contains(index) && slides.indices.contains(index + 1)
            && slides[index].sectionIndex == slides[index + 1].sectionIndex
    }

    /// The second-language text that goes with slide `index`, or nil.
    public func secondaryText(ofSlide index: Int) -> String? {
        results.indices.contains(index) ? results[index].content.secondary : nil
    }

    /// What will be saved: one result per slide. With no break moved this equals `Reflow.contents`.
    public var results: [ReflowResult] {
        var output: [ReflowResult] = []
        var consumed: [Int: Int] = [:]                       // lines of each section used by earlier slides
        for (slideIndex, slide) in slides.enumerated() {
            let section = slide.sectionIndex
            let start = consumed[section] ?? 0
            let end = start + slide.lines.count
            consumed[section] = end
            let isLast = slideIndex + 1 >= slides.count || slides[slideIndex + 1].sectionIndex != section
            let other = section < secondarySections.count ? secondarySections[section].lines : []
            let paired = start < other.count ? Array(other[start..<(isLast ? other.count : min(end, other.count))]) : []
            output.append(ReflowResult(
                sectionName: sections.indices.contains(section) ? sections[section].name : nil,
                content: SlideContent(primary: slide.lines.joined(separator: "\n"),
                                      secondary: paired.isEmpty ? nil : paired.joined(separator: "\n"))))
        }
        if secondarySections.count > sections.count, !output.isEmpty {
            let extra = secondarySections[sections.count...].flatMap(\.lines)
            var last = output[output.count - 1].content
            last.secondary = ([last.secondary].compactMap { $0 } + extra).joined(separator: "\n")
            output[output.count - 1].content = last
        }
        return output
    }
}
