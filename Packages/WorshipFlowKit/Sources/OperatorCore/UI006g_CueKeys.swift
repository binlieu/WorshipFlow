// UI-006g (CU-21): a function key that runs a macro. The key table, the one-key-one-macro rule, the gate the key monitor asks, and the
// model's save and run. Stored in the library's app state (key "cue.macro.keys"), so it needs no schema change. Foundation and CueEngine only.
import Foundation
import CueEngine

/// F1 to F12. They are not used by any other key of the show (a test checks `ShowShortcuts`), and a function key is never typed text.
public enum CueFunctionKey: Int, CaseIterable, Sendable, Equatable, Hashable, Identifiable {
    case f1 = 1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12

    public var id: Int { rawValue }
    public var label: String { "F\(rawValue)" }

    /// macOS virtual key codes (kVK_F1 ... kVK_F12).
    public var keyCode: UInt16 {
        switch self {
        case .f1: 122; case .f2: 120; case .f3: 99; case .f4: 118; case .f5: 96; case .f6: 97
        case .f7: 98; case .f8: 100; case .f9: 101; case .f10: 109; case .f11: 103; case .f12: 111
        }
    }

    public init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    public init?(label: String) {
        guard let key = Self.allCases.first(where: { $0.label == label }) else { return nil }
        self = key
    }
}

/// Which function key runs which macro. A key belongs to one macro and a macro has one key.
public struct CueKeyTriggers: Sendable, Equatable, Codable {
    public static let currentVersion = 1
    private var byMacro: [UUID: CueFunctionKey]

    public init() { byMacro = [:] }

    public var isEmpty: Bool { byMacro.isEmpty }

    public func key(for macro: UUID) -> CueFunctionKey? { byMacro[macro] }

    /// The macro that holds `key`, if it is still among `existing`.
    public func macroID(for key: CueFunctionKey, existing: Set<UUID>) -> UUID? {
        byMacro.first { $0.value == key && existing.contains($0.key) }?.key
    }

    /// The macro that holds `key`, whether or not it still exists (for the "now used by" text).
    public func holder(of key: CueFunctionKey) -> UUID? { byMacro.first { $0.value == key }?.key }

    /// Gives `key` to the macro, taking it from any other macro. Nil clears the macro's key.
    public mutating func assign(_ key: CueFunctionKey?, to macro: UUID) {
        byMacro[macro] = nil
        guard let key else { return }
        byMacro = byMacro.filter { $0.value != key }
        byMacro[macro] = key
    }

    /// Without the keys of macros that are gone.
    public func pruned(keeping existing: Set<UUID>) -> CueKeyTriggers {
        var copy = self
        copy.byMacro = byMacro.filter { existing.contains($0.key) }
        return copy
    }

    private struct Entry: Codable { var macro: UUID; var key: String }
    private enum CodingKeys: String, CodingKey { case version, keys }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try c.decodeIfPresent([Entry].self, forKey: .keys) ?? []
        byMacro = [:]
        for e in entries { if let key = CueFunctionKey(label: e.key) { assign(key, to: e.macro) } }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        let entries = byMacro.sorted { $0.value.rawValue < $1.value.rawValue }.map { Entry(macro: $0.key, key: $0.value.label) }
        try c.encode(entries, forKey: .keys)
    }
}

/// What the key monitor asks before it hands a key to the model: only a bare function key, pressed once, outside text fields and sheets.
public enum CueKeyGate {
    public static func key(forKeyCode code: UInt16, commandControlOptionDown: Bool, shiftDown: Bool, isRepeat: Bool,
                           inTextInput: Bool, sheetOpen: Bool) -> CueFunctionKey? {
        guard !commandControlOptionDown, !shiftDown, !isRepeat, !inTextInput, !sheetOpen else { return nil }
        return CueFunctionKey(keyCode: code)
    }
}

/// The text of the Trigger field in a macro's bar.
public enum CueTriggerText {
    /// "F1 · MIDI Note C2", "MIDI Note C2, CC 7", "F4" or "none". `midi` is each pad as `MIDIText.pattern` writes it.
    public static func summary(key: CueFunctionKey?, midi: [String]) -> String {
        var parts: [String] = []
        if let key { parts.append(key.label) }
        if !midi.isEmpty { parts.append("MIDI " + midi.joined(separator: ", ")) }
        return parts.isEmpty ? "none" : parts.joined(separator: " \u{00B7} ")
    }
}

extension CueModel {
    static let keyTriggersKey = "cue.macro.keys"

    /// Reads the saved keys (called by `start()`); a key whose macro is gone is dropped.
    func loadKeyTriggers() async {
        guard let settingsStore, let text = try? await settingsStore.state(for: Self.keyTriggersKey) else { return }
        guard let triggers = try? JSONDecoder().decode(CueKeyTriggers.self, from: Data(text.utf8)) else {
            // FIX-V item 6 (L3): text that cannot be read is kept under its own key before a later change replaces it.
            try? await settingsStore.setState(text, for: Self.keyTriggersKey + ".unreadable")
            note("The saved macro keys could not be read, so no macro has a key. The damaged text was kept.")
            return
        }
        let kept = triggers.pruned(keeping: Set(macros.map(\.id)))
        keyTriggers = kept
        // The first prune (in `reload`) ran before the keys were read and saw none: a key of a macro that is gone leaves the store here.
        if kept != triggers { await save(kept, key: Self.keyTriggersKey) }
    }

    /// Gives the macro this key (nil clears it) and remembers it. The key moves if another macro had it.
    public func setKey(_ key: CueFunctionKey?, for macro: UUID) async {
        guard library.macro(id: macro) != nil else { return }
        keyTriggers.assign(key, to: macro)
        await save(keyTriggers, key: Self.keyTriggersKey)
    }

    /// Runs the macro that holds this key. False when none does, so the key is left to the app.
    @discardableResult
    public func runKeyTrigger(_ key: CueFunctionKey) -> Bool {
        guard let id = keyTriggers.macroID(for: key, existing: Set(macros.map(\.id))) else { return false }
        submit(.runMacro(id), from: .key)
        return true
    }

    /// Forgets the keys of macros that no longer exist, and saves if that changed anything.
    func pruneKeyTriggers() async {
        let kept = keyTriggers.pruned(keeping: Set(macros.map(\.id)))
        guard kept != keyTriggers else { return }
        keyTriggers = kept
        await save(kept, key: Self.keyTriggersKey)
    }
}
