// FIX-Y (SC-25, SC-31; REVIEW-5 L14): the rule behind a typed note that is kept in a draft and written on Return, when the field is left, or when the
// field goes away (the operator clicked another screen while it still had focus). One place decides whether anything is left to write, so the three
// triggers never write the same text twice. Foundation only.
import Foundation

public enum NoteDraft {
    /// The text to write now, or nil when there is nothing to write. `value` is what the model holds for the screen the field was made for;
    /// `written` is what this field already wrote and the model has not yet reported back.
    public static func pending(draft: String, value: String, written: String?) -> String? {
        draft == (written ?? value) ? nil : draft
    }
}
