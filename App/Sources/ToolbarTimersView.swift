// UI-003 Part 1: timers in the toolbar, beside the AUD, STG and BRD pills, in every mode. The timers shown are the ones
// the operator marked ("In toolbar" in the Timers panel); by default the first elapsed timer and the first countdown.
// A countdown has a start or pause button. Overrun uses the warning colour, never red. No timers: nothing is drawn.
import SwiftUI
import OperatorCore

struct ToolbarTimersView: View {
    @Bindable var stage: StageModel

    var body: some View {
        let _ = stage.toolbarRevision
        let anyRunning = stage.timers.contains(where: \.isRunning)
        // Redraws every second only while something runs; otherwise a stopped timer is drawn once.
        if anyRunning {
            TimelineView(.periodic(from: .now, by: 1)) { _ in content }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        let rows = stage.toolbarTimerRows(at: stage.nowSeconds)
        if !rows.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Rectangle().fill(Tok.border).frame(width: 1, height: 16).wfRect("tb.timer.\(index).sep").padding(.horizontal, 2) }
                    HStack(spacing: 6) {
                        Image(systemName: row.kindLabel == "Elapsed" ? "clock" : "timer").font(.wf(12)).foregroundStyle(Tok.muted).frame(width: 12, height: 12)
                            .wfRect("tb.timer.\(index).icon")
                            .accessibilityHidden(true)
                        Text(row.name).font(.wf(11)).lineLimit(1).wfLine().frame(maxWidth: 90, alignment: .leading).wfRect("tb.timer.\(index).name", size: 11, weight: 400)
                        // The picture: the value in the text colour (muted while it is not running, warning on overrun, never red).
                        Text(row.toolbarText).font(.wfMono(13, .bold)).wfLine()
                            .foregroundStyle(row.isOverrun ? Tok.warning : (row.isRunning || row.canToggle == false ? Tok.text : Tok.text))
                            .wfRect("tb.timer.\(index).value", size: 13, weight: 700)
                        if row.canToggle {
                            Button { stage.toggleToolbarTimer(row.id) } label: {
                                Image(systemName: row.isRunning ? "pause.fill" : "play.fill").font(.wf(10))
                                    .frame(width: 12, height: 12).frame(width: 26, height: 20)
                            }
                            .buttonStyle(.plain).foregroundStyle(Tok.text)
                            .wfOutline(RoundedRectangle(cornerRadius: Radius.md), stroke: Tok.borderStrong)
                            .wfRect("tb.timer.\(index).button", radius: Radius.md)
                            .help(row.isRunning ? "Pause \(row.name)" : "Start \(row.name)")
                            .accessibilityLabel(row.isRunning ? "Pause \(row.name)" : "Start \(row.name)")
                        }
                    }
                    .foregroundStyle(Tok.muted)
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.name) \(row.toolbarText)\(row.isOverrun ? ", over time" : "")")
                }
            }
            .padding(.horizontal, 9).frame(height: 28)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.track), stroke: Tok.border, fill: Tok.surface2)
            .wfRect("tb.timers", radius: Radius.track)   // room inside the toolbar item, which clips to its bounds
        }
    }
}
