// CUE-001 (AUTO-01, AUTO-02, AUTO-04): the vocabulary of show-control actions and its stable JSON. Foundation only.
import Foundation

public enum CueBlackout: String, Sendable, Equatable, Hashable, Codable {
    case on, off, toggle
}

/// Commands that move or clear the show. Named apart from the operator's key-routing command type so a file can import
/// both modules.
public enum CueTransport: Sendable, Equatable, Hashable, Codable {
    case next
    case previous
    /// Zero-based slide index in the live deck.
    case goToSlide(index: Int)
    case clear
    case clearAll
    case blackout(CueBlackout)
    case stop

    public var summary: String {
        switch self {
        case .next: return "Next slide"
        case .previous: return "Previous slide"
        case .goToSlide(let i): return "Go to slide \(i + 1)"
        case .clear: return "Clear"
        case .clearAll: return "Clear all"
        case .blackout(let m): return "Blackout \(m.rawValue)"
        case .stop: return "Stop"
        }
    }
}

public enum CueAction: Sendable, Equatable, Hashable, Codable {
    case transport(CueTransport)
    case selectLook(UUID)
    case prop(id: UUID, isOn: Bool)
    case showMessage(id: UUID, fields: [String: String])
    case hideMessage(id: UUID)
    case startTimer(UUID)
    case pauseTimer(UUID)
    case resetTimer(UUID)
    case playForeground(assetID: UUID)
    /// Nil clears the background.
    case setBackground(assetID: UUID?)
    case stopForeground
    case playAudio(assetID: UUID)
    case stopAudio(assetID: UUID)
    case midiOut(MIDIMessage)
    case runMacro(UUID)
    case wait(seconds: Double)
    /// An action written by a newer version (or damaged). Skipped when run, reported, and written back unchanged.
    case unknown(CueJSON)

    public var isTransport: Bool { if case .transport = self { return true } else { return false } }

    /// Short operator-readable text, used in failure reports.
    public var summary: String {
        switch self {
        case .transport(let t): return t.summary
        case .selectLook: return "Select Look"
        case .prop(_, let on): return on ? "Show prop" : "Hide prop"
        case .showMessage: return "Show message"
        case .hideMessage: return "Hide message"
        case .startTimer: return "Start timer"
        case .pauseTimer: return "Pause timer"
        case .resetTimer: return "Reset timer"
        case .playForeground: return "Play clip over the slide"
        case .setBackground(let a): return a == nil ? "Clear background" : "Set background"
        case .stopForeground: return "Stop clip"
        case .playAudio: return "Play sound"
        case .stopAudio: return "Stop sound"
        case .midiOut: return "Send MIDI"
        case .runMacro: return "Run macro"
        case .wait(let s): return "Wait \(String(format: "%g", s)) s"
        case .unknown(let raw):
            if let kind = raw.objectValue?["kind"]?.stringValue { return "Unknown action \"\(kind)\"" }
            return "Unknown action"
        }
    }

    // MARK: JSON (flat objects with a "kind"; see docs/features/CUE-001-cue-engine.md)

    public init(from decoder: Decoder) throws {
        let raw = try CueJSON(from: decoder)
        self = CueAction(json: raw) ?? .unknown(raw)
    }

