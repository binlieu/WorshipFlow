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
        HStack(spacing: 0) {
            if app.ui.sidebarVisible {
                LibrarySidebar(app: app, workspace: workspace, query: $query, searchFocused: searchFocused)
                    .padding(.trailing, 1)          // the column's 1 pt border is outside its 255 pt of content, as in ui.css
                    .frame(width: app.ui.sidebarWidth)
                    .wfRect("sidebar")
                    .overlay(alignment: .trailing) { Rectangle().fill(Tok.border).frame(width: 1) }
                ColumnHandle(width: Binding(get: { app.ui.sidebarWidth }, set: { app.ui.sidebarWidth = $0 }), range: 240...380, grows: 1, name: "Sidebar width")
            }
            ShowCentre(app: app, workspace: workspace)
                .frame(minWidth: 460, maxWidth: .infinity)
                .wfRect("main")
                .focusable().focused(gridFocused).focusEffectDisabled()
                .onChange(of: workspace.openPresentationID) { _, new in if new != nil { app.ui.scriptureOpen = false } }     // opening a song closes the passage view
            ColumnHandle(width: Binding(get: { app.ui.inspectorWidth }, set: { app.ui.inspectorWidth = $0 }), range: 320...440, grows: -1, name: "Inspector width")
            ShowInspector(app: app, workspace: workspace)
                .padding(.leading, 1)
                .frame(width: app.ui.inspectorWidth)
                .wfRect("inspector")
                .overlay(alignment: .leading) { Rectangle().fill(Tok.border).frame(width: 1) }
        }
    }
}

/// A 9 pt drag strip on a column edge (the design's resizable columns: sidebar 240-380, inspector 320-440). Keyboard: with the
/// strip focused the arrow keys move it by 8 pt. The visible edge is the 1 pt border the column draws itself.
struct ColumnHandle: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// +1 when dragging right widens the column (the sidebar), -1 when dragging left widens it (the inspector).
    let grows: Double
    let name: String
    @State private var start: Double?

    var body: some View {
        Color.clear.frame(width: 0)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { drag in
                            if start == nil { start = width }
                            width = min(max((start ?? width) + grows * Double(drag.translation.width), range.lowerBound), range.upperBound)
                        }
                        .onEnded { _ in start = nil })
                    .accessibilityElement()
                    .accessibilityLabel(name)
                    .accessibilityValue("\(Int(width)) points")
                    .accessibilityAdjustableAction { direction in
                        width = min(max(width + (direction == .increment ? 8 : -8), range.lowerBound), range.upperBound)
                    }
            }
            .zIndex(1)
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
