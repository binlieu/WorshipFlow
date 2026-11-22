// UI-005e (debug builds only): the Stage mode captured at the design's size (1440 x 900 points, 2x) in the state of `04-stage.png`:
// a layout named Band whose elements sit where the design draws them (percent of the screen: current 4/9/66/42, next 4/60/66/22,
// clock 74/9/22/15, timer 74/32/22/19, notes where the design draws its Section, message 4/87/92/10), two more layouts, the stage message
// sent, the first element selected. Run with `UI_SNAPSHOT_STAGE=1` together with the design seed (`UI_SNAPSHOT_DESIGN=1`); written as
// `<prefix>-stage-dark.png` / `-stage-light.png` with their `.rects.json`. Sample content is plain data; nothing is stored in a real library.
#if DEBUG
import AppKit
import Domain
import OperatorCore

/// Read once by the Stage mode when it appears: the name of the layout to open (the capture opens Band).
@MainActor enum StageDesignSeed { static var openLayoutName: String? }

extension AppModel {
    func runStageDesignScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void, window: NSWindow?) async {
        guard let workspace, let stage else { note("stage: no workspace or stage model"); return }
        func frame(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ id: UUID, _ layout: UUID) {
            stage.setFrame(id, in: layout, x: x / 100, y: y / 100, width: w / 100, height: h / 100)
        }
        if let band = stage.createLayout(name: "Band") {
            stage.renameLayout(band.id, to: "Band")
            let ids = band.elements.map(\.id)
            if ids.count >= 4 {
                frame(4, 9, 66, 42, ids[0], band.id); frame(4, 60, 66, 22, ids[1], band.id)
                frame(74, 9, 22, 15, ids[2], band.id); frame(74, 32, 22, 19, ids[3], band.id)
            }
            if let notes = stage.addElement(.notes, to: band.id) { frame(74, 60, 22, 22, notes, band.id) }
            if let message = stage.addElement(.message, to: band.id) { frame(4, 87, 92, 10, message, band.id) }
            if let screen = profiles.first(where: { $0.role == .stage }) {
                stage.setLayout(band.id, forScreen: screen.id)
                var p = screen; p.name = "Confidence"; updateProfile(p)
            }
        }
        _ = stage.createLayout(name: "Speaker")
        _ = stage.createLayout(name: "Clock only")
        stage.sendMessage("Repeat chorus ×2, then bridge")
        StageDesignSeed.openLayoutName = "Band"
        window?.setContentSize(NSSize(width: 1440, height: 900))
        window?.center()
        workspace.setMode(.stage)
        try? await Task.sleep(for: .seconds(2))
        setAppearance(.dark)
        await capture("stage-dark")
        setAppearance(.light)
        await capture("stage-light")
        setAppearance(.dark)
        // FIX-K: with UI_SNAPSHOT_STAGE_DRAG the editor is then driven with real mouse events (UISnapshotStageMouse.swift).
        if ProcessInfo.processInfo.environment["UI_SNAPSHOT_STAGE_DRAG"] != nil { await driveStageMouse(note: note, window: window) }
    }
}
#endif
