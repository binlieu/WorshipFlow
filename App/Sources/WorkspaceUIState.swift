// OUT-004: small pieces of interface state that menus and views share (which sheet is open, focus requests).
import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceUIState {
    var showImport = false
    /// Set when the import sheet re-flows an existing presentation instead of creating one.
    var importExistingID: UUID?
    var showQuickEdit = false
    var showSectionOrders = false
    var showThemeEditor = false
    var showStageEditor = false
    /// SLIDE-001b: what the editor under the slide grid shows, the slide's words or its objects.
    enum EditorMode: String, CaseIterable, Identifiable {
        case words = "Words", objects = "Objects"
        var id: String { rawValue }
    }
    var editorMode = EditorMode.words
    /// True while anything is open over the workspace, so the transport keys stay out of its way (KI-021).
    var anySheetOpen: Bool { showImport || showQuickEdit || showSectionOrders || showThemeEditor || showStageEditor }
    /// Counters: a view reacts to a change in the number, so a menu command can ask for focus.
    var focusSearch = 0
    var focusTitle = 0
    /// Bumped by Escape in the search field: clear the search and put keyboard focus on the slide grid.
    var leaveSearch = 0
    var focusGrid = 0
}
