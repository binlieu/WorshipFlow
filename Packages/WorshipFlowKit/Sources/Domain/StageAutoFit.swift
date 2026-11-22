// UI-006e: Auto-fit for a stage element. The compositor (FIX-J) already shrinks text that has a fit floor until it fits its frame; this says
// which floor an element gets. Foundation only.
import Foundation

public enum StageAutoFit {
    /// The design's minimum lyric size, in points at 1080 lines.
    public static let lyricMinimum = 64.0

    /// The smallest size auto-fit takes the element's text to. The current slide never goes below the lyric minimum (and never above its own size, so a
    /// lyric set smaller than that is left as it is); other elements may go to half their size, not below 24.
    public static func floor(for element: StageElement) -> Double {
        let size = element.style.fontSize
        guard size.isFinite, size > 0 else { return 24 }
        switch element.kind {
        case .currentSlide: return min(lyricMinimum, size)
        default: return min(size, max(24, size * 0.5))
        }
    }

    /// True when a current-slide element is set below the lyric minimum: it is drawn as set, and is hard to read from the back of the room.
    public static func isBelowLyricMinimum(_ element: StageElement) -> Bool {
        element.kind == .currentSlide && element.style.fontSize < lyricMinimum
    }
}
