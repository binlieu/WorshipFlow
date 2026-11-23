// CUE-002b (item 6): the decisions behind the Cues mode's lists and pickers. Foundation and CueEngine only.
import Foundation
import CueEngine

/// The kinds of action a picker offers. One per thing the operator would name; the engine's `CueAction` cases carry the values.
public enum CueActionKind: String, CaseIterable, Identifiable, Sendable {
    case next, previous, goToSlide, clear, clearAll, blackout, stop
    case look, prop, showMessage, hideMessage
    case startTimer, pauseTimer, resetTimer
    case setBackground, clearBackground, playClip, stopClip
    /// MEDIA-010: the three live clears. (`clearBackground` above drops the live override; this one hides every background.)
    case clearLiveBackground, clearLiveForeground, clearMusic
    case playSound, stopSound
    case midiOut, runMacro, wait

    public var id: String { rawValue }

    public var isTransport: Bool {
        switch self {
        case .next, .previous, .goToSlide, .clear, .clearAll, .blackout, .stop, .clearLiveBackground, .clearLiveForeground, .clearMusic: true
        default: false
        }
    }

    public var title: String {
        switch self {
        case .next: "Next slide"
        case .previous: "Previous slide"
        case .goToSlide: "Go to slide"
        case .clear: "Clear"
        case .clearAll: "Clear all"
        case .blackout: "Blackout"
        case .stop: "Stop"
        case .clearLiveBackground: "Clear live background"
        case .clearLiveForeground: "Clear live foreground"
        case .clearMusic: "Clear music"
        case .look: "Set Look"
        case .prop: "Prop on or off"
        case .showMessage: "Stage message"
        case .hideMessage: "Clear stage message"
        case .startTimer: "Start timer"
        case .pauseTimer: "Pause timer"
        case .resetTimer: "Reset timer"
        case .setBackground: "Set background"
        case .clearBackground: "Clear background"
        case .playClip: "Play clip over the slide"
        case .stopClip: "Stop clip"
        case .playSound: "Play sound"
        case .stopSound: "Stop sound"
        case .midiOut: "MIDI out"
        case .runMacro: "Run macro"
        case .wait: "Wait"
        }
    }

    public var group: String {
        switch self {
        case .next, .previous, .goToSlide, .clear, .clearAll, .blackout, .stop, .clearLiveBackground, .clearLiveForeground, .clearMusic: "Show"
        case .look, .prop: "Look and props"
        case .showMessage, .hideMessage, .startTimer, .pauseTimer, .resetTimer: "Stage"
        case .setBackground, .clearBackground, .playClip, .stopClip: "Media"
        case .playSound, .stopSound: "Audio"
        case .midiOut, .runMacro, .wait: "Other"
        }
    }

    /// The kind of a stored action; nil for one this version does not know.
    public static func of(_ action: CueAction) -> CueActionKind? {
        switch action {
        case .transport(let t):
            switch t {
            case .next: return .next
            case .previous: return .previous
            case .goToSlide: return .goToSlide
            case .clear: return .clear
            case .clearAll: return .clearAll
            case .blackout: return .blackout
            case .stop: return .stop
            case .clearBackground: return .clearLiveBackground
            case .clearForeground: return .clearLiveForeground
            case .clearMusic: return .clearMusic
            }
        case .selectLook: return .look
        case .prop: return .prop
        case .showMessage: return .showMessage
        case .hideMessage: return .hideMessage
        case .startTimer: return .startTimer
        case .pauseTimer: return .pauseTimer
        case .resetTimer: return .resetTimer
        case .playForeground: return .playClip
        case .setBackground(let id): return id == nil ? .clearBackground : .setBackground
        case .stopForeground: return .stopClip
        case .playAudio: return .playSound
        case .stopAudio: return .stopSound
        case .midiOut: return .midiOut
        case .runMacro: return .runMacro
        case .wait: return .wait
        case .unknown: return nil
        }
    }
}

public struct CueChoice: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// What the pickers can choose from, read from the models by the app.
public struct CueChoices: Sendable, Equatable {
    public var looks: [CueChoice] = []
    public var props: [CueChoice] = []
    public var timers: [CueChoice] = []
    /// Pictures and videos (anything that can sit behind or over the words).
    public var pictures: [CueChoice] = []
    public var sounds: [CueChoice] = []
    public var macros: [CueChoice] = []

    public init(looks: [CueChoice] = [], props: [CueChoice] = [], timers: [CueChoice] = [], pictures: [CueChoice] = [],
                sounds: [CueChoice] = [], macros: [CueChoice] = []) {
        self.looks = looks
        self.props = props
        self.timers = timers
        self.pictures = pictures
        self.sounds = sounds
        self.macros = macros
    }

    public func macros(excluding id: UUID?) -> [CueChoice] { macros.filter { $0.id != id } }
}

