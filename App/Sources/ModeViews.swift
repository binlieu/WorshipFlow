// UI-001 / ADR-0007: the Edit, Media, Stage, Cues and Screens modes. Each re-homes panels that already worked; none
// of them carries new logic.
import SwiftUI
import Domain
import OperatorCore

// MARK: Edit

// UI-005c: EditModeView moved to EditMode.swift.

// MARK: Stage

struct StageModeView: View {
    let app: AppModel

    var body: some View {
        if let stage = app.stage {
            StageEditorView(app: app, stage: stage)
        } else {
            Text("Stage layouts are not available.").foregroundStyle(Tok.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
