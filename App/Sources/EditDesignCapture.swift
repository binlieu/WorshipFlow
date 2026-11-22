// UI-005c (debug builds only): `UI_SNAPSHOT_DESIGN=1 UI_SNAPSHOT_EDIT=1` with the ui-snapshots hook captures the Edit mode at 1440 x 900 points
// in the state of docs/UI/screens/02-editor.png as far as today's data allows: "Amazing Grace" open, slide 3 live, slide 4 being edited,
// one text object on it with the design's frame, size, shadow and weight, selected. The design's two lyric boxes are the theme's words in
// the app (not objects), so the object here is an extra text box that stands for the selected one. Dark and light.
// Run by scripts/design-capture-edit.sh by hand.
#if DEBUG
import AppKit
import SwiftUI
import Domain
import OperatorCore

extension AppModel {
    func runEditDesignScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let workspace, let editor = slideEditor else { note("edit design: no workspace or editor"); return }
        workspace.setMode(.edit)
        workspace.selectSlide(3)
        try? await Task.sleep(for: .milliseconds(600))
        if let id = editor.add(.textBox) {
            editor.setText(id, "My God, my Savior\nhas ransomed me")
            editor.setFrame(id, x: 0.12, y: 0.27, width: 0.76, height: 0.28)
            editor.setFontSize(id, 72)
            editor.setTextColor(id, .white)
            editor.setAlignment(id, .center)
            editor.setVerticalAlignment(id, .center)
            editor.setShadow(id, TextShadow(color: .black, offsetX: 0, offsetY: 4, blur: 16))
            editor.setOutline(id, width: 0, color: ColorRGBA(red: 0.024, green: 0.129, blue: 0.220))
            editor.edit(id, key: "weight") { object in if case .text(var t) = object.content { t.style.weight = 600; object.content = .text(t) } }
            editor.select(id)
        }
        note("edit design: slide \(workspace.show.selectedIndex + 1) of \(workspace.slides.count), live \(workspace.show.liveIndex.map { String($0 + 1) } ?? "-"), object \(editor.selectedObjectID != nil)")
        setAppearance(.dark)
        await capture("edit-dark")
        setAppearance(.light)
        await capture("edit-light")
        setAppearance(.dark)
        // The other tabs, and the inspector with a shape and with nothing selected (not in the design: looked at, not measured).
        for tab in ["slide", "theme"] {
            NotificationCenter.default.post(name: .init("wf.debug.editTab"), object: tab)
            await capture("edit-\(tab)-tab-dark")
        }
        NotificationCenter.default.post(name: .init("wf.debug.editTab"), object: "object")
        if let shape = editor.add(.roundedRectangle) { editor.setFrame(shape, x: 0.1, y: 0.62, width: 0.3, height: 0.25); editor.select(shape) }
        await capture("edit-shape-dark")
        editor.select(nil)
        await capture("edit-nosel-dark")
    }
}
#endif