public enum CueScreen: String, Sendable, Equatable {
    case audience, stage, broadcast
    public var tag: String { switch self { case .audience: "AUD"; case .stage: "STG"; case .broadcast: "BRD" } }
}

/// UI-007d: a marker's actions follow the rule of a slide's: nothing that moves the show.
public enum CueActionContext: Sendable { case slide, macro, marker }

/// One row of an action list.
public struct CueActionRow: Sendable, Equatable {
    public var title: String
    public var detail: String
    /// The screens the action can change. A true statement about the action, not decoration.
    public var screens: [CueScreen]
    /// The thing it points at is gone, or the action is not understood: drawn as a warning.
    public var isBroken: Bool
}

public enum CueActionEditing {
    /// One fixed id for the stage message action: the app has a single stage message, so the id only has to be stable.
    public static let stageMessageID = UUID(uuidString: "5A6E0000-0000-4000-8000-00000000C0DE")!

    public static func isAllowed(_ kind: CueActionKind, in context: CueActionContext) -> Bool {
        context == .macro || !kind.isTransport
    }

    public static func unavailableReason(for kind: CueActionKind, choices c: CueChoices) -> String? {
        switch kind {
        case .look: return c.looks.isEmpty ? "No Looks yet" : nil
        case .prop: return c.props.isEmpty ? "No props yet" : nil
        case .startTimer, .pauseTimer, .resetTimer: return c.timers.isEmpty ? "No timers yet" : nil
        case .setBackground, .playClip: return c.pictures.isEmpty ? "No pictures or videos in the media bin" : nil
        case .playSound, .stopSound: return c.sounds.isEmpty ? "No sounds in the media bin" : nil
        case .runMacro: return c.macros.isEmpty ? "No other macros yet" : nil
        default: return nil
        }
    }

    /// A new action of this kind with the first thing to choose already chosen; nil when there is nothing to choose.
    public static func defaultAction(for kind: CueActionKind, choices c: CueChoices) -> CueAction? {
        guard unavailableReason(for: kind, choices: c) == nil else { return nil }
        switch kind {
        case .next: return .transport(.next)
        case .previous: return .transport(.previous)
        case .goToSlide: return .transport(.goToSlide(index: 0))
        case .clear: return .transport(.clear)
        case .clearAll: return .transport(.clearAll)
        case .blackout: return .transport(.blackout(.toggle))
        case .stop: return .transport(.stop)
        case .clearLiveBackground: return .transport(.clearBackground)
        case .clearLiveForeground: return .transport(.clearForeground)
        case .clearMusic: return .transport(.clearMusic)
        case .look: return c.looks.first.map { .selectLook($0.id) }
        case .prop: return c.props.first.map { .prop(id: $0.id, isOn: true) }
        case .showMessage: return .showMessage(id: stageMessageID, fields: ["text": "Message"])
        case .hideMessage: return .hideMessage(id: stageMessageID)
        case .startTimer: return c.timers.first.map { .startTimer($0.id) }
        case .pauseTimer: return c.timers.first.map { .pauseTimer($0.id) }
        case .resetTimer: return c.timers.first.map { .resetTimer($0.id) }
        case .setBackground: return c.pictures.first.map { .setBackground(assetID: $0.id) }
        case .clearBackground: return .setBackground(assetID: nil)
        case .playClip: return c.pictures.first.map { .playForeground(assetID: $0.id) }
        case .stopClip: return .stopForeground
        case .playSound: return c.sounds.first.map { .playAudio(assetID: $0.id) }
        case .stopSound: return c.sounds.first.map { .stopAudio(assetID: $0.id) }
        case .midiOut: return .midiOut(.noteOn(channel: 1, note: 60, velocity: 100))
        case .runMacro: return c.macros.first.map { .runMacro($0.id) }
        case .wait: return .wait(seconds: 1)
        }
    }

