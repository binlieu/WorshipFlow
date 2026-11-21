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
    /// Counters: a view reacts to a change in the number, so a menu command can ask for focus.
    var focusSearch = 0
    var focusTitle = 0
}
