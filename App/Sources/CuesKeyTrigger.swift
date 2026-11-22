// UI-006g (CU-21): the key monitor's side of a macro's function key. The decision is `CueKeyGate` (pure, tested); this only asks the cue
// model, which runs the macro through the one command path like a button does.
import AppKit
import OperatorCore

extension AppModel {
    /// True when the key was a function key that runs a macro: the monitor then swallows it. A key with no macro, a typed key, a key with a
    /// modifier, a repeat, and any key while a text field or a sheet has focus are all left alone.
    func handleCueKeyTrigger(keyCode: UInt16, modifierHeld: Bool, shift: Bool, isRepeat: Bool, focus: FocusedElement, textInput: Bool, sheetOpen: Bool) -> Bool {
        guard let cue else { return false }
        let typing = textInput || focus == .textInput || focus == .searchField
        guard let key = CueKeyGate.key(forKeyCode: keyCode, commandControlOptionDown: modifierHeld, shiftDown: shift, isRepeat: isRepeat,
                                       inTextInput: typing, sheetOpen: sheetOpen) else { return false }
        return cue.runKeyTrigger(key)
    }
}
