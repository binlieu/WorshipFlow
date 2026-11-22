// FIX-K items 5 and 6: what the operator window's toolbar holds, in order, for each mode. Foundation only.
// The owner's words (2026-11-21, on build 115): "remove live red on the top right corner. it looks too busy" (Edit, Stage, Screens) and "align all top tabs to
// the left". Both overrule the design picture. The AUD, STG and BRD pills keep showing each screen's state; keyboard transport works in every mode.
import Foundation

public enum ToolbarItem: Equatable, Sendable {
    case windowButtons, sidebarToggle, titleBlock, modeSwitcher, timers, pills
    /// The red LIVE (or CLEARED, BLACKOUT) chip with the live slide's words. Never in the toolbar any more; the transport bar carries it where there is one.
    case liveChip
}

public enum ToolbarLayout {
    /// The mode switcher follows the title block directly, in every mode.
    public static let switcherIsLeading = true

    public static func items(for mode: WorkspaceMode) -> [ToolbarItem] {
        [.windowButtons, .sidebarToggle, .titleBlock, .modeSwitcher, .timers, .pills]
    }
}