    public func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }

    init?(json raw: CueJSON) {
        guard let o = raw.objectValue, let kind = o["kind"]?.stringValue else { return nil }
        func id() -> UUID? { o["id"]?.uuidValue }
        func asset() -> UUID? { o["assetID"]?.uuidValue }
        switch kind {
        case "transport.next": self = .transport(.next)
        case "transport.previous": self = .transport(.previous)
        case "transport.goToSlide":
            guard let i = o["index"]?.countValue else { return nil }
            self = .transport(.goToSlide(index: i))
        case "transport.clear": self = .transport(.clear)
        case "transport.clearAll": self = .transport(.clearAll)
        case "transport.blackout":
            guard let m = o["mode"]?.stringValue.flatMap(CueBlackout.init(rawValue:)) else { return nil }
            self = .transport(.blackout(m))
        case "transport.stop": self = .transport(.stop)
        case "look.select":
            guard let i = id() else { return nil }
            self = .selectLook(i)
        case "prop.set":
            guard let i = id(), let on = o["on"]?.boolValue else { return nil }
            self = .prop(id: i, isOn: on)
        case "message.show":
            guard let i = id(), let f = o["fields"]?.objectValue else { return nil }
            var fields: [String: String] = [:]
            for (k, v) in f {
                guard let s = v.stringValue else { return nil }
                fields[k] = s
            }
            self = .showMessage(id: i, fields: fields)
        case "message.hide":
            guard let i = id() else { return nil }
            self = .hideMessage(id: i)
        case "timer.start":
            guard let i = id() else { return nil }
            self = .startTimer(i)
        case "timer.pause":
            guard let i = id() else { return nil }
            self = .pauseTimer(i)
        case "timer.reset":
            guard let i = id() else { return nil }
            self = .resetTimer(i)
        case "media.playForeground":
            guard let a = asset() else { return nil }
            self = .playForeground(assetID: a)
        case "media.setBackground":
            switch o["assetID"] {
            case .some(.null): self = .setBackground(assetID: nil)
            case .some(let v):
                guard let a = v.uuidValue else { return nil }
                self = .setBackground(assetID: a)
            case .none: return nil
            }
        case "media.stopForeground": self = .stopForeground
        case "audio.play":
            guard let a = asset() else { return nil }
            self = .playAudio(assetID: a)
        case "audio.stop":
            guard let a = asset() else { return nil }
            self = .stopAudio(assetID: a)
        case "midi.out":
            guard let type = o["type"]?.stringValue, let ch = o["channel"]?.countValue,
                  let d1 = o["data1"]?.countValue, let d2 = o["data2"]?.countValue else { return nil }
            let m: MIDIMessage
            switch type {
            case "noteOn": m = .noteOn(channel: ch, note: d1, velocity: d2)
            case "noteOff": m = .noteOff(channel: ch, note: d1, velocity: d2)
            case "controlChange": m = .controlChange(channel: ch, controller: d1, value: d2)
            case "programChange": m = .programChange(channel: ch, program: d1)
            default: return nil
            }
            guard m.isValid else { return nil }
            self = .midiOut(m)
        case "macro.run":
            guard let i = id() else { return nil }
            self = .runMacro(i)
        case "wait":
            guard let s = o["seconds"]?.numberValue, s.isFinite, s >= 0 else { return nil }
            self = .wait(seconds: s)
        default:
            return nil
        }
    }

    var json: CueJSON {
        func obj(_ kind: String, _ extra: [String: CueJSON] = [:]) -> CueJSON {
            var d = extra
            d["kind"] = .string(kind)
            return .object(d)
        }
        func uuid(_ u: UUID) -> CueJSON { .string(u.uuidString.lowercased()) }
        switch self {
        case .transport(let t):
            switch t {
            case .next: return obj("transport.next")
            case .previous: return obj("transport.previous")
            case .goToSlide(let i): return obj("transport.goToSlide", ["index": .number(Double(i))])
            case .clear: return obj("transport.clear")
            case .clearAll: return obj("transport.clearAll")
            case .blackout(let m): return obj("transport.blackout", ["mode": .string(m.rawValue)])
            case .stop: return obj("transport.stop")
            }
        case .selectLook(let i): return obj("look.select", ["id": uuid(i)])
        case .prop(let i, let on): return obj("prop.set", ["id": uuid(i), "on": .bool(on)])
        case .showMessage(let i, let f): return obj("message.show", ["id": uuid(i), "fields": .object(f.mapValues { .string($0) })])
        case .hideMessage(let i): return obj("message.hide", ["id": uuid(i)])
        case .startTimer(let i): return obj("timer.start", ["id": uuid(i)])
        case .pauseTimer(let i): return obj("timer.pause", ["id": uuid(i)])
        case .resetTimer(let i): return obj("timer.reset", ["id": uuid(i)])
        case .playForeground(let a): return obj("media.playForeground", ["assetID": uuid(a)])
        case .setBackground(let a): return obj("media.setBackground", ["assetID": a.map(uuid) ?? .null])
        case .stopForeground: return obj("media.stopForeground")
        case .playAudio(let a): return obj("audio.play", ["assetID": uuid(a)])
        case .stopAudio(let a): return obj("audio.stop", ["assetID": uuid(a)])
        case .midiOut(let m):
            let (type, ch, d1, d2): (String, Int, Int, Int)
            switch m {
            case .noteOn(let c, let n, let v): (type, ch, d1, d2) = ("noteOn", c, n, v)
            case .noteOff(let c, let n, let v): (type, ch, d1, d2) = ("noteOff", c, n, v)
            case .controlChange(let c, let n, let v): (type, ch, d1, d2) = ("controlChange", c, n, v)
            case .programChange(let c, let p): (type, ch, d1, d2) = ("programChange", c, p, 0)
            }
            return obj("midi.out", ["type": .string(type), "channel": .number(Double(ch)),
                                    "data1": .number(Double(d1)), "data2": .number(Double(d2))])
        case .runMacro(let i): return obj("macro.run", ["id": uuid(i)])
        case .wait(let s): return obj("wait", ["seconds": .number(s)])
        case .unknown(let raw): return raw
        }
    }
}

/// One entry of `CueActionList.unknownActions`.
public struct UnknownCueAction: Sendable, Equatable, CustomStringConvertible {
    public var index: Int
    public var raw: CueJSON
    public var description: String { raw.objectValue?["kind"]?.stringValue ?? "unrecognised action" }
}

/// A stored list of actions with a format version, so cues saved today still load after the vocabulary grows.
public struct CueActionList: Sendable, Equatable, Codable {
    public static let currentVersion = 1

    public var version: Int
    public var actions: [CueAction]

    public init(actions: [CueAction], version: Int = CueActionList.currentVersion) {
        self.actions = actions
        self.version = version
    }

    /// Actions this version could not read, for a "skipped" report when a cue is loaded.
    public var unknownActions: [UnknownCueAction] {
        actions.enumerated().compactMap { i, a in
            if case .unknown(let raw) = a { return UnknownCueAction(index: i, raw: raw) } else { return nil }
        }
    }

    private enum CodingKeys: String, CodingKey { case version, actions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        actions = try c.decode([CueAction].self, forKey: .actions)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(actions, forKey: .actions)
    }
}
