// CUE-001 (AUTO-03): which incoming MIDI message runs which command. Foundation only.
import Foundation

/// What a binding does: any transport command, or a macro.
public enum MIDICommand: Sendable, Equatable, Hashable, Codable {
    case transport(CueTransport)
    case macro(UUID)

    public var actions: [CueAction] {
        switch self {
        case .transport(let t): return [.transport(t)]
        case .macro(let id): return [.runMacro(id)]
        }
    }
}

/// A message shape. `channel` and `number` nil mean "any". `valueRange` limits the velocity of a note or the value of
/// a control change (ignored for program change). Note-off never matches: releasing a pad does nothing.
public struct MIDIPattern: Sendable, Equatable, Hashable, Codable {
    public enum Kind: String, Sendable, Equatable, Hashable, Codable { case noteOn, controlChange, programChange }

    public var kind: Kind
    public var channel: Int?
    public var number: Int?
    public var valueRange: ClosedRange<Int>?

    public init(kind: Kind, channel: Int? = nil, number: Int? = nil, valueRange: ClosedRange<Int>? = nil) {
        self.kind = kind
        self.channel = channel
        self.number = number
        self.valueRange = valueRange
    }

    public var isValid: Bool {
        if let c = channel, !(1...16).contains(c) { return false }
        if let n = number, !(0...127).contains(n) { return false }
        if let r = valueRange {
            if kind == .programChange { return false }
            if r.lowerBound < 0 || r.upperBound > 127 { return false }
        }
        return true
    }

    /// The values this pattern accepts: a note-on has velocity 1 to 127 (zero is a note-off).
    private var effectiveValues: ClosedRange<Int>? {
        switch kind {
        case .programChange: return 0...127
        case .noteOn: return (valueRange ?? 1...127).clamped(to: 1...127)
        case .controlChange: return (valueRange ?? 0...127).clamped(to: 0...127)
        }
    }

    /// Everything but the value.
    func matchesSource(_ m: MIDIMessage) -> Bool {
        guard m.isValid else { return false }
        let (ch, num): (Int, Int)
        switch (kind, m) {
        case (.noteOn, .noteOn(let c, let n, _)): (ch, num) = (c, n)
        case (.controlChange, .controlChange(let c, let n, _)): (ch, num) = (c, n)
        case (.programChange, .programChange(let c, let p)): (ch, num) = (c, p)
        default: return false
        }
        return (channel == nil || channel == ch) && (number == nil || number == num)
    }

    public func matches(_ m: MIDIMessage) -> Bool {
        guard matchesSource(m) else { return false }
        switch m {
        case .noteOn(_, _, let v), .controlChange(_, _, let v):
            return effectiveValues?.contains(v) ?? false
        default:
            return true
        }
    }

    /// True when some message could match both patterns.
    public func overlaps(_ other: MIDIPattern) -> Bool {
        guard kind == other.kind else { return false }
        if let a = channel, let b = other.channel, a != b { return false }
        if let a = number, let b = other.number, a != b { return false }
        guard let r1 = effectiveValues, let r2 = other.effectiveValues else { return false }
        return r1.overlaps(r2)
    }

    /// The pattern a "learn" would create from a message: exact channel and number, any value. Releases and invalid
    /// messages cannot be learned.
    public static func learned(from m: MIDIMessage) -> MIDIPattern? {
        guard m.isValid else { return nil }
        switch m {
        case .noteOn(let c, let n, let v): return v > 0 ? MIDIPattern(kind: .noteOn, channel: c, number: n) : nil
        case .noteOff: return nil
        case .controlChange(let c, let n, _): return MIDIPattern(kind: .controlChange, channel: c, number: n)
        case .programChange(let c, let p): return MIDIPattern(kind: .programChange, channel: c, number: p)
        }
    }
}

private extension ClosedRange where Bound == Int {
    /// The intersection with `limit`, or nil when empty.
    func clamped(to limit: ClosedRange<Int>) -> ClosedRange<Int>? {
        let lo = Swift.max(lowerBound, limit.lowerBound), hi = Swift.min(upperBound, limit.upperBound)
        return lo <= hi ? lo...hi : nil
    }
}

public struct MIDIBinding: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var pattern: MIDIPattern
    public var command: MIDICommand

    public init(id: UUID = UUID(), name: String, pattern: MIDIPattern, command: MIDICommand) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.command = command
    }
}

public struct MIDIConflict: Sendable, Equatable, Hashable {
    public var first: UUID
    public var second: UUID
    public init(first: UUID, second: UUID) { self.first = first; self.second = second }
}

