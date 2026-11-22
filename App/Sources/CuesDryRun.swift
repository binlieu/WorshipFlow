// UI-006g (CU-22): the bar's "Dry run" button and its popover. The design's "Test in Preview" has no Preview-only run to call (a macro's
// steps act on the Look, the props, the timers and the live show, and there is no second set of those for Preview), so this does the part
// that can be told truthfully: it lists, in the order Run would deliver them and with their waits, what Run would do, from the macro as
// saved and the Looks, props, timers and media as they are now. It sends nothing to any screen, logs nothing and starts no timer.
import SwiftUI
import CueEngine
import OperatorCore

struct CuesDryRunButton: View {
    let app: AppModel
    let cue: CueModel
    let macroID: UUID
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            // ui.css `.btn` with the design's small play icon; 126.9 pt wide in all (padding 11 each side).
            HStack(spacing: 6) {
                Image(systemName: "play").font(.wf(11)).frame(width: 15, height: 15)
                Text("Dry run").wfLine()
            }
            .frame(width: 104.9)
        }
        .buttonStyle(HeaderButtonStyle())
        .wfRect("main.test", size: 12, weight: 500, radius: Radius.md)
        .help("Show what Run would do, in order, without sending anything to a screen")
        .accessibilityLabel("Dry run")
        .accessibilityHint("Lists what Run would do. Nothing is sent to any screen.")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            CuesDryRunPopover(summary: cue.dryRun(of: macroID, choices: app.cueChoices()))
        }
    }
}

private struct CuesDryRunPopover: View {
    let summary: CueDryRunSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dry run").font(.wf(14, .bold)).accessibilityAddTraits(.isHeader)
            Text("Nothing is sent to any screen. This is the order Run would use, from the macro as saved and the Looks, props, timers and media as they are now.")
                .font(.wf(12)).foregroundStyle(Tok.muted).fixedSize(horizontal: false, vertical: true)
            if let summary {
                HStack(spacing: 8) {
                    Text(summary.headline).font(.wf(13, .semibold))
                    ScreenTags(screens: summary.screens)
                }
                .accessibilityElement(children: .combine)
                ForEach(summary.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel(group.when)
                        ForEach(group.lines) { line in lineView(line) }
                    }
                }
                if summary.brokenCount > 0 {
                    warning("\(summary.brokenCount) step\(summary.brokenCount == 1 ? "" : "s") point\(summary.brokenCount == 1 ? "s" : "") at something that is gone or not valid. Run would fail on \(summary.brokenCount == 1 ? "it" : "them") and carry on.")
                }
                ForEach(Array(summary.issues.enumerated()), id: \.offset) { _, text in warning(text) }
            } else {
                Text("This macro no longer exists.").font(.wf(12)).foregroundStyle(Tok.warning)
            }
        }
        .padding(14).frame(width: 400, alignment: .leading)
    }

    private func lineView(_ line: CueDryRunLine) -> some View {
        HStack(spacing: 8) {
            Text("\(line.number)").font(.wf(11, .bold).monospacedDigit()).frame(width: 20, height: 20)
                .background(Tok.surface3, in: Circle()).accessibilityHidden(true)
            Text(line.title).font(.wf(12, .bold)).lineLimit(1)
            Text(line.detail).font(.wf(12)).foregroundStyle(line.isBroken ? Tok.warning : Tok.muted).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            ScreenTags(screens: line.screens)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(line.number): \(line.title) \(line.detail)" + (line.isBroken ? ", broken" : ""))
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.wf(11)).foregroundStyle(Tok.warning).accessibilityHidden(true)
            Text(text).font(.wf(12)).foregroundStyle(Tok.warning).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
