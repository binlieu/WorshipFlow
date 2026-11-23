// FIX-U: the Show inspector's pinned bottom row (Edit live slide, the live background override, Configure) as a view of its own. Whether it shows depends on
// whether words are live, so Clear and a Go Live that lifts it wake this view and not the whole inspector (`ShowInspector`'s body read it and rebuilt
// the monitors, the Looks, the tabs and the stage message).
import SwiftUI
import Domain
import OperatorCore

struct ShowSlimRow: View {
    let app: AppModel
    let workspace: WorkspaceModel

    private var showsSlimRow: Bool {
        workspace.showParts.hasLiveWords || app.media?.hasLiveBackgroundOverride == true || app.profiles.filter(\.isEnabled).isEmpty
    }

    var body: some View {
        let _ = BodyProbe.hit("ShowSlimRow")
        // UI-005j: what the design does not draw (Edit live slide, the live background override with Drop, Configure…) sits at the
        // bottom, pinned, in the area the design leaves empty; it takes no space when there is nothing to show.
        if showsSlimRow {
            VStack(spacing: 0) {
                Rectangle().fill(Tok.border).frame(height: 1)
                slimRow.padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Tok.surface)
            }
        }
    }

    /// The row for what the design does not draw but the operator needs: Edit live slide (the one edit that changes Live),
    /// the live background override with Drop, and Configure.
    private var slimRow: some View {
        HStack(spacing: 6) {
            Button { app.requestLiveQuickEdit() } label: {
                HStack(spacing: 5) { Image(systemName: "pencil.and.outline"); Text(QuickEditLabels.liveTitle) }
            }
            .buttonStyle(HeaderButtonStyle(ring: Tok.warning)).fixedSize()
            .disabled(!workspace.showParts.hasLiveWords)
            .help("\(HeaderChrome.Control.editLiveSlide.tooltip)")
            .accessibilityLabel("Edit live slide. Changes what the audience sees now.")
            .popover(isPresented: Binding(get: { app.ui.showLiveQuickEdit }, set: { app.ui.showLiveQuickEdit = $0 }), arrowEdge: .bottom) {
                QuickEditView(workspace: workspace) { app.ui.showLiveQuickEdit = false }
            }
            overrideChip
            Spacer(minLength: 4)
            if app.profiles.filter(\.isEnabled).isEmpty { Text("No screens enabled").font(.wf(11)).foregroundStyle(Tok.muted) }
            Button("Configure…") { workspace.setMode(.screens) }.buttonStyle(HeaderButtonStyle(kind: .ghost))
                .help("Screen settings are in the Screens mode (Command-6)")
        }
    }

    /// Shown while a background chosen in the media bin is on: it replaces every slide's own background on the live screens
    /// (and is never written to the presentation). The button drops it.
    @ViewBuilder private var overrideChip: some View {
        if let media = app.media, media.hasLiveBackgroundOverride {
            let name = media.layerParts.background.flatMap { media.asset($0.selection.assetID)?.name } ?? "a background"
            HStack(spacing: 5) {
                Image(systemName: "film").font(.wf(11)).foregroundStyle(Tok.muted).accessibilityHidden(true)
                Text("Override: \(name)").font(.wf(11)).foregroundStyle(Tok.muted).lineLimit(1).truncationMode(.middle)
                Button("Drop") { media.dropBackgroundOverride() }.buttonStyle(HeaderButtonStyle(compact: true))
                    .help("Drop the live background override and go back to each slide's own background")
                    .accessibilityLabel("Drop the live background override")
            }
            .accessibilityElement(children: .contain)
        }
    }
}
