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
            HStack(spacing: Space.s4) {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Image(systemName: row.kindLabel == "Elapsed" ? "clock" : "timer").font(.system(size: 11)).foregroundStyle(Tok.muted)
                            .accessibilityHidden(true)
                        Text(row.name).font(.system(size: 12)).foregroundStyle(Tok.muted).lineLimit(1).frame(maxWidth: 90, alignment: .leading)
                        Text(row.text).font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(row.isOverrun ? Tok.warning : (row.isRunning ? Tok.cyan : Tok.text))
                        if row.canToggle {
                            Button { stage.toggleToolbarTimer(row.id) } label: {
                                Image(systemName: row.isRunning ? "pause.fill" : "play.fill").font(.system(size: 10))
                                    .frame(width: 22, height: 18)
                            }
                            .buttonStyle(.plain).foregroundStyle(Tok.text)
                            .wfOutline(RoundedRectangle(cornerRadius: Radius.sm), stroke: Tok.borderStrong)
                            .help(row.isRunning ? "Pause \(row.name)" : "Start \(row.name)")
                            .accessibilityLabel(row.isRunning ? "Pause \(row.name)" : "Start \(row.name)")
                        }
                    }
                    .fixedSize()
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.name) \(row.text)\(row.isOverrun ? ", over time" : "")")
                }
            }
            .padding(.horizontal, Space.s4).frame(height: 28)
            .wfOutline(RoundedRectangle(cornerRadius: Radius.xl), stroke: Tok.border, fill: Tok.surface2)
            .padding(1)   // room inside the toolbar item, which clips to its bounds
        }
    }
}