    public static func describe(_ action: CueAction, choices c: CueChoices) -> CueActionRow {
        func named(_ list: [CueChoice], _ id: UUID, missing: String) -> (String, Bool) {
            list.first { $0.id == id }.map { ($0.name, false) } ?? ("(missing \(missing))", true)
        }
        let all: [CueScreen] = [.audience, .stage, .broadcast]
        switch action {
        case .transport(let t):
            switch t {
            case .next: return CueActionRow(title: "Next slide", detail: "", screens: all, isBroken: false)
            case .previous: return CueActionRow(title: "Previous slide", detail: "", screens: all, isBroken: false)
            case .goToSlide(let i): return CueActionRow(title: "Go to slide", detail: "\(i + 1)", screens: all, isBroken: false)
            case .clear: return CueActionRow(title: "Clear", detail: "", screens: all, isBroken: false)
            case .clearAll: return CueActionRow(title: "Clear all", detail: "", screens: all, isBroken: false)
            case .blackout(let m): return CueActionRow(title: "Blackout", detail: m.rawValue, screens: all, isBroken: false)
            case .stop: return CueActionRow(title: "Stop", detail: "", screens: all, isBroken: false)
            case .clearBackground: return CueActionRow(title: "Clear live background", detail: "", screens: [.audience, .broadcast], isBroken: false)
            case .clearForeground: return CueActionRow(title: "Clear live foreground", detail: "", screens: [.audience, .broadcast], isBroken: false)
            case .clearMusic: return CueActionRow(title: "Clear music", detail: "", screens: [], isBroken: false)
            }
        case .selectLook(let id):
            let (n, bad) = named(c.looks, id, missing: "Look")
            return CueActionRow(title: "Set Look", detail: n, screens: [.audience, .broadcast], isBroken: bad)
        case .prop(let id, let on):
            let (n, bad) = named(c.props, id, missing: "prop")
            return CueActionRow(title: on ? "Prop on" : "Prop off", detail: n, screens: [.audience, .broadcast], isBroken: bad)
        case .showMessage(_, let fields):
            return CueActionRow(title: "Stage message", detail: fields["text"] ?? "", screens: [.stage], isBroken: (fields["text"] ?? "").isEmpty)
        case .hideMessage:
            return CueActionRow(title: "Clear stage message", detail: "", screens: [.stage], isBroken: false)
        case .startTimer(let id):
            let (n, bad) = named(c.timers, id, missing: "timer")
            return CueActionRow(title: "Start timer", detail: n, screens: [.stage], isBroken: bad)
        case .pauseTimer(let id):
            let (n, bad) = named(c.timers, id, missing: "timer")
            return CueActionRow(title: "Pause timer", detail: n, screens: [.stage], isBroken: bad)
        case .resetTimer(let id):
            let (n, bad) = named(c.timers, id, missing: "timer")
            return CueActionRow(title: "Reset timer", detail: n, screens: [.stage], isBroken: bad)
        case .playForeground(let id):
            let (n, bad) = named(c.pictures, id, missing: "file")
            return CueActionRow(title: "Play clip over the slide", detail: n, screens: [.audience, .broadcast], isBroken: bad)
        case .setBackground(let id):
            guard let id else { return CueActionRow(title: "Clear background", detail: "", screens: [.audience], isBroken: false) }
            let (n, bad) = named(c.pictures, id, missing: "file")
            return CueActionRow(title: "Set background", detail: n, screens: [.audience], isBroken: bad)
        case .stopForeground:
            return CueActionRow(title: "Stop clip", detail: "", screens: [.audience, .broadcast], isBroken: false)
        case .playAudio(let id):
            let (n, bad) = named(c.sounds, id, missing: "sound")
            return CueActionRow(title: "Play sound", detail: n, screens: [], isBroken: bad)
        case .stopAudio(let id):
            let (n, bad) = named(c.sounds, id, missing: "sound")
            return CueActionRow(title: "Stop sound", detail: n, screens: [], isBroken: bad)
        case .midiOut(let m):
            return CueActionRow(title: "MIDI out", detail: midiDetail(m), screens: [], isBroken: !m.isValid)
        case .runMacro(let id):
            let (n, bad) = named(c.macros, id, missing: "macro")
            return CueActionRow(title: "Run macro", detail: n, screens: [], isBroken: bad)
        case .wait(let s):
            return CueActionRow(title: "Wait", detail: "\(String(format: "%g", s)) s", screens: [], isBroken: !(s.isFinite && s >= 0))
        case .unknown:
            return CueActionRow(title: "Unknown action", detail: "\(action.summary): skipped when run, kept as it is", screens: [], isBroken: true)
        }
    }

    static func midiDetail(_ m: MIDIMessage) -> String {
        switch m {
        case .noteOn(let c, let n, let v): return "Note \(MIDIText.noteName(n)) on \u{00B7} ch \(c) \u{00B7} velocity \(v)"
        case .noteOff(let c, let n, _): return "Note \(MIDIText.noteName(n)) off \u{00B7} ch \(c)"
        case .controlChange(let c, let n, let v): return "CC \(n) = \(v) \u{00B7} ch \(c)"
        case .programChange(let c, let p): return "Program \(p) \u{00B7} ch \(c)"
        }
    }
}

/// Moving, inserting, replacing and removing the steps of a macro or the actions of a slide. Out-of-range indices are clamped or ignored.
public enum CueStepEditing {
    public static func move(_ steps: inout [CueAction], from: Int, to: Int) {
        guard steps.indices.contains(from) else { return }
        let step = steps.remove(at: from)
        steps.insert(step, at: min(max(to, 0), steps.count))
    }
    public static func insert(_ action: CueAction, into steps: inout [CueAction], at index: Int) {
        steps.insert(action, at: min(max(index, 0), steps.count))
    }
    public static func replace(_ steps: inout [CueAction], at index: Int, with action: CueAction) {
        guard steps.indices.contains(index) else { return }
        steps[index] = action
    }
    public static func remove(_ steps: inout [CueAction], at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
    }
}
