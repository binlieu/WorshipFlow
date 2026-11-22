// OUT-004: small pieces of interface state that menus and views share (which sheet is open, focus requests).
import Foundation
import Observation
import OperatorCore

/// CUE-002b: what the Cues mode's centre shows.
enum CuesSelection: Hashable {
    case macro(UUID), slideActions, schedule, midi, remote
}

@MainActor
@Observable
final class WorkspaceUIState {
    /// CUE-002b: the macro, the slide actions, the schedule, MIDI or the remote control, in the Cues mode.
    var cuesSelection: CuesSelection?
    /// The slide whose actions the Cues mode edits (an index into the open song).
    var cuesSlideID: UUID?
    /// LIB-004c: the Scripture view takes the centre of Show; Command-J or the sidebar row opens it, opening a song closes it.
    var scriptureOpen = false
    /// Which of the Scripture view's three screens is showing (kept here so a debug run can switch it).
    var scriptureScreen = ScriptureScreen.reference
    /// Bumped by Command-J: the Scripture view puts the cursor in its reference field.
    var focusScripture = 0
    var showImport = false
    /// Set when the import sheet re-flows an existing presentation instead of creating one.
    var importExistingID: UUID?
    /// The popover that deliberately changes the LIVE slide (Option-Command-E). Not the Quick edit tab.
    var showLiveQuickEdit = false
    /// UI-003: the tabs under the Look row (Props, Cues, Audio and, while open, Quick edit).
    var tabs = InspectorTabs()
    /// UI-003: the media dock's tab and the layer a click on a tile acts on.
    var dockTab = MediaDockTab.backgrounds
    var dockLayer = MediaLayerChoice.background
    /// MEDIA-010: the item selected in the Media mode's bin (shown in the sidebar player) and the hot folder it is showing.
    var binSelection: UUID?
    var binFolderID: UUID?
    /// Debug pictures only: draws the entries of the Clear menu as a list, because a real menu popup is a separate window the
    /// snapshot hook cannot capture. Never set in normal use.
    var showClearMenuPreview = false
    /// True while the sidebar search field has keyboard focus (it is a SwiftUI field, not an NSSearchField).
    var searchHasFocus = false
    /// FIX-H item 7: the custom control that has keyboard focus, if one does (a toggle, a slider, a tab...). The controls report it; the
    /// key monitor reads it, so Space, Return and the arrows act on the control and not on the show.
    var focusedControl: FocusedElement?

    /// A control gained or lost keyboard focus. Losing it only counts when that kind is still the one recorded.
    func controlFocus(_ kind: FocusedElement, _ focused: Bool) {
        if focused { focusedControl = kind } else if focusedControl == kind { focusedControl = nil }
    }
    /// Bumped by Command-E: the Quick edit tab puts the cursor in its first field.
    var focusQuickEdit = 0
    /// Counts requests for the live-slide edit (Option-Command-E, the Live button, the Edit header): the popover itself
    /// can only show while the app is the active one, so a debug run reads this to see that the key reached the menu item.
    var liveQuickEditRequests = 0
    /// LIB-005: the program export or import sheet.
    var programSheet: ProgramSheet?
    var showSectionOrders = false
    var showThemeEditor = false
    /// UI-005a: the Show sidebar can be hidden (the toolbar's sidebar button); the two column widths are the design's 256 and 372.
    var sidebarVisible = true
    var sidebarWidth: Double = 256
    var inspectorWidth: Double = 372
    /// The height of the Libraries block over the playlist (the design's 338 pt).
    var libraryHeight: Double = 330
    /// UI-001: the slide grid as thumbnails or as a list.
    var gridAsList = false
    /// UI-002: the screen selected in the Screens mode.
    var selectedScreenID: UUID?
    /// True while anything is open over the workspace, so the transport keys stay out of its way (KI-021).
    var anySheetOpen: Bool { showImport || showLiveQuickEdit || showSectionOrders || showThemeEditor || programSheet != nil }
    /// Counters: a view reacts to a change in the number, so a menu command can ask for focus.
    var focusSearch = 0
    var focusTitle = 0
    /// Bumped by Escape in the search field: clear the search and put keyboard focus on the slide grid.
    var leaveSearch = 0
    var focusGrid = 0
}
