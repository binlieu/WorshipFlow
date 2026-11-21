// SLIDE-004: pure text-to-slides rules (PRES-05, PRES-10). Foundation only.
import Foundation

public struct ReflowSection: Sendable, Equatable {
    /// The section label as the user wrote it (colon dropped), or nil for an unlabelled block.
    public var name: String?
    public var lines: [String]

    public init(name: String?, lines: [String]) {
        self.name = name
        self.lines = lines
    }
}

public struct ReflowSlide: Sendable, Equatable {
    public var sectionIndex: Int
    public var lines: [String]

    public init(sectionIndex: Int, lines: [String]) {
        self.sectionIndex = sectionIndex
        self.lines = lines
    }
}

public struct ReflowResult: Sendable, Equatable {
    public var sectionName: String?
    public var content: SlideContent

    public init(sectionName: String?, content: SlideContent) {
        self.sectionName = sectionName
        self.content = content
    }
}

public enum ReflowLanguage: Sendable, Equatable {
    case primary, secondary
}

public enum Reflow {
    private static let labelWords: Set<String> = [
        "verse", "chorus", "pre-chorus", "pre chorus", "prechorus", "bridge", "tag", "intro", "outro",
        "ending", "refrain", "interlude",
        "câu", "điệp khúc", "đoạn", "kết",
    ]

    /// The stored section name when the whole line is a label (word, optional number, optional
    /// trailing colon, any letter case), else nil.
    static func label(_ line: String) -> String? {
        var name = line.trimmingCharacters(in: .whitespaces)
        if name.hasSuffix(":") { name.removeLast() }
        name = name.trimmingCharacters(in: .whitespaces)
        var word = Substring(name)
        while let last = word.last, last.isASCII, last.isNumber { word = word.dropLast() }
        let stem = word.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, labelWords.contains(stem) else { return nil }
        return name
    }

    /// Splits text into sections at blank lines. A block whose first line is a label is named by
    /// it; a label alone in its block names the next unlabelled block. Lines are trimmed.
    public static func sections(from text: String) -> [ReflowSection] {
        var blocks: [[String]] = [[]]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                if !(blocks.last?.isEmpty ?? true) { blocks.append([]) }
            } else {
                blocks[blocks.count - 1].append(line)
            }
        }
        var result: [ReflowSection] = []
        var pending: String?
        for block in blocks where !block.isEmpty {
            var lines = block
            var name: String?
            if let found = label(lines[0]) {
                name = found
                lines.removeFirst()
            }
            if lines.isEmpty {
                pending = name ?? pending
                continue
            }
            if name == nil { name = pending }
            pending = nil
            result.append(ReflowSection(name: name, lines: lines))
        }
        return result
    }

    /// Chops each section into slides of at most `maxLines` lines (below 1 counts as 1). A slide
    /// never spans two sections.
    public static func slides(from sections: [ReflowSection], maxLines: Int) -> [ReflowSlide] {
        let size = max(maxLines, 1)
        var result: [ReflowSlide] = []
        for (index, section) in sections.enumerated() {
            var start = 0
            while start < section.lines.count {
                let end = min(start + size, section.lines.count)
                result.append(ReflowSlide(sectionIndex: index, lines: Array(section.lines[start..<end])))
                start = end
            }
        }
        return result
    }

    /// Moves the break after slide `index` by `delta` lines inside one section. Positive pulls
    /// lines from the next slide up; negative pushes lines from this slide down. The move is
    /// clamped, an emptied slide is removed, and nothing changes if the two slides belong to
    /// different sections or `index` is out of range. No line is ever lost.
    public static func moveBreak(in slides: [ReflowSlide], after index: Int, by delta: Int) -> [ReflowSlide] {
        guard slides.indices.contains(index), slides.indices.contains(index + 1),
              slides[index].sectionIndex == slides[index + 1].sectionIndex, delta != 0 else { return slides }
        var result = slides
        if delta > 0 {
            let count = min(delta, result[index + 1].lines.count)
            result[index].lines += result[index + 1].lines.prefix(count)
            result[index + 1].lines.removeFirst(count)
        } else {
            let count = min(-delta, result[index].lines.count)
            result[index + 1].lines.insert(contentsOf: result[index].lines.suffix(count), at: 0)
            result[index].lines.removeLast(count)
        }
        return result.filter { !$0.lines.isEmpty }
    }

    /// Splits `primary` into slides and pairs `secondary` with it section by section and line by
    /// line (PRES-10). Missing secondary lines give nil; surplus secondary lines join the last
    /// slide of their section, and surplus secondary sections join the last slide overall.
    public static func contents(primary: String, secondary: String?, maxLines: Int) -> [ReflowResult] {
        let primarySections = sections(from: primary)
        let secondarySections = secondary.map(sections(from:)) ?? []
        let size = max(maxLines, 1)
        var results: [ReflowResult] = []
        for (index, section) in primarySections.enumerated() {
            let other = index < secondarySections.count ? secondarySections[index].lines : []
            var start = 0
            while start < section.lines.count {
                let end = min(start + size, section.lines.count)
                let isLast = end == section.lines.count
                let paired = start < other.count ? Array(other[start..<(isLast ? other.count : min(end, other.count))]) : []
                results.append(ReflowResult(
                    sectionName: section.name,
                    content: SlideContent(primary: section.lines[start..<end].joined(separator: "\n"),
                                          secondary: paired.isEmpty ? nil : paired.joined(separator: "\n"))))
                start = end
            }
        }
        if secondarySections.count > primarySections.count, !results.isEmpty {
            let extra = secondarySections[primarySections.count...].flatMap(\.lines)
            var last = results[results.count - 1].content
            last.secondary = ([last.secondary].compactMap { $0 } + extra).joined(separator: "\n")
            results[results.count - 1].content = last
        }
        return results
    }

    /// Rebuilds editable text from slides: a label line (when named), the lines, and a blank line
    /// between sections. Consecutive slides with the same name form one section. Slides without
    /// text in `language` are skipped.
    public static func text(from slides: [(name: String?, content: SlideContent)], language: ReflowLanguage) -> String {
        var blocks: [(name: String?, lines: [String])] = []
        var previous: String??
        for slide in slides {
            let body = language == .primary ? slide.content.primary : slide.content.secondary
            guard let body, !body.isEmpty else { continue }
            if let previous, previous == slide.name, !blocks.isEmpty {
                blocks[blocks.count - 1].lines.append(body)
            } else {
                blocks.append((slide.name, [body]))
            }
            previous = .some(slide.name)
        }
        return blocks.map { block in
            ((block.name.map { [$0] } ?? []) + block.lines).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
