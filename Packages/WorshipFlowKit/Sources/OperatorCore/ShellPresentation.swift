// UI-001: small pure decisions the shell draws: role pills, output health, section runs, the live line, the library
// filter. Views stay thin. Foundation and Domain only.
import Foundation
import Domain

// MARK: Role pills (AUD, STG, BRD)

/// What the output coordinator knows about one screen, without the output engine's types.
public enum ScreenRunState: Sendable, Equatable { case stopped, running, hidden, faulted }

public struct ScreenStatusInput: Sendable, Equatable {
    public var role: ScreenRole
    public var isEnabled: Bool
    public var run: ScreenRunState

    public init(role: ScreenRole, isEnabled: Bool, run: ScreenRunState) {
        self.role = role
        self.isEnabled = isEnabled
        self.run = run
    }
}

public enum RoleStatus: Sendable, Equatable { case on, off, fault }

public struct RolePill: Sendable, Equatable, Identifiable {
    public var role: ScreenRole
    public var status: RoleStatus
    /// True when the role's only running screens are covered by another window (nothing is presented).
    public var isCovered: Bool

    public var id: ScreenRole { role }

    public var abbreviation: String {
        switch role { case .audience: "AUD"; case .stage: "STG"; case .broadcast: "BRD" }
    }
    public var roleName: String {
        switch role { case .audience: "Audience"; case .stage: "Stage"; case .broadcast: "Broadcast" }
    }
    /// The state as a word, so it is never colour alone.
    public var statusWord: String {
        switch status { case .on: "on"; case .off: "off"; case .fault: "fault" }
    }
    public var accessibilityText: String {
        "\(roleName) screens: \(statusWord)" + (isCovered && status == .on ? ", covered by another window" : "")
    }
}

public enum RolePills {
    /// Always three pills in the order Audience, Stage, Broadcast. A fault on any enabled screen of a role wins; a
    /// running (or covered) enabled screen is on; everything else is off.
    public static func pills(from screens: [ScreenStatusInput]) -> [RolePill] {
        [ScreenRole.audience, .stage, .broadcast].map { role in
            let enabled = screens.filter { $0.role == role && $0.isEnabled }
            if enabled.contains(where: { $0.run == .faulted }) { return RolePill(role: role, status: .fault, isCovered: false) }
            let live = enabled.filter { $0.run == .running || $0.run == .hidden }
            guard !live.isEmpty else { return RolePill(role: role, status: .off, isCovered: false) }
            return RolePill(role: role, status: .on, isCovered: live.allSatisfy { $0.run == .hidden })
        }
    }
}

// MARK: Output health readout

public struct OutputHealthSample: Sendable, Equatable {
    public var role: ScreenRole
    public var run: ScreenRunState
    public var refreshRate: Double
    public var dropped: Int
    public var late: Int

    public init(role: ScreenRole, run: ScreenRunState, refreshRate: Double, dropped: Int, late: Int) {
        self.role = role
        self.run = run
        self.refreshRate = refreshRate
        self.dropped = dropped
        self.late = late
    }
}

public struct OutputHealthSummary: Sendable, Equatable {
    public var framesPerSecond: Double
    public var dropped: Int
    public var late: Int
    public var needsAttention: Bool

    public var rateText: String {
        let rounded = (framesPerSecond * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(saturating: rounded)) fps" : String(format: "%.2f fps", rounded)
    }
    public var countsText: String { "dropped \(dropped) · late \(late)" }
}

public enum OutputHealth {
    /// Nil when no screen is running. The rate is the audience screen's (else the first running screen's); dropped and
    /// late frames are totalled over every running screen.
    public static func summary(from samples: [OutputHealthSample]) -> OutputHealthSummary? {
        let running = samples.filter { $0.run == .running || $0.run == .hidden }
        guard let lead = running.first(where: { $0.role == .audience }) ?? running.first else { return nil }
        return OutputHealthSummary(framesPerSecond: lead.refreshRate, dropped: running.reduce(0) { $0 + $1.dropped },
                                   late: running.reduce(0) { $0 + $1.late },
                                   needsAttention: samples.contains { $0.run == .faulted })
    }
}

// MARK: Section runs

public enum SectionTone: Sendable, Equatable {
    case verse, chorus, bridge, ending, other

    public init(sectionName: String?) {
        let name = (sectionName ?? "").lowercased()
        if name.contains("chorus") || name.contains("refrain") { self = .chorus }
        else if name.contains("verse") { self = .verse }
        else if name.contains("bridge") { self = .bridge }
        else if name.contains("ending") || name.contains("outro") || name.hasPrefix("end") || name.contains("tag") { self = .ending }
        else { self = .other }
    }
}

public struct SectionRun: Sendable, Equatable, Identifiable {
    public var id: Int
    public var groupID: UUID?
    public var name: String?
    public var tone: SectionTone
    public var indices: [Int]
    /// How many times in a row the section plays in this run (two plays of a two-slide section = 2), 1 when unknown.
    public var repeatCount: Int
}

public enum SectionRuns {
    public static func runs(slideGroupIDs: [UUID?], groups: [SlideGroup], groupSlideCounts: [UUID: Int]) -> [SectionRun] {
        var result: [SectionRun] = []
        for (i, groupID) in slideGroupIDs.enumerated() {
            if let last = result.last, last.groupID == groupID {
                result[result.count - 1].indices.append(i)
            } else {
                let name = groupID.flatMap { id in groups.first { $0.id == id }?.name }
                result.append(SectionRun(id: result.count, groupID: groupID, name: name, tone: SectionTone(sectionName: name),
                                         indices: [i], repeatCount: 1))
            }
        }
        for k in result.indices {
            guard let id = result[k].groupID, let each = groupSlideCounts[id], each > 0 else { continue }
            let n = result[k].indices.count
            if n % each == 0, n / each > 1 { result[k].repeatCount = n / each }
        }
        return result
    }
}

// MARK: The live line

public enum LiveSummary {
    /// "Amazing Grace · Chorus · slide 3 of 9" (`index` counts from 0).
    public static func positionLine(title: String?, section: String?, index: Int, count: Int) -> String {
        var parts: [String] = []
        for part in [title, section] {
            if let t = part?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { parts.append(t) }
        }
        parts.append("slide \(index + 1) of \(count)")
        return parts.joined(separator: " · ")
    }

    /// The first-language words of a slide on one line.
    public static func line(for slide: SlideContent) -> String {
        let text = slide.primary.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? "(blank slide)" : text
    }
}

// MARK: Library filter

public enum LibraryFilter {
    /// Keeps the items whose title contains every word of `query`, ignoring case and accents (the search rule).
    public static func apply<T>(_ query: String, to items: [T], title: (T) -> String) -> [T] {
        let words = SearchFolding.fold(query).split(separator: " ")
        guard !words.isEmpty else { return items }
        return items.filter { item in
            let folded = SearchFolding.fold(title(item))
            return words.allSatisfy { folded.contains($0) }
        }
    }
}
