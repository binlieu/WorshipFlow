// UI-005e: Stage mode.
import SwiftUI

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