public struct MIDIBindingSet: Sendable, Equatable, Codable {
    public var bindings: [MIDIBinding]

    public init(bindings: [MIDIBinding] = []) { self.bindings = bindings }

    /// The first binding, in list order, whose pattern matches.
    public func binding(for message: MIDIMessage) -> MIDIBinding? {
        bindings.first { $0.pattern.matches(message) }
    }

    public func command(for message: MIDIMessage) -> MIDICommand? { binding(for: message)?.command }

    /// Every pair of bindings that one message could trigger together, each pair once, in list order.
    public func conflicts() -> [MIDIConflict] {
        var out: [MIDIConflict] = []
        for i in bindings.indices {
            for j in bindings.indices where j > i && bindings[i].pattern.overlaps(bindings[j].pattern) {
                out.append(MIDIConflict(first: bindings[i].id, second: bindings[j].id))
            }
        }
        return out
    }

    /// Existing bindings (other than the candidate itself) that the candidate would collide with.
    public func conflicts(with candidate: MIDIBinding) -> [MIDIBinding] {
        bindings.filter { $0.id != candidate.id && $0.pattern.overlaps(candidate.pattern) }
    }
}

/// "Learn": the next usable message received while armed becomes a pattern.
public struct MIDILearner: Sendable {
    public private(set) var isArmed = false
    public init() {}
    public mutating func arm() { isArmed = true }
    public mutating func cancel() { isArmed = false }

    public mutating func feed(_ message: MIDIMessage) -> MIDIPattern? {
        guard isArmed, let p = MIDIPattern.learned(from: message) else { return nil }
        isArmed = false
        return p
    }
}

/// Stops one physical action from running a command many times. Feed it every received message.
///
/// - A note-on binding fires once; further note-ons for the same pad are held back until its note-off (or a note-on
///   with velocity zero). If the note-off is lost, the pad works again after `noteStaleAfter` seconds of silence.
/// - A control-change binding fires when the value enters its range; values that stay in the range are held back. The
///   value leaving the range re-arms it, and so does `ccRepeatWindow` seconds without a message (for controllers that
///   send the same value on every press and nothing on release).
/// - A program change fires every time.
/// - A note-off never fires anything.
public struct MIDICommandFilter: Sendable {
    public var noteStaleAfter: TimeInterval
    public var ccRepeatWindow: TimeInterval

    private struct Key: Hashable { var binding: UUID; var channel: Int; var number: Int }
    private var active: [Key: TimeInterval] = [:]

    public init(noteStaleAfter: TimeInterval = 5, ccRepeatWindow: TimeInterval = 0.3) {
        self.noteStaleAfter = noteStaleAfter
        self.ccRepeatWindow = ccRepeatWindow
    }

    public mutating func reset() { active = [:] }

    private func isFresh(_ key: Key, at now: TimeInterval, within window: TimeInterval) -> Bool {
        guard let last = active[key] else { return false }
        let gap = now - last
        return gap >= 0 && gap < window
    }

    private mutating func release(channel: Int, number: Int) {
        for k in active.keys where k.channel == channel && k.number == number { active[k] = nil }
    }

    public mutating func command(for message: MIDIMessage, in set: MIDIBindingSet, at now: TimeInterval) -> MIDICommand? {
        guard message.isValid else { return nil }
        switch message {
        case .noteOff(let ch, let n, _), .noteOn(let ch, let n, 0):
            release(channel: ch, number: n)
            return nil

        case .noteOn(let ch, let n, _):
            guard let b = set.binding(for: message) else { return nil }
            let key = Key(binding: b.id, channel: ch, number: n)
            if isFresh(key, at: now, within: noteStaleAfter) {
                active[key] = now          // a repeat: still held
                return nil
            }
            active[key] = now
            return b.command

        case .controlChange(let ch, let n, _):
            // Bindings for this controller whose range the value is outside of are released.
            for b in set.bindings where b.pattern.kind == .controlChange && b.pattern.matchesSource(message) && !b.pattern.matches(message) {
                active[Key(binding: b.id, channel: ch, number: n)] = nil
            }
            guard let b = set.binding(for: message) else { return nil }
            let key = Key(binding: b.id, channel: ch, number: n)
            if isFresh(key, at: now, within: ccRepeatWindow) {
                active[key] = now
                return nil
            }
            active[key] = now
            return b.command

        case .programChange:
            return set.command(for: message)
        }
    }
}
