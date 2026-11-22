// UI-006e (debug builds only): after the Stage design scenario, with UI_SNAPSHOT_STAGE_FEATURES set: hides the Notes element of the Band layout,
// turns Auto-fit on for its current slide, colours the second language, makes the three presets, takes a picture and logs what the stage screen's
// scene holds (so a hidden element is seen to be absent). Works on the model; the controls themselves are exercised by hand (see the report).
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import OperatorCore

extension AppModel {
    func runStageFeaturesScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void) async {
        guard let stage, let band = stage.customLayouts.first(where: { $0.name == "Band" }) else { note("stagefeatures: no Band layout"); return }
        if let notes = band.elements.first(where: { $0.kind == .notes }) { stage.setHidden(true, for: notes.id, in: band.id) }
        if let current = band.elements.first(where: { $0.kind == .currentSlide }) {
            stage.setAutoFit(true, for: current.id, in: band.id)
            stage.setSecondLanguageColor(ColorRGBA(red: 0.3, green: 0.9, blue: 0.5), for: current.id, in: band.id)
        }
        for preset in StagePreset.allCases { _ = stage.addPreset(preset, named: "Preset " + preset.title) }
        let layout = stage.layout(withID: band.id) ?? band
        let scene = stage.sampleScene(for: layout)
        note("stagefeatures: hidden=\(layout.elements.filter(\.isHidden).count) autoFit=\(layout.elements.filter(\.autoFit).count) layers=\(scene.textLayers.map(\.text)) fitFloors=\(scene.textLayers.compactMap(\.fitFloor)) presets=\(stage.customLayouts.map(\.name))")
        try? await Task.sleep(for: .seconds(1))
        await capture("stage-features-dark")
    }
}
#endif
