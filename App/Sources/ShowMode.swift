// UI-001 / UI-003 / ADR-0007: the Show mode, design revision 2. Library, search and playlist on the left; the slide grid
// over the media dock in the middle; Preview and Live monitors, the other screens, Looks, tabs (Props, Cues, Audio and
// Quick edit) and the stage message on the right. Everything here is an existing panel re-homed; the decisions live in
// OperatorCore.
import SwiftUI
import Domain
import OutputEngine
import OperatorCore

struct ShowModeView: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel
    @Binding var query: String
    /// Keyboard focus belongs on the slide grid, so the transport keys never land in a text field by accident (KI-021).
    var gridFocused: FocusState<Bool>.Binding
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        HSplitView {
            LibrarySidebar(app: app, workspace: workspace, query: $query, searchFocused: searchFocused)
                .frame(minWidth: 240, idealWidth: Space.sidebarWidth, maxWidth: 276)
            ShowCentre(app: app, workspace: workspace)
                .frame(minWidth: 460)
                .focusable().focused(gridFocused).focusEffectDisabled()
                .onChange(of: workspace.openPresentationID) { _, new in if new != nil { app.ui.scriptureOpen = false } }     // opening a song closes the passage view
            ShowInspector(app: app, workspace: workspace)
                .frame(minWidth: 320, idealWidth: Space.inspectorWidth, maxWidth: 380)
        }
    }
}

/// The slide grid over the media dock.
struct ShowCentre: View {
    let app: AppModel
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if app.ui.scriptureOpen || workspace.centreShowsScripture, let scripture = app.scripture {
                    ScriptureView(app: app, workspace: workspace, scripture: scripture)      // LIB-004c
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    CentrePane(app: app, workspace: workspace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let media = app.media {
                    MediaDockView(app: app, media: media, audio: app.audio, available: geo.size.height)
                }
            }
        }
    }
}
