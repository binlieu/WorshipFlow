// UI-006g (CU-21) and FIX-V item 1: a macro's function key. The key monitor does not decide anything here: `KeyRouting.decision` routes it
// (`.runMacro`, only in Show and Cues, in the operator window, with no sheet, alert or text field), and this only says what the app tells the
// operator about that rule.
import OperatorCore

enum CuesKeyTrigger {
    /// The help text of the Trigger menu: where a function key works.
    static let keyHelp = "Choose the function key that runs this macro. It works in Show and Cues, when no text field, sheet or dialog has focus; in Edit, Media, Stage and Screens it does nothing."
}
