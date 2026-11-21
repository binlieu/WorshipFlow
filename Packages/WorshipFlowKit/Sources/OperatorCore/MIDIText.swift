// CUE-002b (item 4): how MIDI patterns and commands read in the interface. Foundation and CueEngine only.
import Foundation
import CueEngine

public enum MIDIText {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// Middle C (note 60) is C4.
    public static func noteName(_ note: Int) -> String {
        guard (0...127).contains(note) else { return "?" }
        return "\(names[note % 12])\(note / 12 - 1)"
    }

    public static func pattern(_ p: MIDIPattern) -> String {
        var text: String
        switch p.kind {
        case .noteOn: text = p.number.map { "Note \(noteName($0))" } ?? "Any note"
        case .controlChange: text = p.number.map { "CC \($0)" } ?? "Any controller"
        case .programChange: text = p.number.map { "Program \($0)" } ?? "Any program"
        }
        if let c = p.channel { text += " \u{00B7} ch \(c)" }
        if let r = p.valueRange, p.kind != .programChange { text += " \u{00B7} \(r.lowerBound)\u{2013}\(r.upperBound)" }
        return text
    }

    public static func command(_ c: MIDICommand, macros: [Macro]) -> String {
        switch c {
        case .transport(let t): return t.summary
        case .macro(let id): return "Macro \u{00B7} \(macros.first { $0.id == id }?.name ?? "(deleted)")"
        }
    }
}
