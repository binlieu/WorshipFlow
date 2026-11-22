// UI-006g (CU-21): the bar's Trigger field, as a menu that chooses the macro's function key. The text is the design's
// "Trigger: F1 · MIDI note C2": the key (bold) and the MIDI pads that run the macro.
import SwiftUI
import CueEngine
import OperatorCore

struct CuesTriggerField: View {
    let cue: CueModel
    let macro: Macro

    var body: some View {
        let key = cue.keyTriggers.key(for: macro.id)
        let pads = cue.bindings.bindings.filter { $0.command == .macro(macro.id) }.map { MIDIText.pattern($0.pattern) }
        let summary = CueTriggerText.summary(key: key, midi: pads)
        Menu {
            Button { choose(nil) } label: { entry("No key", on: key == nil) }
            Divider()
            ForEach(CueFunctionKey.allCases) { candidate in
                let holder = cue.keyTriggers.holder(of: candidate).flatMap { $0 == macro.id ? nil : cue.macro($0)?.name }
                Button { choose(candidate) } label: {
                    entry(holder.map { "\(candidate.label) \u{2014} takes it from \($0)" } ?? candidate.label, on: key == candidate)
                }
            }
        } label: {
            label(key: key, summary: summary)
                .lineLimit(1).wfLine().wfField().wfRect("main.trigger", size: 12, weight: 400, radius: Radius.md)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Choose the function key that runs this macro. It works when no text field has focus.")
        .accessibilityLabel("Trigger")
        .accessibilityValue(summary)
    }

    /// The key is bold, as the design's `<b>`.
    private func label(key: CueFunctionKey?, summary: String) -> Text {
        guard let key, summary.hasPrefix(key.label) else { return Text("Trigger: \(summary)") }
        return Text("Trigger: ") + Text(key.label).bold() + Text(String(summary.dropFirst(key.label.count)))
    }

    @ViewBuilder private func entry(_ text: String, on: Bool) -> some View {
        if on { Label(text, systemImage: "checkmark") } else { Text(text) }
    }

    private func choose(_ key: CueFunctionKey?) {
        Task { @MainActor in await cue.setKey(key, for: macro.id) }
    }
}
