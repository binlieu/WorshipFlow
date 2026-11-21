// CUE-001 (AUTO-01): actions attached to slides, and the rule for when they fire. Foundation and Domain only.
import Foundation
import Domain

public enum SlideActionError: Error, Sendable, Equatable {
    case transportNotAllowed(CueTransport)
    case macroContainsTransport(macroName: String, transport: CueTransport)

    public var message: String {
        switch self {
        case .transportNotAllowed(let t):
            return "A slide action cannot move the show: \u{201C}\(t.summary)\u{201D} is not allowed here, because a slide could then advance itself in a loop. Use a button, a MIDI binding or the schedule instead."
        case .macroContainsTransport(let name, let t):
            return "A slide action cannot run the macro \u{201C}\(name)\u{201D}: it contains \u{201C}\(t.summary)\u{201D}, which moves the show."
        }
    }
}

/// Which slide went live. The app maps `index` in the live deck to a slide id.
public struct SlideLiveEvent: Sendable, Equatable, Hashable {
    public var presentationID: UUID
    public var index: Int

    public init(presentationID: UUID, index: Int) {
        self.presentationID = presentationID
        self.index = index
    }

    /// Decides from a show command and the state before and after it whether a slide went live.
    /// Fires for: trigger (also the same slide again), next and previous when the live slide changed (or when next takes
    /// the first slide live from stopped). Never for load, select, restore, quick edit, clear, clear all or stop, and not
    /// for a command that changed nothing.
    public static func detect(command: ShowCommand, before: ShowState, after: ShowState) -> SlideLiveEvent? {
        guard let deck = after.liveDeck, let index = after.liveIndex else { return nil }
        switch command {
        case .trigger(let i):
            guard before.previewDeck?.slides.indices.contains(i) == true, index == i else { return nil }
            return SlideLiveEvent(presentationID: deck.presentationID, index: i)
        case .next, .previous:
            let moved = before.liveDeck == nil || before.liveIndex != index
            return moved ? SlideLiveEvent(presentationID: deck.presentationID, index: index) : nil
        default:
            return nil
        }
    }
}

/// The actions attached to each slide. Transport actions are refused, and so are macros that contain them.
public struct SlideActionSet: Sendable, Equatable, Codable {
    public static let currentVersion = 1
    private var bySlide: [UUID: [CueAction]]

    public init() { bySlide = [:] }

    public var slideIDs: [UUID] { bySlide.keys.sorted { $0.uuidString < $1.uuidString } }

    public func actions(for slideID: UUID) -> [CueAction] { bySlide[slideID] ?? [] }

    public func actions(for event: SlideLiveEvent, slideID: (SlideLiveEvent) -> UUID?) -> [CueAction] {
        guard let id = slideID(event) else { return [] }
        return actions(for: id)
    }

    public static func validate(_ actions: [CueAction], library: MacroLibrary) -> [SlideActionError] {
        var errors: [SlideActionError] = []
        for a in actions {
            switch a {
            case .transport(let t): errors.append(.transportNotAllowed(t))
            case .runMacro(let id):
                if let t = library.firstTransport(in: id), let m = library.macro(id: id) {
                    errors.append(.macroContainsTransport(macroName: m.name, transport: t))
                }
            default: break
            }
        }
        return errors
    }

    /// Stores the actions for a slide (an empty list removes the entry). Throws the first problem and stores nothing.
    public mutating func set(_ actions: [CueAction], for slideID: UUID, library: MacroLibrary) throws {
        if let first = Self.validate(actions, library: library).first { throw first }
        bySlide[slideID] = actions.isEmpty ? nil : actions
    }

    /// Problems in what is stored now, for example after a macro was edited. Keyed by slide id.
    public func problems(library: MacroLibrary) -> [UUID: [SlideActionError]] {
        var out: [UUID: [SlideActionError]] = [:]
        for (id, actions) in bySlide {
            let e = Self.validate(actions, library: library)
            if !e.isEmpty { out[id] = e }
        }
        return out
    }

    private struct Entry: Codable { var slide: UUID; var actions: [CueAction] }
    private enum CodingKeys: String, CodingKey { case version, slides }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try c.decode([Entry].self, forKey: .slides)
        bySlide = Dictionary(entries.map { ($0.slide, $0.actions) }, uniquingKeysWith: { _, last in last })
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(slideIDs.map { Entry(slide: $0, actions: bySlide[$0] ?? []) }, forKey: .slides)
    }
}
