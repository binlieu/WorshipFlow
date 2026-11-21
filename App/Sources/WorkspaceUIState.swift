// OUT-004: small pieces of interface state that menus and views share (which sheet is open, focus requests).
import Foundation
import Observation
import OperatorCore

@MainActor
@Observable
final class WorkspaceUIState {
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
    /// True while the sidebar search field has keyboard focus (it is a SwiftUI field, not an NSSearchField).
    var searchHasFocus = false
    /// Bumped by Command-E: the Quick edit tab puts the cursor in its first field.
    var focusQuickEdit = 0
    /// Counts requests for the live-slide edit (Option-Command-E, the Live button, the Edit header): the popover itself
    /// can only show while the app is the active one, so a debug run reads this to see that the key reached the menu item.
    var liveQuickEditRequests = 0
    var showSectionOrders = false
    var showThemeEditor = false
    /// UI-001: the slide grid as thumbnails or as a list.
    var gridAsList = false
    /// UI-002: the screen selected in the Screens mode.
    var selectedScreenID: UUID?
    /// True while anything is open over the workspace, so the transport keys stay out of its way (KI-021).
    var anySheetOpen: Bool { showImport || showLiveQuickEdit || showSectionOrders || showThemeEditor }
    /// Counters: a view reacts to a change in the number, so a menu command can ask for focus.
    var focusSearch = 0
    var focusTitle = 0
    /// Bumped by Escape in the search field: clear the search and put keyboard focus on the slide grid.
    var leaveSearch = 0
    var focusGrid = 0
}
