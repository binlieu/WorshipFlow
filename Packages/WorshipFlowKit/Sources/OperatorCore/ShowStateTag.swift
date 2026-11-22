// FIX-N item 3: the quiet state tag in the operator toolbar. The red LIVE chip is gone (owner: too busy); this adds back less: a small amber
// word, present only while the screens are blacked out or cleared, so an operator who pressed B in Edit, Stage or Screens sees that it
// happened. Nothing is shown while the show is plainly live or stopped. Foundation and Domain only.
import Foundation
import Domain

public enum ShowStateTag {
    /// "BLACKOUT" while blacked out (it wins over a clear that is waiting underneath), "CLEARED" while the words are cleared, else nil.
    public static func text(for show: ShowState) -> String? {
        if show.isBlackedOut { return "BLACKOUT" }
        if show.isCleared { return "CLEARED" }
        return nil
    }
}
