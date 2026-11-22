// UI-005g (debug builds only): `UI_SNAPSHOT_CUESDESIGN=1` with `UI_SNAPSHOT_DESIGN=1` and `UI_SNAPSHOT_SDI=1` (see scripts/design-capture.sh)
// captures the Cues mode at 1440 x 900 points in the state of docs/UI/screens/06-cues.png as far as today's data allows: the design's five
// macros (with the design's step counts), a slide action on two slides, seven MIDI bindings and a macro run for the Activity list.
// Pictures and rectangle dumps go through the hook's `capture` (names `cues-dark`, `cues-light`). Sample content is plain data.
#if DEBUG || WF_MEASURE
import AppKit
import Domain
import CueEngine
import OperatorCore

extension AppModel {
    func runCuesDesignScenario(note: @MainActor (String) -> Void, capture: @MainActor (String) async -> Void, window: NSWindow?) async {
        guard let workspace, let cue, let stage else { note("cues-design: no models"); return }
        // The design scenario's own seeding (props, timers, media, playlist) is shared; here only what Cues shows.
        await runDesignScenarioSeed(workspace: workspace)
        guard let look = looks.first(where: { $0.name.contains("Worship") }) ?? looks.first else { note("cues-design: no look"); return }
        let timer = stage.timers.first(where: { $0.name == "Service" }) ?? stage.timers.first
        let prop = props.first
        let video = media?.assets.first(where: { $0.kind == .video })
        guard let timer, let prop else { note("cues-design: no timer or prop"); return }
        // Macro 1: five steps (the design's fourth, "Stage layout", has no action yet: a stage message stands in).
        guard let start = await cue.createMacro(name: "Start worship set") else { note("cues-design: macro failed \(cue.lastError ?? "")"); return }
        await cue.setSteps([.selectLook(look.id), .setBackground(assetID: video?.id), .prop(id: prop.id, isOn: true),
                            .showMessage(id: CueActionEditing.stageMessageID, fields: ["text": "Welcome, we are starting"]), .startTimer(timer.id)], of: start.id)
        let sermon = await cue.createMacro(name: "Sermon mode")
        await cue.setSteps([.selectLook(look.id), .hideMessage(id: CueActionEditing.stageMessageID), .prop(id: prop.id, isOn: false), .resetTimer(timer.id)], of: sermon?.id ?? start.id)
        let baptism = await cue.createMacro(name: "Baptism video")
        await cue.setSteps([.selectLook(look.id), .setBackground(assetID: nil), .prop(id: prop.id, isOn: false), .hideMessage(id: CueActionEditing.stageMessageID),
                            .pauseTimer(timer.id), .wait(seconds: 1)], of: baptism?.id ?? start.id)
        let end = await cue.createMacro(name: "End of service")
        await cue.setSteps([.pauseTimer(timer.id), .prop(id: prop.id, isOn: false), .transport(.blackout(.on))], of: end?.id ?? start.id)
        let emergency = await cue.createMacro(name: "Emergency clear")
        await cue.setSteps([.transport(.clearAll), .transport(.blackout(.on))], of: emergency?.id ?? start.id)
        await cue.setKey(.f1, for: start.id)      // UI-006g: the design's "Trigger: F1 · MIDI note C2"
        // Two slides with an action, the design's "Amazing Grace 2".
        for index in [1, 2] where index < workspace.slides.count {
            try? await cue.setSlideActions([.selectLook(look.id)], for: workspace.slides[index].id)
        }
        // Seven MIDI bindings as the design lists them (the design's "CC 7: Media audio level" has no command here: Stop stands in).
        let rows: [(MIDIPattern, MIDICommand)] = [
            (MIDIPattern(kind: .noteOn, channel: 1, number: 36), .macro(start.id)),
            (MIDIPattern(kind: .noteOn, channel: 1, number: 38), .transport(.next)),
            (MIDIPattern(kind: .noteOn, channel: 1, number: 40), .transport(.previous)),
            (MIDIPattern(kind: .noteOn, channel: 1, number: 41), .transport(.clear)),
            (MIDIPattern(kind: .noteOn, channel: 1, number: 43), .transport(.blackout(.toggle))),
            (MIDIPattern(kind: .controlChange, channel: 1, number: 7), .transport(.stop)),
            (MIDIPattern(kind: .noteOn, channel: 1, number: 45), .macro((emergency ?? start).id)),
        ]
        for (pattern, command) in rows { await cue.saveBinding(MIDIBinding(name: MIDIText.pattern(pattern), pattern: pattern, command: command)) }
        cue.submit(.runMacro(start.id), from: .button)
        await cue.settled()
        window?.setContentSize(NSSize(width: 1440, height: 900))
        window?.center()
        workspace.setMode(.cues)
        ui.cuesSelection = .macro(start.id)
        try? await Task.sleep(for: .seconds(1.5))
        note("cues-design: macros \(cue.macros.count), bindings \(cue.bindings.bindings.count), activity \(cue.activity.count)")
        setAppearance(.dark)
        await capture("cues-dark")
        setAppearance(.light)
        await capture("cues-light")
        setAppearance(.dark)
    }

    /// The shared part of the design scenario that Show's capture does before it takes its pictures: the selected presentation open and live.
    private func runDesignScenarioSeed(workspace: WorkspaceModel) async {
        workspace.setMode(.show)
        workspace.selectSlide(2)
        await workspace.goLive()
        workspace.selectSlide(3)
    }
}
#endif
