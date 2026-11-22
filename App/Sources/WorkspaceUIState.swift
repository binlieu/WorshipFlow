// OUT-004: small pieces of interface state that menus and views share (which sheet is open, focus requests).
import Foundation
import Observation
import Domain
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
    /// FIX-I item 2: which section the arrow keys act on (the slide grid or the media bin: whichever was clicked last), and how many columns each
    /// draws, so Up and Down step a row.
    var keySection = KeySection.slideGrid
    var gridColumns = 5
    var binColumns = 1
    func keySectionEvent(_ event: KeySection.Event) { keySection = KeySection.after(event, from: keySection) }
    var binFolderID: UUID?
    /// True while the sidebar search field has keyboard focus (it is a SwiftUI field, not an NSSearchField).
    var searchHasFocus = false
    /// FIX-H item 7: the custom control that has keyboard focus, if one does (a toggle, a slider, a tab...). The controls report it; the
    /// key monitor reads it, so Space, Return and the arrows act on the control and not on the show.
    var controlFocusTracker = ControlFocusTracker()
    /// FIX-N item 7: "Apply to all slides in this song" was chosen for this language; the window asks "Apply this position to N slides?" before it applies.
    var applyLyricToAll: LyricBox?
    /// FIX-N item 8: the last mouse press was on a canvas box (Stage or Edit). Reset by every mouse press in the window, set again by the canvas's own.
    @ObservationIgnored var canvasLastClicked = false
    /// FIX-N item 8: the Stage canvas has an editable layout with a box selected (the arrows nudge it), and what an arrow or its release does there.
    @ObservationIgnored var stageTakesArrows = false
    @ObservationIgnored var stageArrow: ((Int, Int, Bool) -> Bool)?
    @ObservationIgnored var stageArrowReleased: (() -> Void)?
    /// FIX-I item 1: true while the slide grid's own focusable container has focus (set by the workspace view). The controls under it
    /// inherit that focus in SwiftUI's environment; the tracker ignores them meanwhile.
    var gridHasFocus = false
    var focusedControl: FocusedElement? { controlFocusTracker.current(gridHasFocus: gridHasFocus) }

    /// A control gained or lost keyboard focus.
    func controlFocus(id: UUID, _ kind: FocusedElement, _ focused: Bool) { controlFocusTracker.report(id: id, kind: kind, focused: focused) }
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
